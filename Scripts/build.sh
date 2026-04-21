#!/bin/bash
#
# build.sh — produce a distributable HarvestPlus installer package.
#
# Pipeline:
#   1. xcodebuild archive        → build/HarvestPlus.xcarchive
#   2. xcodebuild -exportArchive → build/Export/HarvestPlus.app   (Developer ID signed)
#   3. pkgbuild                  → build/HarvestPlus-<version>.pkg
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
#   TEAM_ID             PA8H58YHD6 (default — must match ExportOptions.plist)
#   INSTALLER_IDENTITY  Auto-detected "Developer ID Installer: …" from keychain.
#                       Set explicitly to override, or set to "" to skip signing
#                       the .pkg (not recommended — Gatekeeper will warn).
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
EXPORT_DIR="$BUILD_DIR/Export"
STAGING_ROOT="$BUILD_DIR/pkgroot"
STAGING_SCRIPTS="$BUILD_DIR/pkgscripts"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
POSTINSTALL_SRC="$SCRIPT_DIR/postinstall.sh"

# ---------------------------------------------------------------------------
# Config (env-overridable)
# ---------------------------------------------------------------------------

CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-HarvestPlus}"
PRODUCT_NAME="${PRODUCT_NAME:-HarvestPlus}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.qampo.HarvestPlus}"
TEAM_ID="${TEAM_ID:-PA8H58YHD6}"

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
require security

[ -d "$PROJECT" ]          || die "Xcode project not found at $PROJECT"
[ -f "$EXPORT_OPTIONS" ]   || die "ExportOptions.plist not found at $EXPORT_OPTIONS"
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

# ---------------------------------------------------------------------------
# 1) Archive
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
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        > "$ARCHIVE_LOG" 2>&1; then
    tail -80 "$ARCHIVE_LOG" >&2
    die "xcodebuild archive failed (full log: $ARCHIVE_LOG)"
fi
ok "Archive → $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# 2) Export signed .app
# ---------------------------------------------------------------------------

log "Exporting Developer ID-signed .app"

rm -rf "$EXPORT_DIR"
EXPORT_LOG="$BUILD_DIR/export.log"
if ! xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        > "$EXPORT_LOG" 2>&1; then
    tail -80 "$EXPORT_LOG" >&2
    die "xcodebuild -exportArchive failed (full log: $EXPORT_LOG)"
fi

APP_EXPORTED="$EXPORT_DIR/${PRODUCT_NAME}.app"
[ -d "$APP_EXPORTED" ] || die "Exported .app not found at $APP_EXPORTED"
ok "Signed app → $APP_EXPORTED"

# Sanity-check the signature and hardened runtime
if ! codesign --verify --deep --strict --verbose=1 "$APP_EXPORTED" >/dev/null 2>&1; then
    die "Exported .app failed codesign verification."
fi
if ! codesign --display --verbose=4 "$APP_EXPORTED" 2>&1 | grep -q "flags=0x10000(runtime)"; then
    warn "Hardened Runtime flag not detected — notarisation will be rejected."
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

# Copy the signed .app into the staging root (preserve symlinks/perms with ditto).
/usr/bin/ditto "$APP_EXPORTED" "$STAGING_ROOT/Applications/${PRODUCT_NAME}.app"

# Scripts must be executable or pkgbuild silently ignores them.
cp "$POSTINSTALL_SRC" "$STAGING_SCRIPTS/postinstall"
chmod +x "$STAGING_SCRIPTS/postinstall"

# ---------------------------------------------------------------------------
# Detect Developer ID Installer identity (optional but strongly preferred)
# ---------------------------------------------------------------------------

if [ -z "${INSTALLER_IDENTITY+x}" ]; then
    # Auto-detect the first matching identity in the default keychain search list.
    INSTALLER_IDENTITY="$(
        security find-identity -v -p basic 2>/dev/null \
            | awk -F'"' '/Developer ID Installer/ { print $2; exit }'
    )"
fi

log "Building package → $PKG_OUT"

PKGBUILD_ARGS=(
    --root            "$STAGING_ROOT"
    --scripts         "$STAGING_SCRIPTS"
    --identifier      "${BUNDLE_IDENTIFIER}.pkg"
    --version         "$MARKETING_VERSION"
    --install-location "/"
)

if [ -n "$INSTALLER_IDENTITY" ]; then
    ok "Signing installer with: $INSTALLER_IDENTITY"
    PKGBUILD_ARGS+=(--sign "$INSTALLER_IDENTITY")
else
    warn "No 'Developer ID Installer' identity found — building UNSIGNED .pkg."
    warn "Coworkers will see a Gatekeeper warning. Import your installer cert"
    warn "into login.keychain or set INSTALLER_IDENTITY to skip this warning."
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
  Signed .app   : $APP_EXPORTED
  Installer     : $PKG_OUT  (${SIZE_HUMAN})

  Next steps:
    • (Recommended) Notarise:
        xcrun notarytool submit "$PKG_OUT" \\
            --apple-id <your@appleid> \\
            --team-id $TEAM_ID \\
            --password <app-specific-password> \\
            --wait
        xcrun stapler staple "$PKG_OUT"

    • Publish on GitHub:
        gh release create v${MARKETING_VERSION} "$PKG_OUT" \\
            --title "HarvestPlus ${MARKETING_VERSION}" \\
            --notes-file CHANGELOG.md

  See RELEASING.md for the full checklist.
──────────────────────────────────────────────────────────

EOF
