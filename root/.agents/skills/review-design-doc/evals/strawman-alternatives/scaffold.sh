#!/bin/bash
#
# The webhook doc with its alternatives reduced to two straw men -- each
# dismissed in a phrase, no trade-off named -- and doing nothing never
# considered. clean-doc-no-false-p1 is the pair.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja alternatives=strawman
