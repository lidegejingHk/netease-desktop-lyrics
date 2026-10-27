#!/bin/zsh
set -euo pipefail

# Creates a stable self-signed code signing identity for local releases.
# A stable identity keeps macOS TCC grants (Accessibility) valid across
# rebuilds; ad-hoc signatures change identity on every build.

identity="${SIGN_IDENTITY:-NeteaseDesktopLyrics Signing}"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -Fq "\"$identity\""; then
  print "Signing identity already present: $identity"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
password="$(openssl rand -hex 16)"

cat > "$tmp/req.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext

[dn]
CN = $identity

[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/req.cnf" >/dev/null 2>&1
if ! openssl pkcs12 -export -legacy -name "$identity" \
  -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -out "$tmp/signer.p12" -passout "pass:$password" >/dev/null 2>&1; then
  # LibreSSL lacks -legacy but already writes a security-compatible archive.
  openssl pkcs12 -export -name "$identity" \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/signer.p12" -passout "pass:$password" >/dev/null 2>&1
fi

security import "$tmp/signer.p12" -k "$keychain" -P "$password" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

print "Created signing identity: $identity"
security find-identity -p codesigning | grep -F "\"$identity\"" || true
print "\nRun this on the release machine only. Other machines must import the same"
print ".p12; generating a second certificate with the same name changes the app identity."
print "\nThe identity is self-signed and intentionally untrusted by Gatekeeper;"
print "that is expected. macOS will still block the first launch of a downloaded build."
print "\nBack up the private key now: Keychain Access -> login -> My Certificates ->"
print "export \"$identity\" as .p12 and store it somewhere safe."
print "Losing it changes the app identity and resets Accessibility grants for every user."
