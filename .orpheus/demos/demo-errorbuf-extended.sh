#!/bin/bash
# Extended demo: errorbuf reset on happy eyeballing success
# PR: https://github.com/fulcrumresearch/curl/pull/7
#
# This script extends the original demo with additional edge cases:
# - IPv6 fails + IPv4 connection refused (both fail)
# - HTTPS with valid cert after IPv6 failure
# - Normal operation without debug flag (regression check)
#
# Requirements:
#   - curl built with --enable-debug (DEBUGBUILD defined)
#   - openssl, python3 for test servers

set -e

CURL_BIN="${CURL_BIN:-./src/curl}"
CERT_DIR=$(mktemp -d)
HTTPS_PORT=9444
HTTP_PORT=8766

cleanup() {
    kill $HTTPS_PID $HTTP_PID 2>/dev/null || true
    rm -rf "$CERT_DIR"
}
trap cleanup EXIT

echo "=== Setup: generate self-signed cert for 'localhost' ==="
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_DIR/cert.pem" -days 1 -nodes \
    -subj "/CN=localhost" 2>/dev/null

python3 -c "
import ssl, http.server
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('$CERT_DIR/cert.pem', '$CERT_DIR/key.pem')
httpd = http.server.HTTPServer(('0.0.0.0', $HTTPS_PORT), http.server.SimpleHTTPRequestHandler)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
" &
HTTPS_PID=$!

python3 -c "
import http.server
httpd = http.server.HTTPServer(('127.0.0.1', $HTTP_PORT), http.server.SimpleHTTPRequestHandler)
httpd.serve_forever()
" &
HTTP_PID=$!
sleep 1

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    echo -n "  $name: "
    if echo "$actual" | grep -q "$expected"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL (expected pattern: $expected, got: $actual)"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== Test 1: IPv6 fails + cert mismatch on IPv4 ==="
RESULT=$(CURL_DBG_SOCK_FAIL_IPV6=1 $CURL_BIN -sS -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\n' \
  --resolve "invalid.example:${HTTPS_PORT}:::1,127.0.0.1" \
  "https://invalid.example:${HTTPS_PORT}/" 2>&1 || true)
echo "$RESULT"
run_test "errormsg shows SSL error" "errormsg=SSL" "$RESULT"

echo ""
echo "=== Test 2: IPv6 fails + IPv4 HTTP succeeds ==="
RESULT=$(CURL_DBG_SOCK_FAIL_IPV6=1 $CURL_BIN -sS -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\nhttp_code=%{http_code}\n' \
  --resolve "testhost:${HTTP_PORT}:::1,127.0.0.1" \
  "http://testhost:${HTTP_PORT}/" 2>&1 || true)
echo "$RESULT"
run_test "exit_code=0" "exit_code=0" "$RESULT"
run_test "empty errormsg" "errormsg=$" "$RESULT"

echo ""
echo "=== Test 3: No debug flag - cert mismatch (regression check) ==="
RESULT=$($CURL_BIN -sS -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\n' \
  --resolve "invalid.example:${HTTPS_PORT}:127.0.0.1" \
  "https://invalid.example:${HTTPS_PORT}/" 2>&1 || true)
echo "$RESULT"
run_test "errormsg shows SSL error" "errormsg=SSL" "$RESULT"

echo ""
echo "=== Test 4: IPv6 fails + HTTPS succeeds (valid cert with -k) ==="
RESULT=$(CURL_DBG_SOCK_FAIL_IPV6=1 $CURL_BIN -sS -k -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\nhttp_code=%{http_code}\n' \
  --resolve "localhost:${HTTPS_PORT}:::1,127.0.0.1" \
  "https://localhost:${HTTPS_PORT}/" 2>&1 || true)
echo "$RESULT"
run_test "exit_code=0" "exit_code=0" "$RESULT"
run_test "empty errormsg" "errormsg=$" "$RESULT"

echo ""
echo "=== Test 5: IPv6 fails + IPv4 connection refused (no server) ==="
RESULT=$(CURL_DBG_SOCK_FAIL_IPV6=1 $CURL_BIN -sS -o /dev/null \
  --connect-timeout 5 \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\n' \
  --resolve "noserver.example:19999:::1,127.0.0.1" \
  "http://noserver.example:19999/" 2>&1 || true)
echo "$RESULT"
run_test "errormsg about connection" "errormsg=Failed to connect" "$RESULT"

echo ""
echo "=== Test 6: Normal HTTP success (regression check) ==="
RESULT=$($CURL_BIN -sS -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\nhttp_code=%{http_code}\n' \
  --resolve "testhost:${HTTP_PORT}:127.0.0.1" \
  "http://testhost:${HTTP_PORT}/" 2>&1 || true)
echo "$RESULT"
run_test "exit_code=0" "exit_code=0" "$RESULT"
run_test "empty errormsg" "errormsg=$" "$RESULT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
