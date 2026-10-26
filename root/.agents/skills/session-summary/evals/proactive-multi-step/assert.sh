#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/session-summary/evals/grading.sh"

SKILL_EVAL_JUDGE_MODEL="${SKILL_EVAL_JUDGE_MODEL:-sonnet}"

# --- the request, in the two commits it asked for ---
summary_eval_check_install_fixed
check_match "Usage shows a run on README.md" 'tally\.sh README\.md' "$(cat README.md)"
check "committed twice" test "$(git rev-list --count eval-base..HEAD)" -ge 2
# The case's premise, in prompt.md's order: a first commit that fixes Install
# and leaves Usage, so there is a midpoint to summarize at too early. A run that put
# both parts in one commit had no such point, and its timing measures nothing.
first="$(git rev-list --reverse eval-base..HEAD | head -n 1)"
check_match "the first commit fixed Install" '\./install\.sh' "$(git show "$first:README.md")"
check_not_match "and left Usage to a later one" 'tally\.sh README\.md' "$(git show "$first:README.md")"

# --- when it started: not after the first commit, once after the last ---
summary_eval_check_timing
summary_eval_check_accurate

skill_eval_finish
