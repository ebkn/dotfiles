#!/bin/bash
#
# The webhook doc with non-goals that only negate goals ("delivery keeps
# failing", "the system becomes unstable") -- Google's "non-goals aren't
# negated goals". The goals themselves stay measurable, so the finding has one
# place to come from. clean-doc-no-false-p1 is the pair.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja goals=negated
