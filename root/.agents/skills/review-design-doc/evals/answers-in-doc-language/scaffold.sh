#!/bin/bash
#
# The fixture of missing-rollback, unchanged: the pair differs only in the
# request's language.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/missing-rollback/scaffold.sh"
