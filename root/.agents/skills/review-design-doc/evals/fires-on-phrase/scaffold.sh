#!/bin/bash
#
# strawman-alternatives' doc. The case grades whether the skill starts and
# stays read-only, not what it finds -- strawman-alternatives grades that.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja alternatives=strawman
