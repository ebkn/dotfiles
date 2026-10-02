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
check_llm "a P1 or P2 finding names delivery_sum as a pass-through" \
  'The text is a design review of a change that added delivery.sh and lib/delivery.sh, where delivery_sum only calls sum_quantities with the same arguments. It passes if a finding ranked P1 or P2 says that delivery_sum only forwards to sum_quantities and adds nothing -- in words such as pass-through, a wrapper or indirection with no value, or a shallow function. It fails if delivery_sum is not raised, or only at P3 or below, or only as a question.' \
  "$report"

# --- the fix that has to follow it ("## After the review") ---
# The forwarder's one caller is inside the range and nothing asked for it, so
# the fix is local and made without asking -- and the skill's stance is to
# delete a pass-through rather than improve it.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
forwarder_gone() { ! git grep -q 'delivery_sum' -- '*.sh'; }
check "removed delivery_sum" forwarder_gone
# Within delivery_total's own body: a grep of the whole file would also match
# the forwarder it is meant to replace.
# shellcheck disable=SC2329
total_calls_sum() { sed -n '/^delivery_total()/,/^}/p' lib/delivery.sh | grep -q 'sum_quantities'; }
check "delivery_total calls sum_quantities itself" total_calls_sum

# Folding the forwarder away changes the shape of the code and nothing it does.
check_eq "left the tests untouched" "" \
  "$(git diff --name-only unit-done -- lib/quantity.test.sh total.test.sh delivery.test.sh)"
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
