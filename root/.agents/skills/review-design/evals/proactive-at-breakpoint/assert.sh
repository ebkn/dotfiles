#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/grading.sh"

skill_uses="$(transcript_skill_uses review-design)"
report="$(review_design_report_text "$(review_design_report_index)")"

# --- the request itself was carried out ---
check_match "total.sh --kg prints the total in kilograms" '3000' \
  "$(./total.sh --kg 1t 2t 2>/dev/null || true)"
check "the tests pass" ./run-tests.sh
check "committed the work" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- starting on its own ("## When to start") ---
# Nothing in the prompt asks for a review. This is the whole measurement.
check "started review-design without being asked" test "$skill_uses" -ge 1
# A breakpoint is a unit of work committed, not a moment in the middle of it:
# a review started before the commit would review half a change.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
started_after_the_commit() {
  local first_skill first_commit
  first_skill="$(transcript_first_tool_index Skill)"
  first_commit="$(transcript_first_command_index '(^|[;&|(]|[[:space:]])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)')"
  [ -n "$first_skill" ] && [ -n "$first_commit" ] && [ "$first_skill" -gt "$first_commit" ]
}
check "started it at the breakpoint: after the work was committed" started_after_the_commit
check "reported under a design-review heading" test -n "$report"
# One review plus at most three re-reviews.
check "kept the review loop within its cap of four" test "$skill_uses" -le 4

skill_eval_finish
