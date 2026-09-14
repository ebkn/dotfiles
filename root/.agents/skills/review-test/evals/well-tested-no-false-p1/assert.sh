#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

result="$(transcript_result_text)"
report_heading='テストレビュー|[Tt]est review'
report_at="$(transcript_first_text_index "$report_heading")"

check_match "reports under a test-review heading" "$report_heading" "$(cat "$SKILL_EVAL_TRANSCRIPT")"
check_llm "raises no P1 against tests that cover the contract" \
  'The text reports a test review of tests that already cover the contract. It passes if the review raises no P1 -- either the P1 section is absent, or it says explicitly that nothing meets the P1 criteria. Findings at P2 or P3 are fine and do not fail this. It fails if any finding is presented as P1.' \
  "$result"

# This case no longer asserts that nothing was written. P2 findings are fixed
# without asking, and a review of even thorough tests can raise one, so an edit
# here is allowed behaviour rather than a violation. What still has to hold is
# that the edit came after the report, and that it left the specification's
# subject and the suite's result alone.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
wrote_nothing_before_the_report() {
  [ -n "$report_at" ] || return 1
  if transcript_tool_uses_precede Write "$report_at"; then return 1; fi
  if transcript_tool_uses_precede Edit "$report_at"; then return 1; fi
  return 0
}
check "wrote nothing before the review was reported" wrote_nothing_before_the_report
check_eq "left the implementation untouched" "" "$(git diff --name-only eval-base -- lib/quantity.sh)"
check "the tests still pass afterwards" \
  ./run-tests.sh

skill_eval_finish
