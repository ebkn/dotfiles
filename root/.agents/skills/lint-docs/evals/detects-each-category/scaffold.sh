#!/bin/bash
#
# docs/guide.md with one finding per category the description promises (see
# lib.sh for the line of each), committed, so a clean tree afterwards means the
# skill wrote nothing.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/lib.sh"

lint_docs_write_guide
skill_eval_init_repo
lint_docs_link_tool
