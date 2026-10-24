#!/bin/bash
#
# The webhook doc with the numbers taken out of the problem and the cost:
# failures are "very many", most are "probably" transient, the extra database
# load is "small enough". The summary loses its figures with them, since it
# would otherwise carry the evidence the context no longer has. The goals keep
# their measurable target. clean-doc-no-false-p1 is the pair.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja summary=vague context=vague risks=vague
