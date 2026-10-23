#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

rdd_check_requested 'webhook-retry\.md'
rdd_check_flags "P1/P2: the doc records no decision" \
  "the document records no design decision as a whole: it is a list of implementation steps and code with no problem statement, no alternatives and no trade-offs, so it reads as an implementation manual rather than a design doc. A list of individually missing sections does not count unless one finding names this as a whole."

skill_eval_finish
