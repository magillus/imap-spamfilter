#!/usr/bin/env bash
# run-gui.sh - Launch the Flutter IMAP spam triage email client
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
RELEASE_BIN="$HERE/email_client/build/linux/x64/release/bundle/email_client"
DEBUG_BIN="$HERE/email_client/build/linux/x64/debug/bundle/email_client"

if [[ -f "$RELEASE_BIN" ]]; then
  exec "$RELEASE_BIN" "$@"
elif [[ -f "$DEBUG_BIN" ]]; then
  exec "$DEBUG_BIN" "$@"
else
  echo "Building and running via Flutter..."
  cd "$HERE/email_client"
  exec flutter run -d linux "$@"
fi

