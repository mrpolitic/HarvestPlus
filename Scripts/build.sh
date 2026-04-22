#!/bin/bash
#
# build.sh — produce a distributable HarvestPlus .app.zip.
#
# Tuned for ad-hoc distribution (no paid Apple Developer Program). The zip is
# installed into /Applications by Scripts/install.sh, which strips the
# quarantine xattr before first launch — so coworkers never see Gatekeeper
# prompts on macOS 14+ (including 15/Sequoia+, which removed the right-click
# → Open escape hatch).
#
# Pipeline:
#   1. xcodebuild archive (ad-hoc signed) → build/HarvestPlus.xcarchive
#   2. Pull .app from xcarchive/Products/Applications/
#   3. ditto -c -k --sequesterRsrc --keepParent → build/HarvestPlus.app.zip
#      (+ a versioned copy build/HarvestPlus-<version>.app.zip for humans)
#
# The file you ship to GitHub Releases:
#   build/HarvestPlus.app.zip
#   (The install script always fetches this fixed name from /releases/latest.)
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
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/HarvestPlus.xcodeproj"
BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/HarvestPlus.xcarchive"

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
require ditto

if ! xcodebuild -version >/dev/null 2>&1; then
    die "xcodebuild is not usable. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

[ -d "$PROJECT" ] || die "Xcode project not found at $PROJECT"

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

# Fixed name — the install script curls this exact filename from /releases/latest.
ZIP_FIXED="$BUILD_DIR/${PRODUCT_NAME}.app.zip"
# Versioned copy — for humans browsing the Releases page.
ZIP_VERSIONED="$BUILD_DIR/${PRODUCT_NAME}-${MARKETING_VERSION}.app.zip"

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

APP_EXPORTED="$ARCHIVE_PATH/Products/Applications/${PRODUCT_NAME}.app"
[ -d "$APP_EXPORTED" ] || die "Built .app not found at $APP_EXPORTED"
ok "Built app → $APP_EXPORTED"

if ! codesign --verify --deep --strict --verbose=1 "$APP_EXPORTED" >/dev/null 2>&1; then
    die "Built .app failed codesign verification."
fi

if ! codesign --display --verbose=4 "$APP_EXPORTED" 2>&1 | grep -q "flags=0x10000(runtime)"; then
    warn "Hardened Runtime flag not detected on the built .app."
fi

# ---------------------------------------------------------------------------
# 3) Zip the .app (the only release asset)
# ---------------------------------------------------------------------------

log "Zipping → $ZIP_FIXED"
rm -f "$ZIP_FIXED" "$ZIP_VERSIONED"

# --keepParent keeps HarvestPlus.app/ as the top-level entry inside the zip,
# so `ditto -x -k <zip> /Applications` lands the .app at /Applications/HarvestPlus.app.
# --sequesterRsrc stores HFS metadata in a way that unzips cleanly on all macOS
# versions (including Finder-based Archive Utility).
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_EXPORTED" "$ZIP_FIXED"

# Second copy with the version in the filename, for humans.
cp "$ZIP_FIXED" "$ZIP_VERSIONED"

ok "Zip → $ZIP_FIXED"
ok "Zip → $ZIP_VERSIONED"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

SIZE_HUMAN="$(du -h "$ZIP_FIXED" | awk '{ print $1 }')"
cat <<EOF

──────────────────────────────────────────────────────────
  HarvestPlus ${MARKETING_VERSION} (build ${BUILD_NUMBER})
  Built app     : $APP_EXPORTED
  Release asset : $ZIP_FIXED             (${SIZE_HUMAN})
  Versioned copy: $ZIP_VERSIONED

  Coworkers install with one Terminal command:
    curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash

  Next step — publish on GitHub:
    git tag v${MARKETING_VERSION}
    git push origin v${MARKETING_VERSION}
    gh release create v${MARKETING_VERSION} \\
        "$ZIP_FIXED" "$ZIP_VERSIONED" \\
        --title "HarvestPlus ${MARKETING_VERSION}" \\
        --notes-file CHANGELOG.md

  See RELEASING.md for the full checklist.
──────────────────────────────────────────────────────────

EOF
