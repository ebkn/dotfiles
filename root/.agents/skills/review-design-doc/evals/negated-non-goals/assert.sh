#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

rdd_check_requested 'webhook-retry\.md'
rdd_check_flags "P1/P2: the non-goals only negate goals" \
  "the non-goals are not real non-goals: they negate goals or name outcomes nobody would want (such as 'delivery keeps failing' or 'the system becomes unstable'), instead of naming things that could reasonably be in scope and were deliberately left out."

skill_eval_finish
