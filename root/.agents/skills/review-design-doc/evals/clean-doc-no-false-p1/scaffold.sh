#!/bin/bash
#
# The webhook doc with every section in its base variant: the pair of every
# defect case, each of which differs from it in one planted defect. A review that
# always finds a P1 would pass every defect case; this is what tells it apart.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja
