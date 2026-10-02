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
# Here the range is the unit alone: from the merge-base with main (eval-base)
# to the unit's commit.
check "names the range it reviewed: eval-base..unit-done" \
  review_design_names_range "$report" eval-base unit-done
# The interface list is what lets a reader see at a glance what a change
# exposed, and the callers it records are what later decides who must agree to
# a fix. total.sh calls sum_quantities but was not touched by the unit, so it
# is a caller outside the range.
check_llm "lists the changed interface with its caller outside the range" \
  'The text is a design review. It passes if it lists the interfaces the change touched, and that list includes sum_quantities, described in about one sentence from the point of view of a caller (what it does, not how), with total.sh recorded as a caller of it that lies outside the reviewed range (or as "outside"). It fails if there is no such list, if sum_quantities is missing from it, or if total.sh is not recorded as a caller outside the range.' \
  "$report"
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
  "$REVIEW_DESIGN_SKIPPING_DOCS_RUBRIC" "$(review_design_skipping_docs)"

# The unit's tests are its specification of the new behaviour. Drift "fixed" by
# turning the code back to match the docs would have to change them, so they
# must come out of this untouched and still passing.
check_eq "left the unit's tests untouched" "" \
  "$(git diff --name-only unit-done -- lib/quantity.test.sh total.test.sh)"
check "the tests still pass afterwards" ./run-tests.sh
check_eq "left what an all-unreadable total does as the unit made it" "0 (status 0)" \
  "$(review_design_total_of twelve)"

# The fix is a commit of its own after the unit's: the review is what justifies
# it, and amending the unit would bury that.
check "kept the unit's commit as it was" git merge-base --is-ancestor unit-done HEAD
check "committed the fix on its own" test "$(git rev-list --count unit-done..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"
# One review plus at most three re-reviews.
check "kept the review loop within its cap of four" test "$skill_uses" -le 4

# --- the boundary: the skill reads, the caller writes ---
check "wrote nothing before the review was reported" \
  review_design_wrote_nothing_before "$report_at"
check "ran no git that writes before the review was reported" \
  review_design_ran_no_writing_git_before "$report_at"

skill_eval_finish
