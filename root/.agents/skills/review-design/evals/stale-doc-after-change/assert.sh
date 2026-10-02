#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# The report's own heading line, not any mention of a design review: a preamble
# such as "設計レビューを始めます" must not count as having reported. The colon
# after the title is what tells the two apart. How the line is set -- a `##`
# heading or bold -- is formatting the model varies, so either is accepted.
# `(^|\n)` rather than a bare `^`: jq's `^` anchors at the start of the text
# block only, and a report may follow a sentence of preamble.
report_heading='(^|\n)(#+ *|\*\*)?(設計レビュー|[Dd]esign [Rr]eview) *[:：]'
report_at="$(transcript_first_text_index "$report_heading")"
report=""
if [ -n "$report_at" ]; then
  report="$(jq -rs --argjson i "$report_at" \
    '.[$i].message.content[]? | select(.type == "text") | .text' "$SKILL_EVAL_TRANSCRIPT")"
fi
skill_uses="$(transcript_skill_uses review-design)"

# --- the review ---
check "started review-design" test "$skill_uses" -ge 1
check "reported under a design-review heading" test -n "$report"
# The next review in the same conversation starts from this line, so it is a
# contract with the skill's own next run, not decoration. Hashes, because a
# branch name moves.
check_match "ends the report with the range it reviewed" \
  'Reviewed: [0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' "$report"
check_llm "P1 names a doc that still describes the refusal" \
  'The text is a design review of a change that made sum_quantities skip a weight it cannot read (with a warning on stderr) instead of refusing the whole total. It passes if a finding ranked P1 says that some documentation still describes the old behaviour -- the comment on sum_quantities, the usage text of total.sh, or the README -- that is, that one unreadable weight refuses or fails the total, or that nothing is printed. Naming any one of the three is enough. It fails if no finding is ranked P1, or if every P1 finding is about something else.' \
  "$report"

# --- the fix that has to follow it ("## After the review") ---
# Each of these sentences is false of the code the unit committed, so a fix
# that leaves any one of them in place has not fixed the drift.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
lacks() { ! grep -qF -- "$1" "$2"; }
check "sum_quantities' comment no longer promises no partial sum" \
  lacks "A partial sum is never printed" lib/quantity.sh
check "total.sh's usage text no longer promises to print nothing" \
  lacks "nothing is printed and the exit status is 1" total.sh
check "the README no longer says an unreadable weight fails the total" \
  lacks "prints nothing and exits 1" README.md
check_llm "all three docs now describe skipping" \
  'The text holds three files of a small project that totals weights. It passes only if the documentation in all three -- the comment above sum_quantities in lib/quantity.sh, the usage text inside total.sh, and the README prose -- says that a weight that cannot be read is skipped (or ignored, or left out) while the remaining weights are still totalled. It fails if any one of the three still says that an unreadable weight refuses or fails the total, or that nothing is printed.' \
  "$(printf -- '--- lib/quantity.sh\n%s\n\n--- total.sh\n%s\n\n--- README.md\n%s\n' \
    "$(cat lib/quantity.sh)" "$(cat total.sh)" "$(cat README.md)")"

# The unit's tests are its specification of the new behaviour. Drift "fixed" by
# turning the code back to match the docs would have to change them, so they
# must come out of this untouched and still passing.
check_eq "left the unit's tests untouched" "" \
  "$(git diff --name-only unit-done -- lib/quantity.test.sh total.test.sh)"
check "the tests still pass afterwards" ./run-tests.sh
# The tests never feed in nothing but unreadable weights, and what that should
# do is exactly the open question a good review raises (0 and status 0 cannot be
# told apart from a real zero). Answering it in code would pass every test
# above, so pin what the unit made it do: deciding it is the user's call.
behaviour() {
  local out status=0
  out="$(./total.sh "$@" 2>/dev/null)" || status=$?
  printf '%s (status %s)' "$out" "$status"
}
check_eq "left what an all-unreadable total does as the unit made it" "0 (status 0)" \
  "$(behaviour twelve)"

# The fix is a commit of its own after the unit's: the review is what justifies
# it, and amending the unit would bury that.
check "kept the unit's commit as it was" git merge-base --is-ancestor unit-done HEAD
check "committed the fix on its own" test "$(git rev-list --count unit-done..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"
# One review plus at most three re-reviews.
check "kept the review loop within its cap of four" test "$skill_uses" -le 4

# --- the boundary: the skill reads, the caller writes ---
# The caller writes and commits in this same run, so what separates the skill
# from it is order: nothing written before the report. Unlike review-test this
# skill runs git while it reviews -- the range is its input -- so the line is
# drawn at git that writes, not at git.
# `check` calls these by name, which shellcheck cannot see.
# shellcheck disable=SC2329
wrote_nothing_before_the_report() {
  [ -n "$report_at" ] || return 1
  if transcript_tool_uses_precede Write "$report_at"; then return 1; fi
  if transcript_tool_uses_precede Edit "$report_at"; then return 1; fi
  return 0
}
writing_git='(^|[;&|(]|[[:space:]])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+--no-pager)*[[:space:]]+(add|am|apply|checkout|cherry-pick|commit|merge|mv|push|rebase|reset|restore|revert|rm|stash|switch)([[:space:]]|$)|git[^|;&]*--output([=[:space:]]|$)'
# shellcheck disable=SC2329
ran_no_writing_git_before_the_report() {
  local first
  [ -n "$report_at" ] || return 1
  first="$(transcript_first_command_index "$writing_git")"
  [ -n "$first" ] || return 0
  [ "$first" -gt "$report_at" ]
}
check "wrote nothing before the review was reported" wrote_nothing_before_the_report
check "ran no git that writes before the review was reported" ran_no_writing_git_before_the_report

skill_eval_finish
