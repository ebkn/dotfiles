#!/bin/bash
#
# detects-each-category's fixture: a Japanese doc with findings, committed.
# Whether the skill starts is the measurement; what it reports is graded only
# as far as showing it really ran.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/lib.sh"

lint_docs_write_guide
skill_eval_init_repo
lint_docs_link_tool
