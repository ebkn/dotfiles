#!/bin/bash
#
# The webhook doc with three decisions left open inside the proposal -- the
# retry interval "TBD", whether to retry 4xx, whether to copy the payload --
# while its open-questions section says there are none. The doc reads more
# settled than it is. clean-doc-no-false-p1 is the pair.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja proposal=hedged open=none
