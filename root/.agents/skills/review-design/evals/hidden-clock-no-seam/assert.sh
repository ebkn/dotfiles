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
check_llm "a P1 or P2 finding names the clock read with no seam" \
  'The text is a design review of a change that added stamp_total, which prints a total with the current date by calling the date command inside itself. It passes if a finding ranked P1 or P2 says that stamp_total reads the clock (or the date) itself, so that no caller or test can supply the date -- in words such as a hidden input, no seam, untestable without the wall clock, or tests that must recompute today and break across midnight. It fails if this is not raised, or only at P3 or below, or only as a question.' \
  "$report"

# --- the fix that has to follow it ("## After the review") ---
# Every caller of stamp_total is inside the range, so adding the seam is local
# and done without asking -- Introduce Parameter with the clock as its default,
# or anything else that lets a caller hand in the date. How is the fixer's
# choice; that the date can now come from outside is the contract.
check_llm "the date can now be supplied from outside stamp_total" \
  'The text holds lib/quantity.sh and total.sh of a small project. It passes if stamp_total no longer depends only on reading the clock itself: a caller or a test can supply the date -- a parameter (with the current date as its default, say), a variable read at the edge, or an injected command. It fails if stamp_total still calls the date command itself with no way for a caller to provide the date instead.' \
  "$(printf -- '--- lib/quantity.sh\n%s\n\n--- total.sh\n%s\n' "$(cat lib/quantity.sh)" "$(cat total.sh)")"
# A seam changes where the date comes from, not which date is printed: run as
# it is today, the command prints what it printed before.
check_eq "today's stamped total is unchanged" "15.5t on $(date +%F)" \
  "$(./total.sh 12.5t 3t 2>/dev/null || true)"

check_eq "left the command's tests untouched" "" \
  "$(git diff --name-only unit-done -- total.test.sh)"
# The one test change SKILL.md allows: the test the seam was for may move onto
# it, asserting the same stamping with a fixed date instead of recomputing
# today. A run did exactly that; anything beyond it is not a tidying.
check_llm "the module's tests changed, if at all, only to use the seam" \
  'The text is a diff of a shell test file (it may be empty). It passes if the diff is empty, or if all it does is replace a test that compared stamp_total against the current date with one that passes a fixed date to stamp_total and expects that date in the output -- the same stamping behavior, now deterministic. It fails if any other test was changed or removed, or if an assertion was weakened or dropped rather than moved onto the fixed date.' \
  "$(git diff unit-done -- lib/quantity.test.sh)"
check "the tests still pass afterwards" ./run-tests.sh
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
