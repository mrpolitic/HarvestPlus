#!/bin/bash
#
# build.sh — produce a distributable HarvestPlus installer package.
#
# This script is tuned for **ad-hoc distribution** — no paid Apple Developer
# Program account is required. The app is ad-hoc signed (CODE_SIGN_IDENTITY=-)
# and the .pkg is unsigned. Coworkers right-click → Open the .pkg once on
# first install; the postinstall step strips com.apple.quarantine so the
# installed app launches without prompts thereafter.
#
# Pipeline:
#   1. xcodebuild archive (ad-hoc signed) → build/HarvestPlus.xcarchive
#   2. Pull .app directly from xcarchive/Products/Applications/
#      (no xcodebuild -exportArchive — that step requires Developer ID)
#   3. pkgbuild (unsigned) → build/HarvestPlus-<version>.pkg
#      (postinstall.sh inside the pkg strips the quarantine xattr on install)
#
# The one output you ship to coworkers: build/HarvestPlus-<version>.pkg
#
# Usage:
#   ./Scripts/build.sh                # full build
#   ./Scripts/build.sh --clean        # wipe build/ first
#
# Environment overrides (optional):
#   CONFIGURATION       Release (default) | Debug
#   SCHEME              HarvestPlus (default)
#   PRODUCT_NAME        HarvestPlus (default)
#   BUNDLE_IDENTIFIER   com.qampo.HarvestPlus (default)
#
#   CODE_SIGN_IDENTITY  "-" for ad-hoc (default), or a Developer ID
#                       Application cert name if you ever join the paid
#                       Apple Developer Program.
#   INSTALLER_IDENTITY  Unset by default → unsigned .pkg. Set to a
#                       "Developer ID Installer: …" cert name to sign.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Resolve the repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/HarvestPlus.xcodeproj"
BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/HarvestPlus.xcarchive"
STAGING_ROOT="$BUILD_DIR/pkgroot"
STAGING_SCRIPTS="$BUILD_DIR/pkgscripts"
POSTINSTALL_SRC="$SCRIPT_DIR/postinstall.sh"

# ---------------------------------------------------------------------------
# Config (env-overridable)
# ---------------------------------------------------------------------------

CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-HarvestPlus}"
PRODUCT_NAME="${PRODUCT_NAME:-HarvestPlus}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.qampo.HarvestPlus}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"   # "-" = ad-hoc

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m✓\033[0m %s\n"  "$*"; }
warn() { printf "\033[1;33m!\033[0m %s\n"  "$*" >&2; }
die()  { printf "\033[1;31m✗\033[0m %s\n"  "$*" >&2; exit 1; }

require() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH."
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

require xcodebuild
require pkgbuild
require plutil

# Catch the classic "xcode-select still on CLT" footgun early.
if ! xcodebuild -version >/dev/null 2>&1; then
    die "xcodebuild is not usable. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

[ -d "$PROJECT" ]          || die "Xcode project not found at $PROJECT"
[ -f "$POSTINSTALL_SRC" ]  || die "postinstall.sh not found at $POSTINSTALL_SRC"

# Handle --clean
if [ "${1:-}" = "--clean" ]; then
    log "Cleaning $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Resolve marketing version (from project.pbxproj MARKETING_VERSION)
# ---------------------------------------------------------------------------

MARKETING_VERSION="$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings \
        -configuration "$CONFIGURATION" 2>/dev/null \
        | awk -F' = ' '/MARKETING_VERSION/ { print $2; exit }'
)"
[ -n "$MARKETING_VERSION" ] || die "Couldn't read MARKETING_VERSION from project."

BUILD_NUMBER="$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings \
        -configuration "$CONFIGURATION" 2>/dev/null \
        | awk -F' = ' '/CURRENT_PROJECT_VERSION/ { print $2; exit }'
)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

PKG_OUT="$BUILD_DIR/${PRODUCT_NAME}-${MARKETING_VERSION}.pkg"

ok "Building ${PRODUCT_NAME} ${MARKETING_VERSION} (build ${BUILD_NUMBER})"
if [ "$CODE_SIGN_IDENTITY" = "-" ]; then
    log "Code-signing identity: ad-hoc (no Apple Developer account required)"
else
    log "Code-signing identity: $CODE_SIGN_IDENTITY"
fi

# ---------------------------------------------------------------------------
# 1) Archive (ad-hoc signed)
# ---------------------------------------------------------------------------

log "Archiving (configuration: $CONFIGURATION)"

# Archive with clean output — route noisy logs to a file, surface only on failure.
ARCHIVE_LOG="$BUILD_DIR/archive.log"
if ! xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
        DEVELOPMENT_TEAM="" \
        > "$ARCHIVE_LOG" 2>&1; then
    tail -80 "$ARCHIVE_LOG" >&2
    die "xcodebuild archive failed (full log: $ARCHIVE_LOG)"
fi
ok "Archive → $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# 2) Pull .app from the archive
# ---------------------------------------------------------------------------

# Archive layout:
#   HarvestPlus.xcarchive/
#     Products/
#       Applications/
#         HarvestPlus.app   ← this
APP_EXPORTED="$ARCHIVE_PATH/Products/Applications/${PRODUCT_NAME}.app"
[ -d "$APP_EXPORTED" ] || die "Built .app not found at $APP_EXPORTED"
ok "Built app → $APP_EXPORTED"

# Sanity-check the signature (ad-hoc passes codesign verification).
if ! codesign --verify --deep --strict --verbose=1 "$APP_EXPORTED" >/dev/null 2>&1; then
    die "Built .app failed codesign verification."
fi

# Confirm Hardened Runtime is on — macOS will flag its absence at launch.
if ! codesign --display --verbose=4 "$APP_EXPORTED" 2>&1 | grep -q "flags=0x10000(runtime)"; then
    warn "Hardened Runtime flag not detected on the built .app."
fi

# ---------------------------------------------------------------------------
# 3) Build the .pkg with postinstall
# ---------------------------------------------------------------------------

log "Assembling installer root"

# pkgbuild lays out files at the package root; we want the .app installed to
# /Applications/HarvestPlus.app, so mirror that path in a staging dir.
rm -rf "$STAGING_ROOT" "$STAGING_SCRIPTS"
mkdir -p "$STAGING_ROOT/Applications"
mkdir -p "$STAGING_SCRIPTS"

# Copy the built .app into the staging root (preserve symlinks/perms with ditto).
/usr/bin/ditto "$APP_EXPORTED" "$STAGING_ROOT/Applications/${PRODUCT_NAME}.app"

# Scripts must be executable or pkgbuild silently ignores them.
cp "$POSTINSTALL_SRC" "$STAGING_SCRIPTS/postinstall"
chmod +x "$STAGING_SCRIPTS/postinstall"

# ---------------------------------------------------------------------------
# pkgbuild — unsigned by default, can be signed via INSTALLER_IDENTITY env
# ---------------------------------------------------------------------------

log "Building package → $PKG_OUT"

PKGBUILD_ARGS=(
    --root            "$STAGING_ROOT"
    --scripts         "$STAGING_SCRIPTS"
    --identifier      "${BUNDLE_IDENTIFIER}.pkg"
    --version         "$MARKETING_VERSION"
    --install-location "/"
)

if [ -n "${INSTALLER_IDENTITY:-}" ]; then
    ok "Signing installer with: $INSTALLER_IDENTITY"
    PKGBUILD_ARGS+=(--sign "$INSTALLER_IDENTITY")
else
    log "Building unsigned .pkg (set INSTALLER_IDENTITY to sign with Developer ID)"
fi

pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG_OUT"
ok "Package → $PKG_OUT"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

SIZE_HUMAN="$(du -h "$PKG_OUT" | awk '{ print $1 }')"
cat <<EOF

──────────────────────────────────────────────────────────
  HarvestPlus ${MARKETING_VERSION} (build ${BUILD_NUMBER})
  Built app     : $APP_EXPORTED
  Installer     : $PKG_OUT  (${SIZE_HUMAN})

  Coworkers will need to right-click → Open the .pkg on first
  install (it's unsigned). After install, the app launches
  prompt-free — the postinstall script strips quarantine.

  Next step — publish on GitHub:
    git tag v${MARKETING_VERSION}
    git push origin v${MARKETING_VERSION}
    gh release create v${MARKETING_VERSION} "$PKG_OUT" \\
        --title "HarvestPlus ${MARKETING_VERSION}" \\
        --notes-file CHANGELOG.md

  See RELEASING.md for the full checklist.
──────────────────────────────────────────────────────────

EOF
