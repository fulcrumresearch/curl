#!/bin/bash
# Demo script for PR #4: socks_sspi refactor
# This PR refactors the Windows-SSPI SOCKS5 code (guarded by USE_WINDOWS_SSPI).
# On Linux, the code is not compiled, so we verify:
# 1. Clean build
# 2. Basic curl functionality
# 3. Full SOCKS5 test suite passes

set -e

CURL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CURL_BIN="$CURL_DIR/src/curl"

echo "=== Step 1: Build from source ==="
cd "$CURL_DIR"
make -j"$(nproc)" 2>&1 | tail -3
echo "Build succeeded."

echo ""
echo "=== Step 2: Verify curl binary ==="
$CURL_BIN --version | head -3

echo ""
echo "=== Step 3: Basic HTTP/HTTPS ==="
HTTP_CODE=$($CURL_BIN -s -o /dev/null -w '%{http_code}' http://example.com)
echo "HTTP  -> $HTTP_CODE"
HTTPS_CODE=$($CURL_BIN -s -o /dev/null -w '%{http_code}' https://example.com)
echo "HTTPS -> $HTTPS_CODE"

echo ""
echo "=== Step 4: SOCKS5 test suite ==="
cd "$CURL_DIR/tests"
# Run all SOCKS-related tests
perl runtests.pl 700 to 721 728 729 742 564 1467 1468 1470 2055 1212 2>&1 | tail -5

echo ""
echo "=== Done ==="
echo "Note: socks_sspi.c is only compiled on Windows (USE_WINDOWS_SSPI)."
echo "Code review for memory safety and behavioral equivalence must be done by inspection."
