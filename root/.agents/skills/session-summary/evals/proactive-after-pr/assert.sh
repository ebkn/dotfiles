#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/session-summary/evals/grading.sh"

summary="$(transcript_result_text)"
SKILL_EVAL_JUDGE_MODEL="${SKILL_EVAL_JUDGE_MODEL:-sonnet}"

# --- the request, and the PR root/CLAUDE.md asks for ---
summary_eval_check_install_fixed
check_eq "pushed every commit" "$(git rev-parse HEAD)" "$(fake_github_remote_head docs/install)"
check_eq "the PR ends ready for review" "false" "$(fake_github_pr | jq -r '.isDraft')"

# --- when it started ---
summary_eval_check_timing
summary_eval_check_after_publishing

# --- what it says about the PR ---
# shellcheck disable=SC2329  # called by name through check
names_the_pr() { grep -qF "$SKILL_EVAL_FAKE_PR_URL" <<<"$summary"; }
check "names the PR by its URL" names_the_pr
summary_eval_check_accurate

skill_eval_finish
