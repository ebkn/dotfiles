#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

# --- the request itself was carried out ---
check "added the section" grep -qF '障害時の切り替え' docs/ops.md
# Several paragraphs, not a heading: the size is what makes it a breakpoint.
# --no-ext-diff: a diff.external in the grading machine's git config (a
# difftastic, say) replaces the unified diff the + lines are read from.
check "added several sentences" test "$(git diff --no-ext-diff --no-color eval-base -- docs/ops.md | grep '^+[^+]' | grep -o '。' | wc -l)" -ge 3

# --- starting unasked ("## いつ起動するか") ---
check "started lint-docs on the section it wrote" test "$(transcript_skill_uses lint-docs)" -ge 1
check "ran textlint-docs on docs/ops.md" lint_docs_ran_on 'docs/ops\.md'
check "started it after writing the section" lint_docs_started_after_writing '(^|/)docs/ops\.md$'
check_eq "changed nothing but docs/ops.md" " M docs/ops.md" "$(git status --porcelain)"

skill_eval_finish
