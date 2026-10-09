# grading.sh — what every review-test eval case reads off a run the same way.
#
# Sourced by a case's assert.sh after bin/skill-eval-assert.sh, whose
# transcript_* helpers it uses. Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# The report's own heading line ("## Test review: [what was reviewed]" in
# SKILL.md, translated), not any mention of a test review. Two things it must
# not match, both found by evals/assert.test.sh:
# - the template itself, which sits in the transcript as part of the SKILL.md
#   body the Skill tool loads -- so it is searched for in the model's text
#   blocks only, never in the transcript as a whole;
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
