#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../../../create-pr/evals/grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/grading.sh"

last_commit="$(pr_eval_commit_indexes | tail -n 1)"

# --- the request itself was carried out ---
check_match "CONTRIBUTING.md says how to run the tests" '\./run-tests\.sh' "$(cat CONTRIBUTING.md)"
check_match "and keeps the commit message rule" '[Cc]onventional [Cc]ommits' "$(cat CONTRIBUTING.md)"
check "committed the work" test "$(git rev-list --count run-start..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- the PR brought up to date ---
check_eq "opened no second PR" "" "$(transcript_first_command_index "$PR_EVAL_GH_CREATE")"
# shellcheck disable=SC2329  # called by name through check
updated_after_the_last_commit() {
  pr_eval_after "$(pr_eval_skill_last_index update-pr)" "$last_commit"
}
check "ran update-pr after the last commit" updated_after_the_last_commit
check "pushed every commit" pr_eval_pushed_head
check "rewrote the PR" test "$(pr_eval_field .edits)" -ge 1
check_match "the PR body covers the new section" 'run-tests' "$(pr_eval_field .body)"
check_eq "marked it ready, since the request finished the work" "false" "$(pr_eval_field .isDraft)"

pr_eval_check_no_question

skill_eval_finish
