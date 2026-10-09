#!/usr/bin/env bash
# Compatibility entry point for the improved Persian fonts installer.
#
# Keep the historical GUI command name working while sharing the maintained
# implementation and all of its safety, caching, offline, and verification
# options with farsifonts.sh.
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$SCRIPT_DIR/farsifonts.sh" "$@"
