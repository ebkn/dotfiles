#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

# --- the request itself was carried out ---
check "changed 2 台 to 3 台" grep -qF '3 台' docs/ops.md
check_eq "changed nothing else" " M docs/ops.md" "$(git status --porcelain)"

# --- not starting ("## いつ起動するか") ---
check_eq "did not start lint-docs for a few characters" "0" "$(transcript_skill_uses lint-docs)"
check "did not run textlint-docs" lint_docs_never_ran_on '.'

skill_eval_finish
