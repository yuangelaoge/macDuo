#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_SIGNING="${MAC_TILT_SIGNING_DIR:-$TASK_ROOT/.local-signing}"
TASK_SIGNING="$(cd "$TASK_SIGNING" && pwd)"
TASK_KEYCHAIN="$TASK_SIGNING/signing.keychain-db"
TASK_APP="${1:?Pass the app bundle to sign}"
test -f "$TASK_KEYCHAIN" || { echo 'Missing local signing identity; refusing an ad-hoc replacement.' >&2; exit 1; }
TASK_PASSWORD=$(<"$TASK_SIGNING/keychain-password")
TASK_FINGERPRINT=$(openssl x509 -in "$TASK_SIGNING/certificate.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
TASK_KEYCHAINS=()
while IFS= read -r TASK_ITEM; do
    TASK_KEYCHAINS+=("$TASK_ITEM")
done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')
restore_signing_state() {
    security list-keychains -d user -s "${TASK_KEYCHAINS[@]}"
    security lock-keychain "$TASK_KEYCHAIN"
}
trap restore_signing_state EXIT
security unlock-keychain -p "$TASK_PASSWORD" "$TASK_KEYCHAIN"
# codesign also needs the certificate in its search list when resolving the key.
# Preserve the original list and restore it immediately after signing.
security list-keychains -d user -s "${TASK_KEYCHAINS[@]}" "$TASK_KEYCHAIN"
TASK_REQUIREMENT="identifier \"local.david.mactilt-duo\" and certificate leaf = H\"$TASK_FINGERPRINT\""
xattr -dr com.apple.FinderInfo "$TASK_APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$TASK_APP" 2>/dev/null || true
codesign --force --keychain "$TASK_KEYCHAIN" --sign "$TASK_FINGERPRINT" \
    -r "=designated => $TASK_REQUIREMENT" "$TASK_APP"
codesign --verify --strict -R "=$TASK_REQUIREMENT" "$TASK_APP"
