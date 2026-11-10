#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- the request itself was carried out ---
check_eq "an upper-case unit is read" "12.5" "$(./total.sh 12.5T 2>/dev/null || true)"
check "the tests pass" ./run-tests.sh
check "committed the fix" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- the boundary shape (root/review-breakpoints.md) ---
# One small non-interface fix is the whole request, so its boundary review is
# the one fork this policy owes: exactly one review-design run, after the
# commit, ending in a clean round.
check_eq "one review-design fork, at the boundary" "1" \
  "$(transcript_skill_uses review-design)"
# check invokes the guard by name, so shellcheck cannot see the call site.
# shellcheck disable=SC2329
boundary_only() {
  local first_skill commits
  # The first call of review-design, not of any Skill: with root/CLAUDE.md a
  # correct run calls `commit` before committing (proactive-at-breakpoint
  # hits the same hazard and takes the skill's own rounds for the same
  # reason).
  first_skill="$(transcript_skill_rounds review-design | jq -s '.[0].index // empty')"
  commits="$(transcript_command_indexes 'git commit' | tail -n 1)"
  [ -n "$first_skill" ] && [ -n "$commits" ] && [ "$first_skill" -gt "$commits" ]
}
check "the fork is at the boundary" boundary_only
# The count above already bounds the loop at one call; the cap adds nothing
# there, so only the stopping rule is worth its own check — bare calls fail
# without a FAIL line and would say nothing the count does not.
check "the boundary review ended clean" review_loop_ended_clean review-design

skill_eval_finish
