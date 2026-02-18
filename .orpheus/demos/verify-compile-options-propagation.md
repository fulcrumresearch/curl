# Verify COMPILE_OPTIONS propagation to clang-tidy test targets

This is the core behavioral change in the PR. Previously, when compile options
moved from CMAKE_C_FLAGS to target COMPILE_OPTIONS, the manual clang-tidy
commands for test targets stopped receiving these flags.

## How to verify

1. Configure CMake with clang compiler and clang-tidy:
   ```
   cmake .. -DCURL_CLANG_TIDY=ON -DCURL_USE_OPENSSL=ON -DCMAKE_C_COMPILER=clang
   ```

2. Build, then run the tidy targets with VERBOSE:
   ```
   cmake --build . --target curl
   VERBOSE=1 cmake --build . --target units-clang-tidy -- VERBOSE=1 2>&1 | grep "clang-tidy.*--"
   ```

3. Look for `-W` flags after the `--` separator in the clang-tidy command.
   With the fix, you should see flags like `-Wall -Wextra -Wpedantic ...` etc.

4. Compare with gcc build (no clang):
   ```
   cmake .. -DCURL_CLANG_TIDY=ON -DCURL_USE_OPENSSL=ON
   ```
   The gcc build should NOT have any `-W` flags in the clang-tidy command,
   because passing gcc warning flags to clang-tidy is unsupported.

## What to look for

- **clang compiler**: clang-tidy command includes `-Werror-implicit-function-declaration -Wextra -Wall ...` after `--`
- **gcc compiler**: clang-tidy command only includes `-I` and `-D` flags after `--`
- **Both**: `--config-file=.../.clang-tidy` is used instead of inline `-checks=...`
- **Both**: `--checks=-clang-diagnostic-unused-function` is appended for test targets
- **WERROR**: `--warnings-as-errors=*` is present when `-DCURL_WERROR=ON`
