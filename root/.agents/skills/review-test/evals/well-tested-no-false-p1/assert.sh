#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/grading.sh"

result="$(transcript_result_text)"
report_at="$(review_test_report_index)"

check "reports under a test-review heading" test -n "$report_at"
check_llm "raises no P1 against tests that cover the contract" \
  'The text reports a test review of tests that already cover the contract. It passes if the review raises no P1 -- either the P1 section is absent, or it says explicitly that nothing meets the P1 criteria. Findings at P2 or P3 are fine and do not fail this. It fails if any finding is presented as P1.' \
  "$result"

# This case no longer asserts that nothing was written. P2 findings are fixed
# without asking, and a review of even thorough tests can raise one, so an edit
# here is allowed behaviour rather than a violation. What still has to hold is
# that the edit came after the report, and that it left the specification's
# subject and the suite's result alone.
check "wrote nothing before the review was reported" \
  review_test_wrote_nothing_before "$report_at"
check_eq "left the implementation untouched" "" "$(git diff --name-only eval-base -- lib/quantity.sh)"
check "the tests still pass afterwards" \
  ./run-tests.sh

# Tests that already cover the contract leave nothing to fix, so a second
# round would re-read everything for nothing.
check "did not re-run after a round with no P1 or P2" \
  review_loop_reran_only_after_findings review-test

skill_eval_finish
