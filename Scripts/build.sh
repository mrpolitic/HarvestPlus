#!/bin/bash
#
# build.sh – produce a signed + notarized + stapled HarvestPlus .app.zip.
#
# Pipeline:
#   1. xcodebuild archive, signed with the Developer ID Application cert
#      (hardened runtime + entitlements, both already on the build config).
#   2. ditto-zip the .app and submit to Apple's notary service via
#      `xcrun notarytool submit --wait`.
#   3. `xcrun stapler staple` the returned ticket onto the .app so Gatekeeper
#      accepts it offline.
#   4. ditto-zip the stapled .app for distribution.
#
# The file you ship to GitHub Releases:
#   build/HarvestPlus.app.zip
#   (The install script always fetches this fixed name from /releases/latest.)
#
# Prerequisites (one-time setup on this machine):
#   - Developer ID Application cert installed in the login keychain.
#     Verify: security find-identity -v -p codesigning | grep "Developer ID"
#   - notarytool profile "AC_NOTARY" stored in the keychain.
#     Create: xcrun notarytool store-credentials AC_NOTARY \
#                 --apple-id <you> --team-id <team> --password <app-spec-pw>
#
# Usage:
#   ./Scripts/build.sh                # full signed + notarized build
#   ./Scripts/build.sh --clean        # wipe build/ first
#
# Environment overrides (optional):
#   CONFIGURATION       Release (default) | Debug
#   SCHEME              HarvestPlus (default)
#   PRODUCT_NAME        HarvestPlus (default)
#   BUNDLE_IDENTIFIER   com.qampo.HarvestPlus (default)
#   CODE_SIGN_IDENTITY  Developer ID Application cert name
#   DEVELOPMENT_TEAM    PA8H58YHD6 (default)
#   NOTARY_PROFILE      AC_NOTARY (the keychain profile name)
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
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: Martin Razvan Politic (PA8H58YHD6)}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-PA8H58YHD6}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
# Developer ID Provisioning Profile registered against com.qampo.HarvestPlus.
# Required so the embedded `keychain-access-groups` entitlement is honoured
# (data-protection keychain). xcodebuild looks this up by name in
# ~/Library/MobileDevice/Provisioning Profiles/ and embeds it inside the
# .app as Contents/embedded.provisionprofile.
PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_SPECIFIER:-HarvestPlus Developer ID}"

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
require security

if ! xcodebuild -version >/dev/null 2>&1; then
    die "xcodebuild is not usable. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

[ -d "$PROJECT" ] || die "Xcode project not found at $PROJECT"

if [ "${1:-}" = "--clean" ]; then
    log "Cleaning $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

# Verify the signing identity exists in the keychain
if ! security find-identity -v -p codesigning | grep -q "$CODE_SIGN_IDENTITY"; then
    die "Code signing identity not found in keychain: $CODE_SIGN_IDENTITY"
fi

# Verify the notary profile is present
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    die "notarytool profile '$NOTARY_PROFILE' not configured. See header for setup."
fi

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

# Fixed name – the install script curls this exact filename from /releases/latest.
ZIP_FIXED="$BUILD_DIR/${PRODUCT_NAME}.app.zip"
# Versioned copy – for humans browsing the Releases page.
ZIP_VERSIONED="$BUILD_DIR/${PRODUCT_NAME}-${MARKETING_VERSION}.app.zip"

ok "Building ${PRODUCT_NAME} ${MARKETING_VERSION} (build ${BUILD_NUMBER})"
log "Signing identity     : $CODE_SIGN_IDENTITY"
log "Provisioning profile : $PROVISIONING_PROFILE_SPECIFIER"
log "Notary profile       : $NOTARY_PROFILE"

# ---------------------------------------------------------------------------
# 1) Archive (Developer ID signed, hardened runtime)
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
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE_SPECIFIER" \
        > "$ARCHIVE_LOG" 2>&1; then
    tail -80 "$ARCHIVE_LOG" >&2
    die "xcodebuild archive failed (full log: $ARCHIVE_LOG)"
fi
ok "Archive → $ARCHIVE_PATH"

# ---------------------------------------------------------------------------
# 2) Pull .app from the archive and verify the signature
# ---------------------------------------------------------------------------

APP_EXPORTED="$ARCHIVE_PATH/Products/Applications/${PRODUCT_NAME}.app"
[ -d "$APP_EXPORTED" ] || die "Built .app not found at $APP_EXPORTED"
ok "Built app → $APP_EXPORTED"

# ---------------------------------------------------------------------------
# 2.5) Re-sign Sparkle's nested binaries with our Developer ID
# ---------------------------------------------------------------------------
#
# Sparkle 2 ships as a precompiled framework via SPM. Its embedded helpers
# (Updater.app, Autoupdate, Installer.xpc, Downloader.xpc) come pre-signed
# by the Sparkle project's own identity, which Apple's notary rejects with
# "not signed with a valid Developer ID certificate". Re-sign each helper
# from the inside out with our Developer ID, hardened runtime, and a secure
# timestamp, then re-seal the outer .app.
#
# This is required for every release. Without it the build will succeed
# locally but notarization rejects the archive.

SPARKLE_FW="$APP_EXPORTED/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    log "Re-signing Sparkle's nested binaries with Developer ID + timestamp…"

    # Order matters: sign each contained binary/bundle before its parent.
    SPARKLE_TARGETS=(
        "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
        "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"
        "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
        "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"
        "$SPARKLE_FW/Versions/B/Updater.app/Contents/MacOS/Updater"
        "$SPARKLE_FW/Versions/B/Updater.app"
        "$SPARKLE_FW/Versions/B/Autoupdate"
        "$SPARKLE_FW"
    )
    for target in "${SPARKLE_TARGETS[@]}"; do
        [ -e "$target" ] || continue
        codesign --force --timestamp --options runtime \
            --sign "$CODE_SIGN_IDENTITY" "$target" \
            >/dev/null 2>&1 || die "Failed to re-sign $target"
    done

    # Re-sign the outer .app – its embedded framework just changed, so the
    # original signature is no longer valid. Re-apply our entitlements.
    #
    # CRITICAL: codesign (unlike Xcode) does NOT expand build variables. The
    # source .entitlements uses $(AppIdentifierPrefix) for the keychain-access
    # group; passing it raw bakes in the LITERAL "$(AppIdentifierPrefix)…"
    # string, which AMFI rejects at process spawn on every machine
    # ("Launchd job spawn failed" / RBSRequestErrorDomain 5) – and it slips past
    # codesign --verify, spctl, AND Apple notarization, so it only surfaces when
    # a user actually launches the downloaded app. Resolve the prefix to the
    # team id (== $(AppIdentifierPrefix) for this single-team Developer ID app)
    # before signing.
    RESIGN_ENTITLEMENTS="$BUILD_DIR/resign.entitlements"
    sed "s#\$(AppIdentifierPrefix)#${DEVELOPMENT_TEAM}.#g" \
        "$REPO_ROOT/HarvestPlus/HarvestPlus.entitlements" > "$RESIGN_ENTITLEMENTS"
    codesign --force --timestamp --options runtime \
        --entitlements "$RESIGN_ENTITLEMENTS" \
        --sign "$CODE_SIGN_IDENTITY" "$APP_EXPORTED" \
        >/dev/null 2>&1 || die "Failed to re-sign HarvestPlus.app after Sparkle re-sign"
    ok "Sparkle helpers + outer .app re-signed for notarization."
fi

# Guard: the embedded entitlements must carry a fully-resolved keychain-access
# group. An unexpanded $(AppIdentifierPrefix) here is the difference between an
# app that launches and one AMFI kills at spawn – and notarization won't catch
# it. Fail the build loudly rather than ship an app nobody can open.
EMBEDDED_ENT="$(codesign -d --entitlements :- "$APP_EXPORTED" 2>/dev/null)"
if printf '%s' "$EMBEDDED_ENT" | grep -q 'AppIdentifierPrefix'; then
    die "Embedded entitlements contain an unexpanded \$(AppIdentifierPrefix) – the app would fail to launch (AMFI). Aborting."
fi
if ! printf '%s' "$EMBEDDED_ENT" | grep -q "${DEVELOPMENT_TEAM}\.com\.qampo\.HarvestPlus"; then
    die "Embedded keychain-access-group is missing the expected ${DEVELOPMENT_TEAM}. prefix. Aborting."
fi
ok "Entitlements verified (keychain-access-group prefix resolved)."

if ! codesign --verify --deep --strict --verbose=1 "$APP_EXPORTED" >/dev/null 2>&1; then
    die "Built .app failed codesign verification."
fi

SIGN_INFO="$(codesign --display --verbose=4 "$APP_EXPORTED" 2>&1)"
if ! printf '%s\n' "$SIGN_INFO" | grep -qF "0x10000"; then
    printf '%s\n' "$SIGN_INFO" >&2
    die "Hardened Runtime flag not detected on the built .app – notary will reject."
fi
ok "Signature verified (Developer ID, hardened runtime)"

# ---------------------------------------------------------------------------
# 3) Zip + submit to Apple's notary service
# ---------------------------------------------------------------------------

NOTARIZE_ZIP="$BUILD_DIR/${PRODUCT_NAME}-for-notarization.zip"
log "Packaging for notary submission → $NOTARIZE_ZIP"
rm -f "$NOTARIZE_ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_EXPORTED" "$NOTARIZE_ZIP"

log "Submitting to Apple's notary service (typically 1–3 min)…"
NOTARIZE_LOG="$BUILD_DIR/notarize.log"
if ! xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        > "$NOTARIZE_LOG" 2>&1; then
    cat "$NOTARIZE_LOG" >&2
    die "Notarization submission failed (full log: $NOTARIZE_LOG)"
fi

if ! grep -q "status: Accepted" "$NOTARIZE_LOG"; then
    cat "$NOTARIZE_LOG" >&2
    SUBMISSION_ID="$(awk -F': ' '/^  id:/ { print $2; exit }' "$NOTARIZE_LOG")"
    if [ -n "$SUBMISSION_ID" ]; then
        warn "Fetching detailed notarization log for $SUBMISSION_ID…"
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    die "Notarization rejected. See above for Apple's reason."
fi
ok "Notarization accepted by Apple."
rm -f "$NOTARIZE_ZIP"

# ---------------------------------------------------------------------------
# 4) Staple the ticket so Gatekeeper accepts the app offline
# ---------------------------------------------------------------------------

log "Stapling notarization ticket to the .app…"
STAPLE_LOG="$BUILD_DIR/staple.log"
if ! xcrun stapler staple "$APP_EXPORTED" > "$STAPLE_LOG" 2>&1; then
    cat "$STAPLE_LOG" >&2
    die "Stapling failed."
fi
xcrun stapler validate "$APP_EXPORTED" >/dev/null || die "Stapler validation failed."
ok "Ticket stapled – Gatekeeper will accept this offline."

if spctl --assess --type execute --verbose "$APP_EXPORTED" 2>&1 | grep -q "accepted"; then
    ok "Gatekeeper assessment: accepted."
else
    warn "Gatekeeper assessment did not return 'accepted' – investigate before shipping."
fi

# ---------------------------------------------------------------------------
# 5) Final zip for distribution
# ---------------------------------------------------------------------------

log "Zipping for release → $ZIP_FIXED"
rm -f "$ZIP_FIXED" "$ZIP_VERSIONED"

# --keepParent keeps HarvestPlus.app/ as the top-level entry inside the zip,
# so `ditto -x -k <zip> /Applications` lands the .app at /Applications/HarvestPlus.app.
# --sequesterRsrc stores HFS metadata in a way that unzips cleanly on all macOS
# versions (including Finder-based Archive Utility).
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_EXPORTED" "$ZIP_FIXED"
cp "$ZIP_FIXED" "$ZIP_VERSIONED"

ok "Zip → $ZIP_FIXED"
ok "Zip → $ZIP_VERSIONED"

# ---------------------------------------------------------------------------
# 6) Sparkle: sign the release zip and (re)write appcast.xml
# ---------------------------------------------------------------------------
#
# Sparkle expects each release zip to carry an EdDSA signature (separate from
# the Apple Developer ID code signature, layered on top of it). The private
# half of the keypair lives in the maintainer's login keychain – set up once
# via `Sparkle/bin/generate_keys`. `sign_update` reads it directly; we never
# see or pass the key material.
#
# The appcast.xml file at the repo root is what Sparkle on every installed
# client polls. We rewrite it after each build to point at the new release.

# Sparkle ships its CLI tools as part of the SPM artifact bundle. Locate them
# under DerivedData. Robust to Xcode's hash-suffixed project folder name.
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -type d -path "*/sparkle/Sparkle/bin" 2>/dev/null | head -1)"
[ -d "$SPARKLE_BIN" ] || die "Couldn't find Sparkle's bin/ in DerivedData. Open the project in Xcode once so SPM caches its artifacts."

log "Signing release zip with Sparkle's EdDSA key…"
SIGN_OUTPUT="$("$SPARKLE_BIN/sign_update" "$ZIP_FIXED")"
# sign_update prints a fragment like:
#   sparkle:edSignature="…" length="…"
ED_SIG="$(printf '%s' "$SIGN_OUTPUT" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')"
ZIP_LENGTH="$(printf '%s' "$SIGN_OUTPUT" | sed -E 's/.*length="([^"]+)".*/\1/')"
[ -n "$ED_SIG" ]    || die "Couldn't extract EdDSA signature from sign_update output: $SIGN_OUTPUT"
[ -n "$ZIP_LENGTH" ]|| die "Couldn't extract length from sign_update output: $SIGN_OUTPUT"

APPCAST="$REPO_ROOT/appcast.xml"
PUB_DATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
RELEASE_URL="https://github.com/mrpolitic/HarvestPlus/releases/download/v${MARKETING_VERSION}/HarvestPlus.app.zip"

# Extract the CHANGELOG section for this version, if present. The appcast
# carries it inside CDATA so Sparkle's release-notes pane can render it.
NOTES="$(awk -v ver="$MARKETING_VERSION" '
    /^## \[/ {
        if (in_section) { exit }
        if (index($0, "[" ver "]") > 0) { in_section = 1; next }
    }
    in_section { print }
' "$REPO_ROOT/CHANGELOG.md" 2>/dev/null || true)"
[ -n "$NOTES" ] || NOTES="Release ${MARKETING_VERSION}."

log "Writing appcast.xml → $APPCAST"
cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>HarvestPlus</title>
        <link>https://github.com/mrpolitic/HarvestPlus</link>
        <description>HarvestPlus update feed.</description>
        <language>en</language>
        <item>
            <title>Version ${MARKETING_VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <description><![CDATA[
${NOTES}
            ]]></description>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${RELEASE_URL}"
                sparkle:version="${BUILD_NUMBER}"
                sparkle:shortVersionString="${MARKETING_VERSION}"
                length="${ZIP_LENGTH}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIG}" />
        </item>
    </channel>
</rss>
EOF

ok "Sparkle signature: ${ED_SIG:0:24}… (length ${ZIP_LENGTH})"
ok "appcast.xml updated. Commit it to main alongside the GitHub release."

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

  Signed    : ${CODE_SIGN_IDENTITY}
  Notarized : yes (ticket stapled)

  Coworkers install with one Terminal command:
    curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash

  Next step – publish on GitHub:
    git tag v${MARKETING_VERSION}
    git push origin v${MARKETING_VERSION}
    gh release create v${MARKETING_VERSION} \\
        "$ZIP_FIXED" "$ZIP_VERSIONED" \\
        --title "HarvestPlus ${MARKETING_VERSION}" \\
        --notes-file CHANGELOG.md

  See RELEASING.md for the full checklist.
──────────────────────────────────────────────────────────

EOF
