#!/usr/bin/env bash
#
# install.sh – one-shot HarvestPlus installer.
#
# Usage (copy-paste into Terminal):
#
#   Per-user install (default, no admin password needed):
#     curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash
#
#   System-wide install (/Applications, requires admin password):
#     curl -fsSL https://raw.githubusercontent.com/mrpolitic/HarvestPlus/main/Scripts/install.sh | bash -s -- --system
#
# What it does:
#   1. Downloads the latest HarvestPlus.app.zip from GitHub Releases.
#   2. Extracts it into ~/Applications (or /Applications with --system).
#   3. Strips the com.apple.quarantine xattr (defensive – see below).
#   4. Launches the app.
#
# Why ~/Applications by default?
# ------------------------------
# macOS treats ~/Applications as a first-class app location – Launchpad,
# Spotlight, auto-start at login, Dock-pinning, and launch services all
# pick it up identically to /Applications. The only practical difference
# is that installs there need *no* admin password, which matters a lot
# for a utility that ships a new release every few weeks.
#
# Why curl instead of a .pkg double-click?
# ----------------------------------------
# Since 1.0.9, HarvestPlus is signed with a Developer ID Application
# certificate and notarized by Apple, with the notarization ticket
# stapled to the .app. That means Gatekeeper accepts it offline – no
# "is damaged", no "unidentified developer", no System Settings trip.
#
# The curl path is still the canonical install for two reasons:
#   - One Terminal command beats a download-then-double-click flow.
#   - The same command is what the in-app updater runs to upgrade in
#     place, so users only ever learn one workflow.
#
# The quarantine-strip below is now defensive: notarized apps don't need
# it, but a leftover xattr from a previous unsigned install is harmless
# to clear.
#

set -euo pipefail

OWNER="mrpolitic"
REPO="HarvestPlus"
APP_NAME="HarvestPlus"

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------

SYSTEM_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --system)     SYSTEM_INSTALL=1 ;;
        --user)       SYSTEM_INSTALL=0 ;;      # explicit opposite, for clarity
        -h|--help)
            sed -n '2,20p' "$0" 2>/dev/null || true
            exit 0
            ;;
        *)
            printf "Unknown argument: %s\n" "$arg" >&2
            exit 2
            ;;
    esac
done

if [ $SYSTEM_INSTALL -eq 1 ]; then
    APPS_DIR="/Applications"
    OTHER_DIR="$HOME/Applications"
else
    APPS_DIR="$HOME/Applications"
    OTHER_DIR="/Applications"
fi
INSTALL_PATH="$APPS_DIR/${APP_NAME}.app"
OTHER_PATH="$OTHER_DIR/${APP_NAME}.app"

# /releases/latest/download/<asset> 302s to the actual asset on the latest
# non-prerelease release – avoids hitting the JSON API's rate limit.
ASSET_URL="https://github.com/${OWNER}/${REPO}/releases/latest/download/${APP_NAME}.app.zip"

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------

blue()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
green() { printf "\033[1;32m✓\033[0m %s\n"  "$*"; }
yell()  { printf "\033[1;33m!\033[0m %s\n"  "$*" >&2; }
red()   { printf "\033[1;31m✗\033[0m %s\n"  "$*" >&2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
    red "HarvestPlus is macOS-only. Detected: $(uname -s)."
    exit 1
fi

# Make sure ~/Applications exists when we're using it (it's not created by default on a fresh Mac).
if [ $SYSTEM_INSTALL -eq 0 ] && [ ! -d "$APPS_DIR" ]; then
    mkdir -p "$APPS_DIR"
fi

# Decide whether we need sudo. For user installs, we never should. For
# --system, we sudo every privileged step if /Applications isn't already
# writable by the current user.
SUDO=""
if [ ! -w "$APPS_DIR" ]; then
    if [ $SYSTEM_INSTALL -eq 1 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
            blue "Installing to ${APPS_DIR} – you'll be prompted once for your admin password."
        else
            red "Can't write to ${APPS_DIR} and sudo isn't available."
            exit 1
        fi
    else
        red "Can't write to ${APPS_DIR}. Check its permissions, or re-run with --system."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d -t harvestplus-install.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

ZIP_PATH="$TMP_DIR/${APP_NAME}.app.zip"

blue "Fetching ${APP_NAME}.app.zip from github.com/${OWNER}/${REPO}…"
if ! curl -fL --progress-bar "$ASSET_URL" -o "$ZIP_PATH"; then
    red "Download failed. The latest release may not have ${APP_NAME}.app.zip attached."
    red "Check https://github.com/${OWNER}/${REPO}/releases/latest in a browser."
    exit 1
fi

# ---------------------------------------------------------------------------
# Quit a running copy, if any
# ---------------------------------------------------------------------------

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    blue "Quitting running ${APP_NAME} so the new version can replace it…"
    # Use killall directly rather than `osascript "tell ... to quit"`.
    # osascript would send an Apple Event to HarvestPlus, which on first
    # use triggers a "Terminal wants to control HarvestPlus" consent
    # dialog – not a password prompt, but still avoidable friction.
    # `killall` on a process the current user owns needs no permission
    # and produces no dialog. HarvestPlus has no unsaved state, so the
    # hard kill is safe.
    killall "$APP_NAME" 2>/dev/null || true
    # Give the process a moment to release the bundle lock.
    for _ in 1 2 3 4 5; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 1
    done
fi

# ---------------------------------------------------------------------------
# Replace the install
# ---------------------------------------------------------------------------

# Stash the previous install so if extraction fails we can roll back.
OLD_STASH=""
if [ -d "$INSTALL_PATH" ]; then
    OLD_STASH="$TMP_DIR/previous-${APP_NAME}.app"
    $SUDO mv "$INSTALL_PATH" "$OLD_STASH"
fi

blue "Extracting into ${APPS_DIR}…"
# ditto preserves HFS metadata, symlinks, and perms inside the .app bundle.
if ! $SUDO /usr/bin/ditto -x -k "$ZIP_PATH" "$APPS_DIR"; then
    red "Extraction failed."
    [ -n "$OLD_STASH" ] && [ -d "$OLD_STASH" ] && $SUDO mv "$OLD_STASH" "$INSTALL_PATH"
    exit 1
fi

if [ ! -d "$INSTALL_PATH" ]; then
    red "Extraction produced no ${APP_NAME}.app at ${INSTALL_PATH}."
    [ -n "$OLD_STASH" ] && [ -d "$OLD_STASH" ] && $SUDO mv "$OLD_STASH" "$INSTALL_PATH"
    exit 1
fi

# ---------------------------------------------------------------------------
# Strip quarantine + launch
# ---------------------------------------------------------------------------

blue "Stripping quarantine attribute…"
$SUDO /usr/bin/xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

blue "Launching ${APP_NAME}…"
/usr/bin/open "$INSTALL_PATH"

green "HarvestPlus is installed at ${INSTALL_PATH}."
green "Look in your menu bar – there's a new icon."

# ---------------------------------------------------------------------------
# Warn about a stale copy in the other location
# ---------------------------------------------------------------------------

if [ -d "$OTHER_PATH" ]; then
    yell ""
    yell "Heads up – an old HarvestPlus.app still lives at:"
    yell "   ${OTHER_PATH}"
    yell "Launchpad/Spotlight will see both copies. To remove the old one:"
    if [ $SYSTEM_INSTALL -eq 1 ]; then
        yell "   rm -rf \"${OTHER_PATH}\""
    else
        yell "   sudo rm -rf \"${OTHER_PATH}\""
    fi
fi
