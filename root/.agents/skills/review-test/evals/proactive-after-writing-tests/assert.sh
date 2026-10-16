#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/grading.sh"

result="$(transcript_result_text)"
skill_uses="$(transcript_skill_uses review-test)"
report_at="$(review_test_report_index)"

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
check "reports under a test-review heading" test -n "$report_at"

# --- the loop afterwards ("## After the review") ---
check_llm "reaches a conclusion about P1 and P2" \
  'The text is the final answer to a request to write tests. It passes if it says one of these about the P1 *and* P2 findings of the test review: that there were none, that they were fixed, or which ones are left and why. It fails if it addresses only P1 and never P2, if it only reports that tests were written, or if it asks the reader whether to fix the findings instead of having fixed them.' \
  "$result"
# Whether the first round finds anything depends on the tests this run wrote,
# so two rounds are not required -- only the shared loop checks.
review_loop_checks review-test
# The step the review loop ends on. A fix left in the working tree is
# indistinguishable from a review that was never acted on, which is why the
# commit is asserted rather than inferred from the report.
check "committed the result" \
  test "$(git rev-list --count eval-base..HEAD)" -ge 1

# --- when it starts: at the breakpoint ("## When to start") ---
# Once per unit of work, after its commits, as review-design does. A review
# started before the commit is the per-batch trigger this replaced, which
# re-ran a forked review after every round of test edits.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
started_after_the_commit() {
  local first_skill first_commit
  # The first call of review-test, not of any skill: a real run called
  # `commit` before committing, and that is not the review starting early.
  first_skill="$(transcript_skill_rounds review-test | jq -s '.[0].index // empty')"
  first_commit="$(transcript_first_command_index '(^|[;&|(]|[[:space:]])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)')"
  [ -n "$first_skill" ] && [ -n "$first_commit" ] && [ "$first_skill" -gt "$first_commit" ]
}
check "started it at the breakpoint: after the work was committed" started_after_the_commit

skill_eval_finish
