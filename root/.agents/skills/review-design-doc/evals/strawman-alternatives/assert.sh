#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

rdd_check_requested 'webhook-retry\.md'
rdd_check_flags "P1/P2: the alternatives are straw men" \
  "the alternatives considered are not real alternatives: each option is dismissed in a phrase (such as 'too big' or 'not realistic') without the trade-off that rules it out, or doing nothing / keeping the current behaviour is not considered at all."

skill_eval_finish
