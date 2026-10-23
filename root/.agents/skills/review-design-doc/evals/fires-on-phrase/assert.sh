#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

check "started review-design-doc without being named" test "$(transcript_skill_uses review-design-doc)" -ge 1
rdd_check_requested ja 'webhook-retry\.md'

skill_eval_finish
