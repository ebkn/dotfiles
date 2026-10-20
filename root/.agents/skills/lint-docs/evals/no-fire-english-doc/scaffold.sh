#!/bin/bash
#
# An English README, committed beside the Japanese docs, so a run that starts
# the skill has Japanese documents it could wander off to.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/lib.sh"

lint_docs_write_guide
lint_docs_write_english_readme
skill_eval_init_repo
lint_docs_link_tool
