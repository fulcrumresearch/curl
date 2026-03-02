#!/bin/bash
# Demo: mk-ca-bundle.pl -r flag for deterministic CA bundle generation
# Tests the new -r <commit ref> option added by PR #5
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/mk-ca-bundle.pl"
WORKDIR=$(mktemp -d)
KNOWN_REF="397c3187280dfa84ce9da56a9944d945bf73977d"
KNOWN_DATE="2025-10-29 14:28:33"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "=== Test 1: Happy path with -r <commit hash> ==="
cd "$WORKDIR" && rm -f certdata.txt ca-bundle.crt
perl "$SCRIPT" -r "$KNOWN_REF" 2>&1
HEADER=$(head -4 ca-bundle.crt | tail -1)
echo "Header: $HEADER"
MTIME=$(stat -c %Y ca-bundle.crt)
echo "File mtime (epoch): $MTIME"
echo

echo "=== Test 2: Deterministic output (second run) ==="
SHA1=$(sha256sum ca-bundle.crt | cut -d' ' -f1)
rm -f certdata.txt ca-bundle.crt
perl "$SCRIPT" -r "$KNOWN_REF" 2>&1
SHA2=$(sha256sum ca-bundle.crt | cut -d' ' -f1)
if [ "$SHA1" = "$SHA2" ]; then
    echo "PASS: Two runs produce identical output ($SHA1)"
else
    echo "FAIL: Output differs between runs ($SHA1 vs $SHA2)"
fi
echo

echo "=== Test 3: Default mode (no -r, regression check) ==="
rm -f certdata.txt ca-bundle.crt
perl "$SCRIPT" 2>&1
HEADER_DEFAULT=$(head -4 ca-bundle.crt | tail -1)
echo "Header: $HEADER_DEFAULT"
echo "(Should show 'as of' with current date, not a fixed date)"
echo

echo "=== Test 4: Invalid commit hash ==="
rm -f certdata.txt ca-bundle.crt
if perl "$SCRIPT" -r deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2>&1; then
    echo "UNEXPECTED: Script succeeded with invalid ref"
else
    echo "PASS: Script failed with invalid ref (exit $?)"
fi
echo

echo "=== Test 5: Empty -r argument ==="
rm -f certdata.txt ca-bundle.crt
if perl "$SCRIPT" -r '' 2>&1; then
    echo "UNEXPECTED: Script succeeded with empty ref"
else
    echo "PASS: Script failed with empty ref (exit $?)"
fi
echo

echo "=== Test 6: -r with tag name ==="
rm -f certdata.txt ca-bundle.crt
perl "$SCRIPT" -r FIREFOX_NIGHTLY_131_END 2>&1
HEADER_TAG=$(head -4 ca-bundle.crt | tail -1)
echo "Header: $HEADER_TAG"
echo

echo "=== Test 7: -r overrides -d ==="
rm -f certdata.txt ca-bundle.crt
perl "$SCRIPT" -r "$KNOWN_REF" -d nss 2>&1
URL_LINE=$(perl "$SCRIPT" -r "$KNOWN_REF" -d nss 2>&1 | grep "Using URL")
echo "$URL_LINE"
echo "(Should use the ref URL, not the nss URL)"

echo
echo "=== All tests complete ==="
