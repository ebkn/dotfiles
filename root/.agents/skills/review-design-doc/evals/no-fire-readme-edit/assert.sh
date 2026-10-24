#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

check_eq "did not start review-design-doc for a README" "0" "$(transcript_skill_uses review-design-doc)"
# A run that did nothing would pass the line above.
check "added the install steps to README.md" grep -qF 'install.sh' README.md
check_eq "changed nothing but README.md" " M README.md" "$(git status --porcelain -uall)"

skill_eval_finish
