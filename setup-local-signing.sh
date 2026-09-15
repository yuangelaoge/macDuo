#!/bin/bash
set -euo pipefail
umask 077
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_SIGNING="${MAC_TILT_SIGNING_DIR:-$TASK_ROOT/.local-signing}"
mkdir -p "$TASK_SIGNING"
TASK_SIGNING="$(cd "$TASK_SIGNING" && pwd)"
if test -e "$TASK_SIGNING/signing.keychain-db"; then
    echo 'Signing keychain already exists; preserving identity.'
    exit 0
fi
openssl rand -hex -out "$TASK_SIGNING/keychain-password" 32
TASK_PASSWORD=$(<"$TASK_SIGNING/keychain-password")
export TASK_P12_PASSWORD="$TASK_PASSWORD"
openssl req -new -x509 -newkey rsa:2048 -days 3650 \
    -subj '/CN=macTilt Duo Local Development/' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -keyout "$TASK_SIGNING/private-key.pem" \
    -out "$TASK_SIGNING/certificate.pem" \
    -passout "file:$TASK_SIGNING/keychain-password"
openssl pkcs12 -export -legacy \
    -inkey "$TASK_SIGNING/private-key.pem" -in "$TASK_SIGNING/certificate.pem" \
    -passin "file:$TASK_SIGNING/keychain-password" -passout env:TASK_P12_PASSWORD \
    -out "$TASK_SIGNING/identity.p12"
security create-keychain -p "$TASK_PASSWORD" "$TASK_SIGNING/signing.keychain-db"
trap 'security lock-keychain "$TASK_SIGNING/signing.keychain-db"' EXIT
security unlock-keychain -p "$TASK_PASSWORD" "$TASK_SIGNING/signing.keychain-db"
security import "$TASK_SIGNING/identity.p12" -k "$TASK_SIGNING/signing.keychain-db" \
    -P "$TASK_PASSWORD" -T /usr/bin/codesign -x
security set-key-partition-list -S apple-tool:,apple: -s -k "$TASK_PASSWORD" \
    "$TASK_SIGNING/signing.keychain-db" >/dev/null
echo 'Created local signing identity. Keep this ignored directory private and reuse it for updates.'
