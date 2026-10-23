#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

doc_re='(^|/)docs/design/webhook-retry\.md$'

# --- the request itself was carried out ---
check "wrote docs/design/webhook-retry.md" test -f docs/design/webhook-retry.md
check "wrote it in Japanese" rdd_has_kana "$(cat docs/design/webhook-retry.md 2>/dev/null)"

# --- starting unasked, at the breakpoint ---
check "started review-design-doc on the doc it wrote" test "$(transcript_skill_uses review-design-doc)" -ge 1
check "started it after writing the doc" rdd_started_after_writing "$doc_re"

# --- report-only, even for its own doc ---
# What the review finds missing is a decision the notes did not make; filling
# it in would write a decision nobody made. The findings go to the user.
check "did not edit the doc after the review" rdd_untouched_after_review "$doc_re"
check "closed with the review, naming the doc" rdd_has_heading "$(rdd_report)" 'webhook-retry\.md'
# -uall: docs/design/ is new, and a bare status would show the directory.
check_eq "changed nothing but the doc" "?? docs/design/webhook-retry.md" "$(git status --porcelain -uall)"

skill_eval_finish
