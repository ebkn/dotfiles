#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

# --- the request itself was carried out ---
check "wrote docs/deploy.md" test -f docs/deploy.md
check "wrote it in Japanese" grep -qF '。' docs/deploy.md

# --- starting unasked ("## いつ起動するか") ---
check "started lint-docs on the document it wrote" test "$(transcript_skill_uses lint-docs)" -ge 1
check "ran textlint-docs on docs/deploy.md" lint_docs_ran_on 'docs/deploy\.md'
# At the breakpoint, once the document exists -- not before writing it.
check "started it after writing the document" lint_docs_started_after_writing '(^|/)docs/deploy\.md$'
# The whole repository is not its to fix: only the document it wrote.
check_eq "changed nothing but docs/deploy.md" "?? docs/deploy.md" "$(git status --porcelain)"

skill_eval_finish
