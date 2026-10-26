#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

check_eq "did not start review-design-doc for a code review" "0" "$(transcript_skill_uses review-design-doc)"
# Routing, not abstention: not starting anything would pass the line above.
check "started review-design instead" test "$(transcript_skill_uses review-design)" -ge 1

skill_eval_finish
