#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

report="$(transcript_result_text)"

check "ran textlint-docs on docs/new.md" lint_docs_ran_on 'docs/new\.md'

# --- step 4: measure, and keep the project's majority ---
check "counted サーバ in the project" lint_docs_measured 'サーバ'
check "kept サーバ in docs/new.md (the project's majority)" grep -qF 'サーバ' docs/new.md
check "did not apply サーバー (the dictionary's direction, here the minority)" \
  test "$(grep -c 'サーバー' docs/new.md)" -eq 0
check_match "reports that the dictionary runs against the project" '逆|少数派|不一致' "$report"

# --- step 5: the rest is fixed ---
check "fixed 予め to あらかじめ" grep -qF 'あらかじめ' docs/new.md
check "no 予め left" test "$(grep -c '予め' docs/new.md)" -eq 0
check_eq "touched docs/new.md only" "docs/new.md" "$(git diff --name-only eval-base)"
# Step 5.4: prh is a regex replacement, so the diff is read before reporting.
check "read git diff after fixing" test -n "$(transcript_first_command_index '^git diff')"

# --- "## このスキルの境界": no git writes ---
check_eq "committed nothing" "0" "$(git rev-list --count eval-base..HEAD)"
check_eq "no command was refused" "0" "$(transcript_denials)"

skill_eval_finish
