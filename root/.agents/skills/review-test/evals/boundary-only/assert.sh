#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- the request itself was carried out ---
check "the five helpers exist and behave" bash -c '
  . ./calc.sh
  [ "$(inc 4)" = "5" ] &&
  [ "$(dbl -3)" = "-6" ] &&
  [ "$(negate 7)" = "-7" ] &&
  [ "$(abs -2)" = "2" ] &&
  [ "$(max 3 9)" = "9" ] &&
  [ "$(max -5 -9)" = "-5" ]
'
check "the tests pass" ./run-tests.sh
check "committed five steps" test "$(git rev-list --count eval-base..HEAD)" -ge 5
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- forks only at the boundary, within the cap ---
# Every commit changed what the tests assert, which is the shape the old
# per-commit trigger fired on; the policy owes one fork, at the boundary,
# and stops within two re-rounds.
check_eq "review-test ran exactly once" "1" "$(transcript_skill_uses review-test)"
boundary_only() {
  local commits skillat
  commits="$(transcript_command_indexes 'git commit' | tail -n 1)"
  skillat="$(transcript_first_tool_index Skill)"
  [ -n "$skillat" ] && [ -n "$commits" ] && [ "$skillat" -gt "$commits" ]
}
check "the fork is at the boundary" boundary_only
review_loop_rounds_capped review-test

skill_eval_finish
