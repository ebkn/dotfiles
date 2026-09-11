#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

result="$(transcript_result_text)"
skill_uses="$(transcript_skill_uses review-test)"

# --- the request itself was carried out ---
check "wrote a test file for lib/quantity.sh" \
  test -f lib/quantity.test.sh
check "the tests it wrote pass" \
  ./run-tests.sh
# Answering a review finding by changing the implementation would invert the
# premise that the tests are the specification, so the implementation is
# expected to come out of this untouched.
check_eq "left the implementation untouched" "" "$(git status --porcelain -- lib/quantity.sh)"
check_eq "made no commit" 0 "$(git rev-list --count eval-base..HEAD)"

# --- starting on its own ("## When to start") ---
# Nothing in the prompt asks for a review. This is the whole measurement.
check "started review-test without being asked" test "$skill_uses" -ge 1
check_match "reports under a test-review heading" 'テストレビュー|[Tt]est review' "$(cat "$SKILL_EVAL_TRANSCRIPT")"

# --- the loop afterwards ("## After the review") ---
# One review plus at most three re-reviews. More than that is a loop running
# past the cap the skill sets for itself.
check "kept the review loop within its cap of four" test "$skill_uses" -le 4
check_llm "reaches a conclusion about P1" \
  'The text is the final answer to a request to write tests. It passes if it says one of these about the P1 findings of the test review: that there were none, that they were fixed, or which ones are left and why. It fails if it only reports that tests were written and never addresses P1 at all.' \
  "$result"

skill_eval_finish
