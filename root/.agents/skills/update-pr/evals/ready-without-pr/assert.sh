#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../../../create-pr/evals/grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/grading.sh"

# --- the hand-over ---
# The prompt is `/update-pr ready`, which a `claude -p` run expands in place:
# no Skill call marks where update-pr starts (all three first runs showed
# none). Its own step 2, `gh pr view`, finding no PR is the point the hand-over
# follows.
first_view="$(transcript_first_command_index "$PR_EVAL_GH_VIEW")"
check "update-pr looked for the PR" test -n "$first_view"
check "handed over to create-pr after finding none" \
  pr_eval_after "$(pr_eval_skill_index create-pr)" "$first_view"
check "through create-pr" pr_eval_opened_through_create_pr

# --- and the work published ---
check "pushed every commit" pr_eval_pushed_head
check_eq "opened the PR ready, since the work is finished" "false false" \
  "$(pr_eval_field '"\(.isDraft) \(.createdAsDraft)"')"
check_match "the PR title is a Conventional Commit" '^[a-z]+(\([^)]+\))?!?: .+' "$(pr_eval_field .title)"
check_eq "left the branch's commits as they were" "$(git rev-parse run-start)" "$(git rev-parse HEAD)"
# The PR and push checks read the current branch, so a run that opened its PR
# from a new branch would pass them; the scaffold's branch is the one to publish.
check_eq "stayed on the branch it was given" "docs/contributing" "$(git rev-parse --abbrev-ref HEAD)"

pr_eval_check_nothing_left

skill_eval_finish
