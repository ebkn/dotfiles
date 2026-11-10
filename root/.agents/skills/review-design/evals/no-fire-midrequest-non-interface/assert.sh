#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- both requests carried out ---
check_eq "an upper-case unit is read" "12.5" "$(./total.sh 12.5T 2>/dev/null || true)"
check_match "MB comes from 1024" '^1\.[0-9] MB' \
  "$(format_size 1048576 2>/dev/null || bash -c '. lib/size.sh; format_size 1048576')"
check "the tests pass" ./run-tests.sh
check "committed both fixes" test "$(git rev-list --count eval-base..HEAD)" -ge 2
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- no fork mid-request, one at the boundary (root/review-breakpoints.md) ---
# Neither commit adds or changes an interface, so the per-commit review the
# old policy promised does not exist here: the first fork, if the CLAUDE.md
# boundary owed one, sits after the second commit. Counted as <= 1 rather
# than == 1: the description-only reality of small non-interface fixes at a
# boundary is not pinned, only the mid-request silence is.
check_match "review-design ran at most once" '^(0|1)$' \
  "$(transcript_skill_uses review-design)"
no_fork_before_the_boundary() {
  local commits skillat
  commits="$(transcript_command_indexes 'git commit' | tail -n 1)"
  skillat="$(transcript_first_tool_index Skill)"
  [ -z "$skillat" ] && return 0
  [ -n "$commits" ] && [ "$skillat" -gt "$commits" ]
}
check "no fork before the last commit" no_fork_before_the_boundary
review_loop_rounds_capped review-design

skill_eval_finish
