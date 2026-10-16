#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../../../create-pr/evals/grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/grading.sh"

# --- the hand-over ---
check "started update-pr" test -n "$(pr_eval_skill_index update-pr)"
check "handed over to create-pr after it" \
  pr_eval_after "$(pr_eval_skill_index create-pr)" "$(pr_eval_skill_index update-pr)"

# --- and the work published ---
check "pushed every commit" pr_eval_pushed_head
check_eq "opened the PR ready, since the work is finished" "false false" \
  "$(pr_eval_field '"\(.isDraft) \(.createdAsDraft)"')"
check_match "the PR title is a Conventional Commit" '^[a-z]+(\([^)]+\))?!?: .+' "$(pr_eval_field .title)"
check_eq "left the branch's commits as they were" "$(git rev-parse run-start)" "$(git rev-parse HEAD)"

pr_eval_check_no_question

skill_eval_finish
