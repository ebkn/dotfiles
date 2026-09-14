#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

result="$(transcript_result_text)"
report_heading='テストレビュー|[Tt]est review'
report_at="$(transcript_first_text_index "$report_heading")"

# --- the finding this case exists for ---
check_match "reports under a test-review heading" "$report_heading" "$(cat "$SKILL_EVAL_TRANSCRIPT")"
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
check "committed the result" \
  test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_llm "the fixed tests exercise the failure behaviour" \
  'This is a shell test file for a module that parses weights. It passes if the tests assert what happens when input is refused -- empty, non-numeric or negative input producing a non-zero status, a message on stderr, no output on stdout, or no partial total from summing. It fails if every assertion is about successfully parsed values.' \
  "$(cat lib/quantity.test.sh)"

# --- the boundary: the skill reads, the caller writes ---
# "Never wrote" stopped being true of a whole run once the caller began fixing
# findings, so what is asserted is the order: nothing may be written before the
# review has been reported. That still separates the skill from its caller, and
# it holds even though the runner would allow an edit at any point
# (--permission-mode acceptEdits) -- the restraint has to come from the skill
# body, since a host that ignores allowed-tools is the case it is written for.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
wrote_nothing_before_the_report() {
  [ -n "$report_at" ] || return 1
  if transcript_tool_uses_precede Write "$report_at"; then return 1; fi
  if transcript_tool_uses_precede Edit "$report_at"; then return 1; fi
  return 0
}
check "wrote nothing before the review was reported" wrote_nothing_before_the_report
# git is pre-approved here so the commit can happen at all, which is exactly
# the host the skill body warns about: the absence of a prompt is not
# permission. What it must not do is reach for git while it is reviewing.
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
# Answering a finding by changing the implementation would invert the premise
# that the tests are the specification.
check_eq "left the implementation untouched" "" "$(git diff --name-only eval-base -- lib/quantity.sh)"

skill_eval_finish
