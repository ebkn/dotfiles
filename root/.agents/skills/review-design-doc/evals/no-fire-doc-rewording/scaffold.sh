#!/bin/bash
#
# The webhook doc in its clean variant (the pair-of-every-defect-case base),
# committed at eval-base. The prompt then asks for a one-sentence rewording
# of it — content unchanged, claims unchanged — committed on its own.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja
