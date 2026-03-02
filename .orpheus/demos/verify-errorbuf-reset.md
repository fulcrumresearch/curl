# Verification: errorbuf reset on happy eyeballing success

## What this PR fixes

When curl uses happy eyeballing (trying IPv6 and IPv4 in parallel), a failing
IPv6 attempt can write an error message into the error buffer via `failf()`.
If the IPv4 attempt then succeeds (or fails with a *different* error), the
stale IPv6 error message remains in the buffer because `failf()` does not
overwrite an already-set error buffer.

The fix adds `Curl_reset_fail()` calls at three points:
1. `cf-https-connect.c`: when a baller wins the HTTPS connect race
2. `cf-ip-happy.c:cf_ip_ballers_run()`: when restarting connection attempts
3. `cf-ip-happy.c:cf_ip_happy_connect()`: when a baller wins the IP connect race

## How to verify

### Scenario 1: IPv6 fails, IPv4 hits cert mismatch

Start an HTTPS server with a cert for "localhost", then connect using a
different hostname with both IPv6 and IPv4 resolve entries. Set
`CURL_DBG_SOCK_FAIL_IPV6=1` to force IPv6 socket open to fail.

```bash
CURL_DBG_SOCK_FAIL_IPV6=1 ./src/curl -sS -o /dev/null \
  -w 'errormsg=%{errormsg}\n' \
  --resolve "invalid.example:9443:::1,127.0.0.1" \
  https://invalid.example:9443/
```

**Expected (with fix):** `errormsg=SSL: certificate subject name 'localhost' does not match target hostname 'invalid.example'`

**Broken (without fix):** `errormsg=CURL_DBG_SOCK_FAIL_IPV6: failed to open socket`

### Scenario 2: IPv6 fails, IPv4 succeeds

```bash
CURL_DBG_SOCK_FAIL_IPV6=1 ./src/curl -sS -o /dev/null \
  -w 'exit_code=%{exitcode}\nerrormsg=%{errormsg}\n' \
  --resolve "testhost:8765:::1,127.0.0.1" \
  http://testhost:8765/
```

**Expected:** `exit_code=0` and `errormsg=` (empty)

### Automated test

The PR includes `test_05_05_failed_peer` in `tests/http/test_05_errors.py`.
It requires Apache httpd and the full pytest test harness. Run with:

```bash
cd tests/http
pytest test_05_errors.py::TestErrors::test_05_05_failed_peer -v
```
