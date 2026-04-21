#!/bin/bash
#
# postinstall — runs as root after pkgbuild drops HarvestPlus.app into
# /Applications. Strips the quarantine xattr that would otherwise force the
# "app downloaded from the internet — are you sure?" Gatekeeper prompt on
# first launch.
#
# This keeps the coworker experience one-click: double-click the .pkg,
# authenticate, done.
#

set -e

APP_PATH="/Applications/HarvestPlus.app"

if [ -d "$APP_PATH" ]; then
    # -c  clear all extended attributes (com.apple.quarantine, etc.)
    # -r  recurse into the bundle (Frameworks, Helpers, …)
    /usr/bin/xattr -cr "$APP_PATH"
fi

exit 0
