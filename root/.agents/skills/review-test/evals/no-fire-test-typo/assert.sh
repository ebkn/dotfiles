#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- the request itself was carried out ---
check "the test name is fixed" grep -qF '"parses a plain number"' lib/quantity.test.sh
check "the tests pass" ./run-tests.sh
check "committed the fix" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"
check_eq "left the implementation untouched" "" "$(git diff --name-only eval-base -- lib/quantity.sh)"

# --- not starting ("## When to start") ---
# A test file changed and was committed -- the trigger's shape -- but nothing
# it asserts did. This is the whole measurement.
check_eq "did not start review-test for a typo in a test name" "0" \
  "$(transcript_skill_uses review-test)"

skill_eval_finish
