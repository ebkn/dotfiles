#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../../../create-pr/evals/grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/grading.sh"

# --- the question was answered ---
check_match "answered with the command the README gives" '\./tally\.sh' "$(transcript_result_text)"

# --- and nothing was published ---
check_eq "committed nothing" "0" "$(git rev-list --count run-start..HEAD)"
check_eq "started neither PR skill" "0 0" \
  "$(transcript_skill_uses update-pr) $(transcript_skill_uses create-pr)"
check_eq "left the PR as it was" "0 0 true" \
  "$(pr_eval_field '"\(.edits) \(.readied) \(.isDraft)"')"
check_eq "pushed nothing" "$(git rev-parse run-start)" "$(fake_github_remote_head docs/contributing)"

pr_eval_check_no_question

skill_eval_finish
