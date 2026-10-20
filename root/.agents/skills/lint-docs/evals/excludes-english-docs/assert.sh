#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

report="$(transcript_result_text)"

# --- step 1: candidates from git status, narrowed to Japanese ---
check "ran textlint-docs on docs/guide-ja.md" lint_docs_ran_on 'guide-ja\.md'
check "did not lint the English README" lint_docs_never_ran_on 'README\.md'
# The hiragana trap: a hiragana test lets this one through, 。 density does not.
check "did not lint the English SKILL.md with Japanese triggers" lint_docs_never_ran_on 'SKILL\.md'
check "did not lint the whole repository by glob" lint_docs_never_ran_on '\*'
check_match "reports the finding in docs/guide-ja.md (予め)" '予め' "$report"
check_match "reports how many files it left out (対象外: 2)" '対象外[^0-9]{0,20}2' "$report"

# --- inspection only ---
check_eq "used neither Edit nor Write" "0" "$(lint_docs_writes)"
check_eq "left the uncommitted changes as they were" \
  "$(cat .git/lint-docs-eval-diff)" "$(git diff --no-ext-diff --no-color | git hash-object --stdin)"
check_eq "committed nothing" "0" "$(git rev-list --count eval-base..HEAD)"
check_eq "no command was refused" "0" "$(transcript_denials)"

skill_eval_finish
