# Code Review: socks_sspi.c Refactor (PR #4)

## What changed

The monolithic `Curl_SOCKS5_gssapi_negotiate` function was split into:
- `socks5_sspi_setup()` -- acquires credentials and prepares the service name
- `socks5_sspi_loop()` -- the GSSAPI negotiation loop
- `socks5_sspi_encryption()` -- negotiates encryption level

Two helper functions were also added:
- `socks5_free_token()` -- frees a SecBuffer via FreeContextBuffer and returns a CURLcode
- `socks5_free()` -- frees three SecBuffer tokens via Curl_safefree and returns a CURLcode

## Bug confirmed: memory leak in socks5_sspi_loop()

**File:** `lib/socks_sspi.c`, lines 223-233

In `socks5_sspi_loop()`, when `Curl_blockread_all` fails after `sspi_recv_token.pvBuffer`
was allocated at line 223, the buffer is not freed before returning:

```c
sspi_recv_token.pvBuffer = curlx_malloc(us_length);  // line 223

if(!sspi_recv_token.pvBuffer)
  return CURLE_OUT_OF_MEMORY;

result = Curl_blockread_all(cf, data, (char *)sspi_recv_token.pvBuffer,
                            sspi_recv_token.cbBuffer, &actualread);

if(result || (actualread != us_length)) {
    failf(data, "Failed to receive SSPI authentication token.");
    return result ? result : CURLE_COULDNT_CONNECT;  // LEAK: sspi_recv_token.pvBuffer not freed
}
```

In the original code, this error path used `goto error`, which included
`curlx_free(sspi_recv_token.pvBuffer)` at what was line 575.

**Fix:** Add `Curl_safefree(sspi_recv_token.pvBuffer);` before the return at line 232.

## Behavioral change: gss_enc flag source

The original code used `sspi_ret_flags` (output parameter from `InitializeSecurityContext`)
to determine the encryption level in the encryption negotiation phase. The refactored code
uses `QueryContextAttributes(SECPKG_ATTR_FLAGS)` via a new `SecPkgContext_Flags` structure
instead. Per Microsoft documentation, these should return the same flags in practice, but:

1. The new code introduces an extra API call that could theoretically fail where the old
   code would not (the old code had the flags already available).
2. `SecPkgContext_Flags.Flags` and the `sspi_ret_flags` output from `InitializeSecurityContext`
   should contain the same flag bits, but this is an implicit contract, not a documented guarantee.

This is unlikely to cause issues in practice but is a non-trivial behavioral change that should
be noted.

## Error path analysis

### socks5_sspi_setup()
- If `service_name` allocation fails (line 75-76): returns CURLE_OUT_OF_MEMORY. Caller's
  `service_name` is NULL. Caller's `goto error` calls `curlx_free(NULL)` -- safe.
- If `AcquireCredentialsHandle` fails (line 85-88): returns CURLE_COULDNT_CONNECT.
  `*service_namep` was already set. Caller's `goto error` frees it -- correct.

### socks5_sspi_loop()
- All `socks5_free_token(&sspi_send_token, ...)` returns: correctly free the send token.
- Lines 204, 210, 216 (after the `if(status != SEC_I_CONTINUE_NEEDED) break` check):
  by this point, `sspi_send_token.pvBuffer` has been freed (lines 191-193) and
  `sspi_recv_token.pvBuffer` has been freed (line 195). Returns are clean.
- **Line 226**: If `sspi_recv_token.pvBuffer` allocation fails, returns CURLE_OUT_OF_MEMORY.
  `sspi_recv_token.pvBuffer` is NULL. Clean.
- **Lines 231-233**: **MEMORY LEAK** -- `sspi_recv_token.pvBuffer` allocated but not freed.

### socks5_sspi_encryption()
- `etbuf` is only allocated in the non-NEC path (line 340). In the NEC path, `etbuf` stays NULL.
- Line 359: `curlx_free(etbuf)` before return on send failure -- correct.
- Line 374: `curlx_free(etbuf)` after send in non-NEC path -- correct.
- All returns after line 381: `etbuf` has already been freed (non-NEC) or was never
  allocated (NEC). Clean.
- `sspi_w_token` buffers: properly freed via `socks5_free()` on allocation failures
  and after EncryptMessage.
- `sspi_w_token[1].pvBuffer` from DecryptMessage: freed via `FreeContextBuffer` on
  error and success paths. Correct (this was SSPI-allocated, not malloc-allocated).
- `sspi_w_token[0].pvBuffer`: freed via `curlx_free` at line 454. Also freed on
  specific error returns at lines 412, 429, 438, 449. Correct.

### Curl_SOCKS5_gssapi_negotiate() (main function)
- `error:` label properly frees: service_name, sspi_context, cred_handle, names.sUserName.
- The `sspi_recv_token`, `sspi_send_token`, `sspi_w_token`, and `etbuf` buffers are now
  local to their respective sub-functions and cleaned up there (except for the bug above).
