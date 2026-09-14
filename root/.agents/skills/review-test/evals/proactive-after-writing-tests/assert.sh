#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

result="$(transcript_result_text)"
skill_uses="$(transcript_skill_uses review-test)"
report_heading='テストレビュー|[Tt]est review'
report_at="$(transcript_first_text_index "$report_heading")"

# --- the request itself was carried out ---
check "wrote a test file for lib/quantity.sh" \
  test -f lib/quantity.test.sh
check "the tests it wrote pass" \
  ./run-tests.sh
# Answering a review finding by changing the implementation would invert the
# premise that the tests are the specification, so the implementation is
# expected to come out of this untouched.
check_eq "left the implementation untouched" "" "$(git diff --name-only eval-base -- lib/quantity.sh)"

# --- starting on its own ("## When to start") ---
# Nothing in the prompt asks for a review. This is the whole measurement.
check "started review-test without being asked" test "$skill_uses" -ge 1
check_match "reports under a test-review heading" "$report_heading" "$(cat "$SKILL_EVAL_TRANSCRIPT")"

# --- the loop afterwards ("## After the review") ---
# One review plus at most three re-reviews. More than that is a loop running
# past the cap the skill sets for itself.
check "kept the review loop within its cap of four" test "$skill_uses" -le 4
check_llm "reaches a conclusion about P1 and P2" \
  'The text is the final answer to a request to write tests. It passes if it says one of these about the P1 *and* P2 findings of the test review: that there were none, that they were fixed, or which ones are left and why. It fails if it addresses only P1 and never P2, if it only reports that tests were written, or if it asks the reader whether to fix the findings instead of having fixed them.' \
  "$result"
# The step the review loop ends on. A fix left in the working tree is
# indistinguishable from a review that was never acted on, which is why the
# commit is asserted rather than inferred from the report.
check "committed the result" \
  test "$(git rev-list --count eval-base..HEAD)" -ge 1

# --- the boundary: the skill reads, the caller writes ---
# Writing is the point of this case, so Write and Edit say nothing here. git
# still does: the skill body forbids it outright, and pre-approving it in the
# frontmatter is precisely the host that body is written for.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
ran_no_git_before_the_report() {
  local first
  [ -n "$report_at" ] || return 1
  first="$(transcript_first_command_index '(^|[^[:alnum:]_-])git([^[:alnum:]_-]|$)')"
  [ -n "$first" ] || return 0
  [ "$first" -gt "$report_at" ]
}
check "ran no git before the review was reported" ran_no_git_before_the_report

skill_eval_finish
