#!/bin/bash
# Demo: cmake clang-tidy integration with COMPILE_OPTIONS propagation
# This script verifies that clang-tidy test targets receive compile options
# from their build targets, which is the core fix in this PR.
#
# Prerequisites: clang-tidy >= 14, clang (optional), cmake, gcc, libssl-dev, etc.
set -euo pipefail

SRCDIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_GCC="$SRCDIR/build-demo-gcc"
BUILD_CLANG="$SRCDIR/build-demo-clang"

echo "=== Test 1: CMake + gcc + clang-tidy ==="
echo "Expect: clang-tidy runs on tests WITHOUT gcc warning flags"
rm -rf "$BUILD_GCC"
mkdir -p "$BUILD_GCC"
cd "$BUILD_GCC"
cmake "$SRCDIR" -DCURL_CLANG_TIDY=ON -DCURL_USE_OPENSSL=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build . --target curl
cmake --build . --target tests-clang-tidy
echo "PASS: CMake + gcc + clang-tidy completed"

# Verify no -W flags in test tidy commands (gcc flags should NOT be passed)
VERBOSE=1 cmake --build . --target units-clang-tidy -- VERBOSE=1 2>&1 | \
  grep "clang-tidy.*--" | grep -v "cmake_depends" | \
  { if grep -q "\-Wall"; then echo "FAIL: gcc warning flags leaked to clang-tidy"; exit 1; else echo "PASS: no gcc warning flags in clang-tidy command"; fi }

echo ""
echo "=== Test 2: CMake + clang + clang-tidy ==="
echo "Expect: clang-tidy runs on tests WITH clang warning flags"
rm -rf "$BUILD_CLANG"
mkdir -p "$BUILD_CLANG"
cd "$BUILD_CLANG"
cmake "$SRCDIR" -DCURL_CLANG_TIDY=ON -DCURL_USE_OPENSSL=ON -DCMAKE_C_COMPILER=clang -DCMAKE_BUILD_TYPE=Debug
cmake --build . --target curl
cmake --build . --target tests-clang-tidy
echo "PASS: CMake + clang + clang-tidy completed"

# Verify -W flags are present in test tidy commands (clang flags SHOULD be passed)
VERBOSE=1 cmake --build . --target units-clang-tidy -- VERBOSE=1 2>&1 | \
  grep "clang-tidy.*--" | grep -v "cmake_depends" | \
  { if grep -q "\-Wall"; then echo "PASS: clang warning flags passed to clang-tidy"; else echo "FAIL: clang warning flags missing from clang-tidy command"; exit 1; fi }

echo ""
echo "=== Test 3: .clang-tidy config file validation ==="
clang-tidy --config-file="$SRCDIR/.clang-tidy" --list-checks 2>&1 | \
  { if grep -q "insecureAPI.bzero"; then echo "FAIL: bzero check should be disabled"; exit 1; else echo "PASS: bzero check correctly disabled"; fi }

echo ""
echo "All tests passed."

# Cleanup
rm -rf "$BUILD_GCC" "$BUILD_CLANG"
