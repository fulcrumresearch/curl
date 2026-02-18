#!/bin/bash
# Demo: errorbuf reset on happy eyeballing success
# PR: https://github.com/fulcrumresearch/curl/pull/7
#
# This script verifies the fix for issue #20608: when happy eyeballing
# tries IPv6 (which fails) and then IPv4 (which succeeds or fails with
# a different error), the error buffer should reflect the actual outcome,
# not the stale IPv6 failure message.
#
# Requirements:
#   - curl built with --enable-debug (DEBUGBUILD defined)
#   - openssl, python3 for the test HTTPS server
#
# The CURL_DBG_SOCK_FAIL_IPV6 env var (new in this PR) forces the
# debug build to fail socket creation for AF_INET6, simulating an
# IPv6 failure without needing a real IPv6 issue.

set -e

CURL_BIN="${CURL_BIN:-./src/curl}"
CERT_DIR=$(mktemp -d)
SERVER_PORT=9443

echo "=== Setup: generate self-signed cert for 'localhost' ==="
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_DIR/cert.pem" -days 1 -nodes \
    -subj "/CN=localhost" 2>/dev/null
echo "Cert generated in $CERT_DIR"

echo ""
echo "=== Setup: start HTTPS server on port $SERVER_PORT ==="
python3 -c "
import ssl, http.server
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('$CERT_DIR/cert.pem', '$CERT_DIR/key.pem')
httpd = http.server.HTTPServer(('0.0.0.0', $SERVER_PORT), http.server.SimpleHTTPRequestHandler)
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
print('HTTPS server running', flush=True)
httpd.serve_forever()
" &
SERVER_PID=$!
sleep 1

cleanup() {
    kill $SERVER_PID 2>/dev/null
    rm -rf "$CERT_DIR"
}
trap cleanup EXIT

echo ""
echo "=== Test 1: IPv6 socket fails + cert mismatch on IPv4 ==="
echo "Expected: errormsg shows SSL cert error, NOT the IPv6 socket failure"
echo ""
RESULT=$(CURL_DBG_SOCK_FAIL_IPV6=1 $CURL_BIN -sS -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\n' \
  --resolve "invalid.example:${SERVER_PORT}:::1,127.0.0.1" \
  "https://invalid.example:${SERVER_PORT}/" 2>&1 || true)
echo "$RESULT"
echo ""

# Verify the error message is about SSL, not about IPv6 socket failure
if echo "$RESULT" | grep -q "errormsg=SSL"; then
    echo "PASS: errormsg correctly shows SSL certificate error"
elif echo "$RESULT" | grep -q "CURL_DBG_SOCK_FAIL_IPV6"; then
    echo "FAIL: errormsg still shows stale IPv6 socket failure (bug not fixed)"
    exit 1
else
    echo "UNEXPECTED: errormsg content not recognized"
    exit 1
fi

echo ""
echo "=== Test 2: IPv6 socket fails + IPv4 succeeds ==="
echo "Expected: errormsg is empty (connection succeeded)"
echo ""

# Start a plain HTTP server for this test
python3 -c "
import http.server
httpd = http.server.HTTPServer(('127.0.0.1', 8765), http.server.SimpleHTTPRequestHandler)
httpd.serve_forever()
" &
HTTP_PID=$!
sleep 1

RESULT=$(CURL_DBG_SOCK_FAIL_IPV6=1 $CURL_BIN -sS -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\nhttp_code=%{http_code}\n' \
  --resolve "testhost:8765:::1,127.0.0.1" \
  "http://testhost:8765/" 2>&1 || true)
echo "$RESULT"
echo ""

kill $HTTP_PID 2>/dev/null

if echo "$RESULT" | grep -q "exit_code=0" && echo "$RESULT" | grep -q "errormsg=$"; then
    echo "PASS: successful connection with empty errormsg"
else
    echo "FAIL: unexpected result"
    exit 1
fi

echo ""
echo "=== All tests passed ==="
