#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

# --- the request itself was carried out ---
check "wrote docs/deploy.md" test -f docs/deploy.md
check "wrote it in Japanese" grep -qF '。' docs/deploy.md

# --- starting unasked (not promised by the description) ---
check "started lint-docs on the document it wrote" test "$(transcript_skill_uses lint-docs)" -ge 1
check "ran textlint-docs on docs/deploy.md" lint_docs_ran_on 'docs/deploy\.md'

skill_eval_finish
