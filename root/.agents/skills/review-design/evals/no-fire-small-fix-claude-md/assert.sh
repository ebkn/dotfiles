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
# commit, ending within the cap.
check_eq "one review-design fork, at the boundary" "1" \
  "$(transcript_skill_uses review-design)"
boundary_only() {
  local commits skillat
  commits="$(transcript_command_indexes 'git commit' | tail -n 1)"
  skillat="$(transcript_first_tool_index Skill)"
  [ -n "$skillat" ] && [ -n "$commits" ] && [ "$skillat" -gt "$commits" ]
}
check "the fork is at the boundary" boundary_only
review_loop_rounds_capped review-design
review_loop_ended_clean review-design

skill_eval_finish
