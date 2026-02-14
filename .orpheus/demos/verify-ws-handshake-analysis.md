# Verification: WebSocket Handshake Buffer Overflow Report is INVALID

## What was verified

The VERDICT.md claims a reported buffer overflow vulnerability in curl's WebSocket
handshake (lib/ws.c line 1287) is invalid. This verification exercises the actual
code paths externally to confirm each claim.

## Key claims verified

### 1. Line 1287 is in client-side key generation, not server response handling

Confirmed by running `curl -v ws://...` and observing the verbose output:
- curl generates a `Sec-WebSocket-Key` header (24 base64 characters)
- This is the code path at line 1287 (`Curl_ws_request()`)
- The server's `Sec-WebSocket-Accept` response is a different code path entirely

### 2. curl does NOT validate Sec-WebSocket-Accept

Confirmed by running a malicious server that sends:
- A completely wrong `Sec-WebSocket-Accept: AAAAAAAAAAAAAAAAAAAAAAAAAAAA`
- A massively oversized `Sec-WebSocket-Accept: AAA...` (1000 bytes)

In both cases, curl accepted the 101 response and proceeded to receive WebSocket
data without complaint. This matches `docs/internals/WEBSOCKET.md` line 101:
"Verify the Sec-WebSocket-Accept response. It requires a sha-1 function." (listed
under Future work).

### 3. No memory errors even with adversarial input

Valgrind memcheck against the oversized Accept server reports:
- 0 errors from 0 contexts
- 0 bytes definitely lost
- No invalid reads or writes

### 4. Buffer bounds are safe

The `keyval[40]` buffer stores base64-encoded 16 random bytes = always 24 chars.
Protected by explicit `if(randlen >= sizeof(keyval))` guard and `curlx_strcopy()`
which checks `slen < dsize` before copying.

## How to reproduce

```bash
cd /path/to/curl
chmod +x .orpheus/demos/demo-ws-handshake-verdict.sh
./.orpheus/demos/demo-ws-handshake-verdict.sh
```

## WebSocket tests

Tests 2700-2705 all pass (6/6) and exercise the WebSocket handshake and frame
processing code paths.
