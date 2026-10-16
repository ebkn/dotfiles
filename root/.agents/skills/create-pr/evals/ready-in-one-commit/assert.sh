#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/grading.sh"

first_commit="$(pr_eval_commit_indexes | head -n 1)"
first_create="$(transcript_first_command_index "$PR_EVAL_GH_CREATE")"

# --- the request itself was carried out ---
check_match "README now installs with ./install.sh" '\./install\.sh' "$(cat README.md)"
check_not_match "and no longer with make install" 'make install' "$(cat README.md)"
check "committed the work" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"
check_eq "stayed on the branch it was given" "docs/install" "$(git rev-parse --abbrev-ref HEAD)"

# --- the PR ---
check "opened the PR after committing" pr_eval_after "$first_create" "$first_commit"
check "through create-pr" pr_eval_opened_through_create_pr
check "pushed every commit" pr_eval_pushed_head
check_match "the PR title is a Conventional Commit" '^[a-z]+(\([^)]+\))?!?: .+' "$(pr_eval_field .title)"
check_eq "the PR ends ready for review" "false" "$(pr_eval_field .isDraft)"

pr_eval_check_no_question

skill_eval_finish
