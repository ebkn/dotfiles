#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/grading.sh"

report_at="$(review_design_report_index)"
report="$(review_design_report_text "$report_at")"
skill_uses="$(transcript_skill_uses review-design)"

# --- the review ---
check "started review-design" test "$skill_uses" -ge 1
check "reported under a design-review heading" test -n "$report"
check "names the range it reviewed: eval-base..unit-done" \
  review_design_names_range "$report" eval-base unit-done
check_llm "raises no P1 against a unit whose docs moved with its code" \
  'The text is a design review of a change whose code, comments, usage text and README all agree. It passes if the review raises no P1 -- either the P1 section is absent, or it says explicitly that nothing meets the P1 criteria. Findings at P2 or P3, and questions put to the user, are fine and do not fail this. It fails if any finding is presented as P1.' \
  "$report"
# A report with nothing in it cannot tell a clean change from an unread one,
# so a review that finds nothing has to say what it looked at. It also keeps
# this case from passing on a review that never opened the files.
check_llm "says what it checked, having found nothing to fix" \
  'The text is a design review of a change to a small project that totals weights: a function comment in lib/quantity.sh, the usage text of total.sh and a README. It passes if the review either raises at least one finding ranked P1, P2 or P3, or -- having no ranked finding at all -- lists what it checked, naming at least the comment, the usage text and the README as compared with the code. Questions put to the user do not count as findings. It fails if it has no ranked finding and does not say what it compared.' \
  "$report"

# --- whatever the caller did afterwards ---
# A P2 may be raised and fixed without asking, so an edit here is allowed
# behaviour rather than a violation. What has to hold is that it left the
# behaviour and the truth of the docs alone, and was committed on its own.
check "changed none of the unit's tests (new ones may be added)" \
  review_design_kept_existing_tests lib/quantity.test.sh total.test.sh
check "the tests still pass afterwards" ./run-tests.sh
check_eq "left what an all-unreadable total does as the unit made it" "0 (status 0)" \
  "$(review_design_total_of twelve)"
check_llm "the docs still describe skipping" \
  "$REVIEW_DESIGN_SKIPPING_DOCS_RUBRIC" "$(review_design_skipping_docs)"
check "kept the unit's commit as it was" git merge-base --is-ancestor unit-done HEAD
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"
# One review plus at most three re-reviews.
check "kept the review loop within its cap of four" test "$skill_uses" -le 4

# --- the boundary: the skill reads, the caller writes ---
check "wrote nothing before the review was reported" \
  review_design_wrote_nothing_before "$report_at"
check "ran no git that writes before the review was reported" \
  review_design_ran_no_writing_git_before "$report_at"

skill_eval_finish
