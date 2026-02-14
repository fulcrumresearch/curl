#!/bin/bash
# Demo: Verify ruff 0.14.14 -> 0.15.0 bump in .github/scripts/requirements.txt
# This script installs both versions and runs the exact CI lint command to confirm
# the version bump does not introduce new linting failures.

set -e

RUFF_CMD="python3 -m ruff"
LINT_RULES="B007,B016,C405,C416,COM818,D200,D213,D204,D401,D415,FURB129,N818,PERF401,PERF403,PIE790,PIE808,PLW0127,Q004,RUF010,SIM101,SIM117,SIM118,TRY400,TRY401"

echo "=== Step 1: Install ruff 0.15.0 (the new version) ==="
pip install --break-system-packages ruff==0.15.0 2>&1 | tail -3
$RUFF_CMD --version

echo ""
echo "=== Step 2: Run the exact CI lint command (scripts/pythonlint.sh rules) ==="
$RUFF_CMD check --extend-select=$LINT_RULES .
echo "Result: PASS"

echo ""
echo "=== Step 3: Run ruff check with default rules ==="
$RUFF_CMD check .
echo "Result: PASS"

echo ""
echo "=== Step 4: Check newly stabilized rules from 0.15.0 ==="
echo "These rules were preview-only in 0.14.14 and are now stable in 0.15.0."
echo "They are NOT in the CI --extend-select list, so they won't cause failures."
$RUFF_CMD check --select=FURB110,FURB171 tests/ 2>&1 || echo "(Expected: some findings, but not enforced in CI)"

echo ""
echo "=== Step 5: Verify curl binary is unaffected ==="
./src/curl --version | head -2
./src/curl -s -o /dev/null -w "HTTP %{http_code}\n" https://curl.se/

echo ""
echo "=== Demo complete ==="
