#!/bin/bash
# One-time setup: create and trust a persistent self-signed code-signing
# certificate for local Whisper builds. Without this, make-app.sh falls back
# to ad-hoc signing, which gives every rebuild a new identity — macOS then
# treats each rebuild as an unrecognized app and re-prompts for Keychain
# access to the stored provider API keys on every single launch.
set -euo pipefail

CERT_NAME="Whisper Dev Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "'$CERT_NAME' already installed and trusted."
    exit 0
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/cert.conf" <<EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = $CERT_NAME

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 \
    -keyout "$WORKDIR/key.pem" -out "$WORKDIR/cert.pem" \
    -days 3650 -nodes -config "$WORKDIR/cert.conf"
openssl x509 -in "$WORKDIR/cert.pem" -outform DER -out "$WORKDIR/cert.der"

security import "$WORKDIR/key.pem" -k "$KEYCHAIN" -A
security import "$WORKDIR/cert.der" -k "$KEYCHAIN" -A

# This is the step that prompts for your macOS password: trusting a cert
# for code signing is a system security-policy change.
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

echo "Installed and trusted '$CERT_NAME'."
security find-identity -v -p codesigning | grep "$CERT_NAME"
