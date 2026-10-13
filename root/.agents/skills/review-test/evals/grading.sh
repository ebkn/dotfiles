# grading.sh — what every review-test eval case reads off a run the same way.
#
# Sourced by a case's assert.sh after bin/skill-eval-assert.sh, whose
# transcript_* helpers it uses. Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# The report's own heading line ("## Test review: [what was reviewed]" in
# SKILL.md, translated), not any mention of a test review. Two things it must
# not match, both pinned by evals/assert.test.sh:
# - the template itself, which the Skill tool loads as part of the SKILL.md
#   body, and the forked skill's report, which comes back as the Skill's
#   tool_result and which the user does not necessarily see -- so it is
#   searched for in assistant text blocks only, never in the transcript as a
#   whole: a report counts once the caller has written it out. Those blocks are
#   the caller's only because the fork emitted no text record of its own in any
#   measured run; transcript_first_text_index does not look at
#   parent_tool_use_id;
# - a preamble such as "テストレビューを始めます", which would move "nothing
#   written before the report" to before the write. The colon after the title
#   is what tells the two apart.
# `##` or bold is formatting the model varies, so either is accepted. `(^|\n)`
# because jq's `^` anchors at the start of the text block only.
REVIEW_TEST_REPORT_HEADING='(^|\n)(#+ *|\*\*)?(テストレビュー|[Tt]est [Rr]eview) *[:：]'

# review_test_report_index
# The transcript record holding the first report; empty when there is none.
review_test_report_index() {
  transcript_first_text_index "$REVIEW_TEST_REPORT_HEADING"
}

# review_test_wrote_nothing_before <index>
# review_test_ran_no_git_before <index>
# "Never wrote" stopped being true of a whole run once the caller began fixing
# findings, so what separates the skill from its caller is order: nothing
# written, and no git run, before the review was reported. Both fail when there
# is no report to be before. git at all, not only git that writes: the skill
# body forbids it outright, and a host that pre-approves it is precisely the
# one that body is written for.
review_test_wrote_nothing_before() {
  [ -n "$1" ] || return 1
  if transcript_tool_uses_precede Write "$1"; then return 1; fi
  if transcript_tool_uses_precede Edit "$1"; then return 1; fi
  return 0
}

review_test_ran_no_git_before() {
  local first
  [ -n "$1" ] || return 1
  first="$(transcript_first_command_index '(^|[^[:alnum:]_-])git([^[:alnum:]_-]|$)')"
  [ -n "$first" ] || return 0
  [ "$first" -gt "$1" ]
}
