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
# The mid-request half of the pair (no-fire-small-fix-claude-md carries the
# CLAUDE.md side): with the skill's description alone, whether the request's
# own boundary review fires is not pinned — only that no fork ran before the
# fix's commit finished, and that at most one fork happened at all.
check_match "review-design ran at most once" '^(0|1)$' \
  "$(transcript_skill_uses review-design)"
# A fork, if it ran at all, sits at the boundary: after the fix's last commit.
# check invokes the guard by name, so shellcheck cannot see the call site.
# shellcheck disable=SC2329
if_boundary_then_after_commit() {
  local commits skillat
  commits="$(transcript_command_indexes 'git commit' | tail -n 1)"
  skillat="$(transcript_first_tool_index Skill)"
  [ -z "$skillat" ] && return 0
  [ -n "$commits" ] && [ "$skillat" -gt "$commits" ]
}
check "a fork, if any, ran at the boundary" if_boundary_then_after_commit

skill_eval_finish
