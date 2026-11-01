#!/bin/sh
set -eu
# Google validates the app ID before SwiftUI starts. Fail the build clearly.
if ! printf '%s' "${ADMOB_APP_ID:-}" | /usr/bin/grep -Eq '^ca-app-pub-[0-9]{16}~[0-9]{10}$'; then
  echo "error: Set a valid ADMOB_APP_ID in xcconfig before building."
  exit 1
fi
if [ "${CONFIGURATION}" = Production ] || [ "${CONFIGURATION}" = Release ]; then
  if ! printf '%s' "${ADMOB_BANNER_UNIT_ID:-}" | /usr/bin/grep -Eq '^ca-app-pub-[0-9]{16}/[0-9]{10}$'; then
    echo "error: Set a valid production ADMOB_BANNER_UNIT_ID."
    exit 1
  fi
  if [ "${ADMOB_APP_ID%%~*}" != "${ADMOB_BANNER_UNIT_ID%%/*}" ]; then
    echo "error: AdMob app and banner must belong to the same publisher."
    exit 1
  fi
  case "$ADMOB_APP_ID $ADMOB_BANNER_UNIT_ID" in
    *3940256099942544*) echo "error: Google demo IDs must not ship."; exit 1 ;;
  esac
fi
