#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

report="$(transcript_result_text)"

check "ran textlint-docs on docs/guide.md" lint_docs_ran_on 'docs/guide\.md'

# --- one finding per category (lib.sh lists the line of each) ---
check_match "表記ゆれ: サーバ (line 3)" 'サーバ' "$report"
check_match "直訳新造語: 単一の真実のソース (line 5)" '単一の真実のソース|Source of Truth' "$report"
check_match "過剰な漢語化: 再試行 (line 7)" '再試行' "$report"
check_match "ひらき: 予め (line 9)" '予め' "$report"
check_match "誇張: 大幅に / 完全に (line 11)" '大幅に|完全に' "$report"
check_match "英語式コロン: 次を実行する: (line 13)" '次を実行する|コロン' "$report"
check_match "装飾絵文字: ✅ (line 15)" '✅|絵文字' "$report"
# Reported by the local ja-no-redundant-phrase. Before it existed no rule
# caught this, and 0 of 4 runs started by name reported it.
check_match "冗長表現: ことができる (line 18)" 'ことができる' "$report"

# --- step 4: a section B finding is measured before it is adopted ---
check "counted サーバ across the project" lint_docs_measured 'サーバ'
check "reports the count behind the サーバ finding" lint_docs_reports_count "$report"

# --- "## このスキルの境界": inspection only ---
check_eq "used neither Edit nor Write" "0" "$(lint_docs_writes)"
check_eq "left the tree as it was" "" "$(git status --porcelain)"
check_eq "committed nothing" "0" "$(git rev-list --count eval-base..HEAD)"

# Every command the procedure needs should sit inside allowed-tools: a refusal
# here is a prompt the user would have to answer.
check_eq "no command was refused" "0" "$(transcript_denials)"

skill_eval_finish
