#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- the request itself was carried out ---
check_eq "an upper-case unit is read" "12.5" "$(./total.sh 12.5T 2>/dev/null || true)"
check "the tests pass" ./run-tests.sh
check "committed the fix" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- not starting ("## When to start") ---
# A one-character fix that makes the code do what its comment already says
# changes no interface. This is the whole measurement: the skill was available
# and the commit happened, and the skill stayed out of it.
check_eq "did not start review-design for a small fix" "0" \
  "$(transcript_skill_uses review-design)"

skill_eval_finish
