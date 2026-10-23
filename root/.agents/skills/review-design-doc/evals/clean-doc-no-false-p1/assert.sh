#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

rdd_check_requested 'webhook-retry\.md'
# P1 only. A good doc can still earn a P2, and which P2 is a matter a
# deterministic check cannot settle; a P1 on this doc is a false alarm.
check_eq "raised no P1" "0" "$(rdd_count "$(rdd_report)" P1)"

skill_eval_finish
