#!/bin/bash
# Demo: Verify WebSocket handshake buffer overflow report is INVALID
# This script exercises the WebSocket handshake code path externally and
# confirms the claims made in VERDICT.md.
#
# Prerequisites: curl built from source with debug mode (see .orpheus/SETUP.md)
set -e

CURL_BIN="${CURL_BIN:-./src/curl}"
PASS=0
FAIL=0

echo "=== WebSocket Handshake Verdict Verification ==="
echo

# --- Test 1: Run WebSocket tests 2700-2705 ---
echo "[Test 1] Running WebSocket tests 2700-2705..."
cd tests
RESULT=$(perl runtests.pl 2700 2701 2702 2703 2704 2705 2>&1)
if echo "$RESULT" | grep -q "6 tests out of 6 reported OK: 100%"; then
    echo "  PASS: All 6 WebSocket tests pass"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Some WebSocket tests failed"
    echo "$RESULT"
    FAIL=$((FAIL + 1))
fi
cd ..
echo

# --- Test 2: Normal WebSocket handshake with echo server ---
echo "[Test 2] Normal WebSocket handshake against echo server..."
python3 /tmp/ws_echo_server.py &
SERVER_PID=$!
sleep 1

OUTPUT=$($CURL_BIN -v --no-buffer --max-time 2 ws://127.0.0.1:9876/ 2>&1 || true)
if echo "$OUTPUT" | grep -q "Sec-WebSocket-Key:"; then
    KEY=$(echo "$OUTPUT" | grep "Sec-WebSocket-Key:" | awk '{print $3}')
    KEY_LEN=${#KEY}
    echo "  Sec-WebSocket-Key generated: $KEY (length: $KEY_LEN)"
    if [ "$KEY_LEN" -le 40 ]; then
        echo "  PASS: Key fits in keyval[40] buffer (24 chars < 40)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Key exceeds buffer size"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: No Sec-WebSocket-Key in output"
    FAIL=$((FAIL + 1))
fi

if echo "$OUTPUT" | grep -q "Received 101, Switching to WebSocket"; then
    echo "  PASS: WebSocket handshake succeeded"
    PASS=$((PASS + 1))
else
    echo "  FAIL: WebSocket handshake did not complete"
    FAIL=$((FAIL + 1))
fi

kill $SERVER_PID 2>/dev/null || true
echo

# --- Test 3: Wrong Sec-WebSocket-Accept (curl should NOT reject it) ---
echo "[Test 3] Server sends WRONG Sec-WebSocket-Accept..."
cat > /tmp/ws_bad_accept_server.py << 'PYEOF'
import asyncio

async def handle_client(reader, writer):
    request = b''
    while True:
        line = await reader.readline()
        request += line
        if line == b'\r\n':
            break
    response = (
        'HTTP/1.1 101 Switching Protocols\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Accept: AAAAAAAAAAAAAAAAAAAAAAAAAAAA\r\n'
        '\r\n'
    )
    writer.write(response.encode())
    await writer.drain()
    payload = b"hello from bad server"
    frame = bytes([0x81, len(payload)]) + payload
    writer.write(frame)
    await writer.drain()
    await asyncio.sleep(3)
    writer.close()

async def main():
    server = await asyncio.start_server(handle_client, '127.0.0.1', 9877)
    async with server:
        await server.serve_forever()

asyncio.run(main())
PYEOF

python3 /tmp/ws_bad_accept_server.py &
SERVER_PID=$!
sleep 1

OUTPUT=$($CURL_BIN -v --no-buffer --max-time 2 ws://127.0.0.1:9877/ 2>&1 || true)
if echo "$OUTPUT" | grep -q "Received 101, Switching to WebSocket"; then
    echo "  PASS: curl accepted WRONG Sec-WebSocket-Accept (no validation, as documented)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: curl rejected wrong Accept (it should have accepted it)"
    FAIL=$((FAIL + 1))
fi

if echo "$OUTPUT" | grep -q "hello from bad server"; then
    echo "  PASS: Data received from server with wrong Accept"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No data received"
    FAIL=$((FAIL + 1))
fi

kill $SERVER_PID 2>/dev/null || true
echo

# --- Test 4: Oversized Sec-WebSocket-Accept (1000 bytes) ---
echo "[Test 4] Server sends 1000-byte Sec-WebSocket-Accept..."
cat > /tmp/ws_oversized_accept_server.py << 'PYEOF'
import asyncio

async def handle_client(reader, writer):
    request = b''
    while True:
        line = await reader.readline()
        request += line
        if line == b'\r\n':
            break
    oversized_accept = 'A' * 1000
    response = (
        'HTTP/1.1 101 Switching Protocols\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        f'Sec-WebSocket-Accept: {oversized_accept}\r\n'
        '\r\n'
    )
    writer.write(response.encode())
    await writer.drain()
    payload = b"hello from oversized server"
    frame = bytes([0x81, len(payload)]) + payload
    writer.write(frame)
    await writer.drain()
    await asyncio.sleep(3)
    writer.close()

async def main():
    server = await asyncio.start_server(handle_client, '127.0.0.1', 9878)
    async with server:
        await server.serve_forever()

asyncio.run(main())
PYEOF

python3 /tmp/ws_oversized_accept_server.py &
SERVER_PID=$!
sleep 1

OUTPUT=$($CURL_BIN -v --no-buffer --max-time 2 ws://127.0.0.1:9878/ 2>&1 || true)
if echo "$OUTPUT" | grep -q "Received 101, Switching to WebSocket"; then
    echo "  PASS: curl accepted 1000-byte Sec-WebSocket-Accept without crash"
    PASS=$((PASS + 1))
else
    echo "  FAIL: curl crashed or rejected oversized Accept"
    FAIL=$((FAIL + 1))
fi

kill $SERVER_PID 2>/dev/null || true
echo

# --- Test 5: Valgrind check against oversized Accept ---
echo "[Test 5] Valgrind check against oversized Sec-WebSocket-Accept..."
python3 /tmp/ws_oversized_accept_server.py &
SERVER_PID=$!
sleep 1

VALGRIND_OUTPUT=$(valgrind --tool=memcheck --leak-check=full --error-exitcode=42 \
    $CURL_BIN --no-buffer --max-time 2 ws://127.0.0.1:9878/ 2>&1 || true)
if echo "$VALGRIND_OUTPUT" | grep -q "ERROR SUMMARY: 0 errors"; then
    echo "  PASS: Valgrind reports 0 memory errors"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Valgrind found memory errors"
    echo "$VALGRIND_OUTPUT" | grep "ERROR SUMMARY"
    FAIL=$((FAIL + 1))
fi

kill $SERVER_PID 2>/dev/null || true
echo

# --- Summary ---
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "VERDICT: Some checks failed"
    exit 1
else
    echo "VERDICT: All checks pass - vulnerability report is INVALID as documented"
    exit 0
fi
