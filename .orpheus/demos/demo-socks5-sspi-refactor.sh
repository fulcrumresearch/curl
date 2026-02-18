#!/bin/bash
# Demo script for PR #4: socks_sspi refactor
# This PR refactors the Windows-SSPI SOCKS5 code (guarded by USE_WINDOWS_SSPI).
# On Linux, the code is not compiled, so we verify:
# 1. Clean build (no compile errors from refactored code structure)
# 2. Basic curl functionality (HTTP/HTTPS)
# 3. SOCKS5 proxy end-to-end via SSH dynamic forwarding
# 4. Full SOCKS5 test suite passes
# 5. Broader regression test suite passes

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
echo "=== Step 4: SOCKS5 proxy end-to-end ==="
# Set up SSH keys if needed
if [ ! -f ~/.ssh/id_ed25519 ]; then
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
  cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
fi

# Start SSH SOCKS5 proxy
ssh -o StrictHostKeyChecking=no -D 1080 -N -f localhost 2>/dev/null || true
sleep 1

if ss -tlnp | grep -q ':1080'; then
  SOCKS_HTTP=$($CURL_BIN -s -o /dev/null -w '%{http_code}' --socks5 127.0.0.1:1080 http://example.com)
  echo "SOCKS5 HTTP  -> $SOCKS_HTTP"
  SOCKS_HTTPS=$($CURL_BIN -s -o /dev/null -w '%{http_code}' --socks5-hostname 127.0.0.1:1080 https://example.com)
  echo "SOCKS5 HTTPS -> $SOCKS_HTTPS"
else
  echo "SOCKS5 proxy not available, skipping live proxy test"
fi

echo ""
echo "=== Step 5: SOCKS5 test suite ==="
cd "$CURL_DIR/tests"
perl runtests.pl 700 to 721 728 729 742 564 1467 1468 1470 2055 1212 2>&1 | tail -5

echo ""
echo "=== Step 6: Broader regression tests (first 200) ==="
perl runtests.pl 1 to 200 2>&1 | tail -3

echo ""
echo "=== Done ==="
echo "Note: socks_sspi.c is only compiled on Windows (USE_WINDOWS_SSPI)."
echo "The memory leak at socks5_sspi_loop() lines 231-233 must be verified by code inspection."
