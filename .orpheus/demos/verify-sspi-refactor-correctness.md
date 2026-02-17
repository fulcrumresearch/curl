# Code Review: socks_sspi.c Refactor (PR #4)

## What changed

The monolithic `Curl_SOCKS5_gssapi_negotiate` function was split into:
- `socks5_sspi_setup()` — acquires credentials and prepares the service name
- `socks5_sspi_loop()` — the GSSAPI negotiation loop
- `socks5_sspi_encryption()` — negotiates encryption level

Two helper functions were also added:
- `socks5_free_token()` — frees a SecBuffer and returns a CURLcode
- `socks5_free()` — frees three SecBuffer tokens and returns a CURLcode

## Bug found: memory leak in socks5_sspi_loop()

**File:** `lib/socks_sspi.c`, lines 228-234

In `socks5_sspi_loop()`, when `Curl_blockread_all` fails after `sspi_recv_token.pvBuffer`
was allocated at line 223, the buffer is not freed before returning:

```c
sspi_recv_token.pvBuffer = curlx_malloc(us_length);  // line 223
// ...
result = Curl_blockread_all(cf, data, (char *)sspi_recv_token.pvBuffer,
                            sspi_recv_token.cbBuffer, &actualread);
if(result || (actualread != us_length)) {
    failf(data, "Failed to receive SSPI authentication token.");
    return result ? result : CURLE_COULDNT_CONNECT;  // LEAK: sspi_recv_token.pvBuffer
}
```

In the original code, this error path used `goto error`, which included
`curlx_free(sspi_recv_token.pvBuffer)`.

**Fix:** Add `Curl_safefree(sspi_recv_token.pvBuffer);` before the return.

## Behavioral change: gss_enc flag source

The original code used `sspi_ret_flags` (output parameter from `InitializeSecurityContext`)
to determine the encryption level. The refactored code uses
`QueryContextAttributes(SECPKG_ATTR_FLAGS)` instead. These should return the same flags
in practice (per Microsoft docs), but the new code introduces an extra API call that could
theoretically fail where the old code would not.

## All other error paths verified clean

- `socks5_sspi_setup()`: service_name is freed by the caller's `error:` label
- `socks5_sspi_encryption()`: all sspi_w_token and etbuf allocations properly freed on error
- `socks5_sspi_loop()` other paths: sspi_send_token freed via socks5_free_token, sspi_recv_token freed via Curl_safefree before returns
