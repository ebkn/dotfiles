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
check_llm "a P1 or P2 finding names the ticket layer as shallow" \
  'The text is a design review of a change that added lib/ticket.sh, whose functions ticket_weight and ticket_total only call parse_quantity and sum_quantities with the same arguments. It passes if a finding ranked P1 or P2 says that this layer (or those functions) only forwards to quantity.sh and hides nothing -- in words such as pass-through, shallow module, a wrapper or layer that adds no abstraction, or that it does not achieve the isolation the commit intended. It fails if the layer is not raised, or only at P3 or below.' \
  "$report"

# --- what has to happen instead of a fix ("### Reach") ---
# The commit says the layer is what it set out to build, so removing it is a
# crossing fix: proposed, and in a run where nobody can answer, left unapplied
# and listed as awaiting a decision.
check "left the layer in place: total.sh still goes through ticket_total" \
  grep -q '^ticket_total "\$@"$' total.sh
check "left the layer in place: lib/ticket.sh still defines ticket_total" \
  grep -q '^ticket_total()' lib/ticket.sh
check_llm "puts removing the layer to the user as a decision" \
  'The text is the review of a change that added a shallow ticket API layer, followed by what was done about it. It passes if removing (or otherwise reshaping) that layer is put to the user as a decision -- a question, a proposal awaiting their answer, or a fix explicitly left unapplied because it undoes what the commit intended. It fails if the text says the layer was removed, or never offers removing it as an option.' \
  "$(printf '%s\n\n%s\n' "$report" "$(transcript_result_text)")"
# The tempting non-fix: making the layer look deep by restating quantity.sh's
# contract in its comments, which writes the same decision down twice. The
# phrases are the deterministic first line -- words only quantity.sh's contract
# uses, copied verbatim -- and the judge catches the same rules reworded.
# `check` calls it by name, which shellcheck cannot see.
# shellcheck disable=SC2329
contract_phrases_absent() { ! grep -qiE 'trailing unit|negative|is refused' lib/ticket.sh; }
check "did not copy quantity.sh's contract phrases into the layer" contract_phrases_absent
check_llm "the layer's comments do not restate quantity.sh's contract" \
  'The text is lib/ticket.sh, a thin layer whose functions call parse_quantity and sum_quantities from quantity.sh. It passes if its comments describe the layer without restating the input rules of those functions themselves -- such as the trailing unit "t", surrounding whitespace, which inputs are refused (empty, not a number, negative), or the exit status and output of a refusal. Pointing to parse_quantity or sum_quantities for those details is fine. It fails if the comments state any of those rules in their own words.' \
  "$(cat lib/ticket.sh)"

# Whatever else was done leaves behaviour alone and is committed on its own.
check_eq "left the tests untouched" "" \
  "$(git diff --name-only unit-done -- lib/quantity.test.sh total.test.sh)"
check "the tests still pass afterwards" ./run-tests.sh
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
