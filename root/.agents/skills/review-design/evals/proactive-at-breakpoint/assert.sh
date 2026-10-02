#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/grading.sh"

skill_uses="$(transcript_skill_uses review-design)"
closing="$(transcript_result_text)"

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

# --- the report of a review nobody asked for ---
# It opens the closing message, where the user reads, once the fixes are
# committed. A run that folded the review into the work left the findings a
# line in the summary at best, or out altogether. Three lines allow a sentence
# of preamble before the heading, as in the grading of a requested review.
# shellcheck disable=SC2329
opens_with_the_report() {
  head -n 3 <<<"$closing" | jq -Rse --arg re "$REVIEW_DESIGN_REPORT_HEADING" 'test($re)' >/dev/null
}
check "opens the closing message with the review report" opens_with_the_report
# The range is the one reviewed: from the merge-base with main to a commit of
# the unit on this branch -- not eval-base itself, and nothing off the branch.
# Whether its head stops short of the fix commits is left to SKILL.md; which
# commits made the unit is not visible from here.
# shellcheck disable=SC2329
names_a_range_on_the_branch() {
  local line base head
  line="$(grep -oE 'Reviewed: [0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' <<<"$closing" | head -n 1)"
  [ -n "$line" ] || return 1
  base="${line#Reviewed: }"
  head="${base#*..}"
  base="${base%%..*}"
  case "$(git rev-parse eval-base)" in "$base"*) ;; *) return 1 ;; esac
  git merge-base --is-ancestor eval-base "$head" || return 1
  git merge-base --is-ancestor "$head" HEAD || return 1
  [ "$(git rev-parse "$head")" != "$(git rev-parse eval-base)" ]
}
check "names the range it reviewed, from eval-base to a commit on the branch" names_a_range_on_the_branch
# One review plus at most three re-reviews.
check "kept the review loop within its cap of four" test "$skill_uses" -le 4

skill_eval_finish
