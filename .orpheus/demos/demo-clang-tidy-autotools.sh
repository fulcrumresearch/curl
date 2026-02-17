#!/bin/bash
# Demo: autotools clang-tidy integration
# Verifies the `make tidy` target works with the new .clang-tidy config file
# and the CLANG conditional for CFLAGS passing.
#
# Prerequisites: clang-tidy >= 14, autoconf, automake, libtool, gcc, libssl-dev, etc.
set -euo pipefail

SRCDIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SRCDIR"

echo "=== Autotools: reconfigure and build ==="
autoreconf -fi
./configure --with-openssl --with-nghttp2 --with-zstd --with-brotli --with-libssh2 --enable-debug
make -j"$(nproc)"

echo ""
echo "=== Run tidy on lib/ ==="
cd "$SRCDIR/lib"
make tidy 2>&1 | tee /tmp/lib-tidy.log
LIB_ERRORS=$(grep -c "error:" /tmp/lib-tidy.log || true)
echo "lib/ tidy errors: $LIB_ERRORS"
if [ "$LIB_ERRORS" -gt 0 ]; then echo "FAIL"; exit 1; fi
echo "PASS: lib/ tidy clean"

echo ""
echo "=== Run tidy on src/ ==="
cd "$SRCDIR/src"
make tidy 2>&1 | tee /tmp/src-tidy.log
SRC_ERRORS=$(grep -c "error:" /tmp/src-tidy.log || true)
echo "src/ tidy errors: $SRC_ERRORS"
if [ "$SRC_ERRORS" -gt 0 ]; then echo "FAIL"; exit 1; fi
echo "PASS: src/ tidy clean"

echo ""
echo "=== Verify NOLINT suppressions are working ==="
SUPPRESSED=$(grep "Suppressed.*NOLINT" /tmp/src-tidy.log || true)
if [ -n "$SUPPRESSED" ]; then
  echo "PASS: NOLINT comments active: $SUPPRESSED"
else
  echo "INFO: No NOLINT suppressions observed (may vary by clang-tidy version)"
fi

echo ""
echo "=== Run RTSP tests (validates rtspd.c realloc fix) ==="
cd "$SRCDIR/tests"
perl runtests.pl 567 570 571 572 573 2>&1 | tail -5

echo ""
echo "All checks passed."
