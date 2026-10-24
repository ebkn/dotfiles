#!/bin/bash
#
# The webhook doc counting on another team to enlarge the shared database,
# without a word on whether that team agreed or was even asked (Squarespace's
# "do the owners know?"). A reviewer reading only the doc cannot know the
# answer, which is the point: the finding is a question for the author, not a
# claim that the team refused. clean-doc-no-false-p1 is the pair.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja dependencies=unconfirmed
