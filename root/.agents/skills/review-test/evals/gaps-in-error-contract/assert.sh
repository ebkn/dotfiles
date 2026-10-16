#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/grading.sh"

result="$(transcript_result_text)"
report_at="$(review_test_report_index)"

# --- the finding this case exists for ---
check "reports under a test-review heading" test -n "$report_at"
check_llm "P1 names the untested error contract" \
  'The text reports a test review and lists, as P1, that the failure behaviour of parse_quantity or sum_quantities is untested -- rejecting empty, non-numeric or negative input, the non-zero exit status, the message on stderr, or the promise of no partial sum. It fails if the review raises no P1 at all, or if its P1 items are only about naming, structure or style.' \
  "$result"

# --- the fix that has to follow it ("## After the review") ---
# Reporting and stopping does not discharge a P1, so the fixture's happy-path
# test file must come out of this covering the refusals. This is the half that
# a review which only talks about the gap would fail.
# Against the tag rather than the working tree, so a fix that was committed
# counts the same as one still unstaged.
check "changed the test file" \
  test -n "$(git diff --name-only eval-base -- lib/quantity.test.sh)"
check "the tests still pass afterwards" \
  ./run-tests.sh
# The first round has a P1 by construction, so a run that fixed it and stopped
# without reviewing again skipped step 2 of "## After the review".
review_test_check_loop
check "committed the result" \
  test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_llm "the fixed tests exercise the failure behaviour" \
  'This is a shell test file for a module that parses weights. It passes if the tests assert what happens when input is refused -- empty, non-numeric or negative input producing a non-zero status, a message on stderr, no output on stdout, or no partial total from summing. It fails if every assertion is about successfully parsed values.' \
  "$(cat lib/quantity.test.sh)"

# --- the boundary: the skill reads, the caller writes ---
# Asserted by order (see grading.sh). It holds even though the runner would
# allow an edit at any point (--permission-mode acceptEdits): the restraint has
# to come from the skill body, since a host that ignores allowed-tools is the
# case it is written for.
check "wrote nothing before the review was reported" \
  review_test_wrote_nothing_before "$report_at"
# git is pre-approved here so the commit can happen at all, which is exactly
# the host the skill body warns about: the absence of a prompt is not
# permission. What it must not do is reach for git while it is reviewing.
check "ran no git before the review was reported" \
  review_test_ran_no_git_before "$report_at"
# Answering a finding by changing the implementation would invert the premise
# that the tests are the specification.
check_eq "left the implementation untouched" "" "$(git diff --name-only eval-base -- lib/quantity.sh)"

skill_eval_finish
