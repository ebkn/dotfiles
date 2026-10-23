#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

report="$(rdd_report)"

rdd_check_requested 'webhook-retry\.md'
check_eq "raised no P1" "0" "$(rdd_count "$report" P1)"
check "wrote no Japanese into an English review" rdd_has_no_kana "$report"

skill_eval_finish
