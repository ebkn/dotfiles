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
check_llm "P1 ties the scattered unit formatting to the planned kg output" \
  'The text is a design review of a change in which total.sh and delivery.sh each print a total with the unit "t" written into their own printf. The next planned change is to print totals in kilograms as well. It passes if a finding ranked P1 says that this planned change would have to edit more than one place -- both scripts -- because each writes the unit itself, and proposes bringing the formatting into one place first. It fails if no P1 connects the scattered formatting to the planned kilogram output.' \
  "$report"

# --- the fix that has to follow it ("## After the review") ---
# Both scripts are in the range, so the preparatory fix is local and made
# without asking: the unit is written in one place that both use. Neither
# script spells "%st" itself any more.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
scripts_no_longer_format() { ! grep -q '%st' total.sh delivery.sh; }
check "neither script writes the unit itself any more" scripts_no_longer_format
check_llm "the unit is formatted in one place both scripts use" \
  'The text holds lib/quantity.sh, total.sh and delivery.sh of a small project. It passes if printing a total with its unit "t" is done in one place -- a function or similar that both total.sh and delivery.sh call -- so that changing the output unit means editing that one place. It fails if each script still formats the unit itself, or if only one of them uses the shared place.' \
  "$(printf -- '--- lib/quantity.sh\n%s\n\n--- total.sh\n%s\n\n--- delivery.sh\n%s\n' \
    "$(cat lib/quantity.sh)" "$(cat total.sh)" "$(cat delivery.sh)")"

# Preparing for the change is not making it: not a byte of output moves.
check "changed none of the tests (new ones may be added)" \
  review_design_kept_existing_tests lib/quantity.test.sh total.test.sh delivery.test.sh
check "the tests still pass afterwards" ./run-tests.sh
check_eq "total.sh still prints 15.5t" "15.5t" "$(./total.sh 12.5t 3t 2>/dev/null || true)"
# The line between preparing for the kg output and building it: a fix that
# added the option would pass every check above, yet it is a behaviour the
# review was never asked for. At unit-done --kg is read as a weight and the
# total refused, and so it must still be.
check_eq "did not make the planned change itself: --kg is still refused" " (status 1)" \
  "$(review_design_total_of --kg 1t)"

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
