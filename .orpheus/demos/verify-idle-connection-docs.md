# Verification: Idle Connection Behavior Documentation (PR #6)

This directory contains two C programs that demonstrate the behaviors documented
in the PR's changes to `CURLMOPT_SOCKETFUNCTION.md` and
`CURLOPT_CLOSESOCKETFUNCTION.md`.

## What the PR changes

1. **CURLMOPT_SOCKETFUNCTION** `CURL_POLL_REMOVE` section: Documents that after
   REMOVE, the app must stop monitoring the socket, libcurl does not track idle
   connections, and the `curl_multi_assign` pointer is forgotten.

2. **CURLOPT_CLOSESOCKETFUNCTION** new "NOTES ON IDLE CONNECTIONS" section:
   Documents that the close callback is copied from the *first* easy handle that
   creates a connection; subsequent handles reusing the connection do not change it.

3. Cross-references added between the two man pages.

## Prerequisites

```bash
# Start a keep-alive HTTP server
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type','text/plain')
        self.send_header('Connection','keep-alive')
        body = b'Hello\n'
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
HTTPServer(('127.0.0.1', 8888), H).serve_forever()
" &
```

## Demo 1: CURL_POLL_REMOVE and socketp forgetting

```bash
gcc -o demo_poll_remove demo_poll_remove.c \
  -I../../include -L../../lib/.libs -lcurl \
  -Wl,-rpath,../../lib/.libs
./demo_poll_remove
```

**What to look for:**
- `CURL_POLL_OUT` fires with `socketp=(nil)` (socket is new)
- `curl_multi_assign` sets `socketp` to a marker value
- `CURL_POLL_REMOVE` fires with the marker pointer, then it is forgotten
- When the socket is re-added, `socketp` is back to `(nil)`

## Demo 2: Close socket callback inheritance

```bash
gcc -o demo_closesocket demo_closesocket.c \
  -I../../include -L../../lib/.libs -lcurl \
  -Wl,-rpath,../../lib/.libs
./demo_closesocket
```

**What to look for:**
- Transfer 1 uses `close_cb_FIRST`
- Transfer 2 sets `close_cb_SECOND` but reuses the existing connection
- At cleanup, `close_cb_FIRST` fires (not `close_cb_SECOND`)
- This confirms the callback is bound to the connection, not the handle

## Man page validation

```bash
cd docs/libcurl/opts
make CURLMOPT_SOCKETFUNCTION.3 CURLOPT_CLOSESOCKETFUNCTION.3
```

Verify that both `.3` files render without errors and contain the new sections.

## Test suite

```bash
cd tests
perl runtests.pl 585 586 1139 1140 1173 1275
```

- Tests 585/586: socket open/close callback functionality
- Tests 1139/1140/1173/1275: documentation format validation
