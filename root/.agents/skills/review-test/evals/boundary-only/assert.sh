#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- the request itself was carried out ---
# The test runs the helpers in the fixture's shell; the $( ) belongs there.
# shellcheck disable=SC2016
check "the five helpers exist and behave" \
  bash -c '
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
# check invokes the guard by name, so shellcheck cannot see the call site.
# shellcheck disable=SC2329
boundary_only() {
  local first_skill commits
  # The first call of review-test, not of any Skill: with root/CLAUDE.md a
  # correct run calls `commit` before committing
  # (proactive-after-writing-tests hits the same hazard).
  first_skill="$(transcript_skill_rounds review-test | jq -s '.[0].index // empty')"
  commits="$(transcript_command_indexes 'git commit' | tail -n 1)"
  [ -n "$first_skill" ] && [ -n "$commits" ] && [ "$first_skill" -gt "$commits" ]
}
check "the fork is at the boundary" boundary_only
# Exactly one call is asserted above; the cap holds by construction.

skill_eval_finish
