#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/grading.sh"

commits="$(pr_eval_commit_indexes)"
first_commit="$(head -n 1 <<<"$commits")"
last_commit="$(tail -n 1 <<<"$commits")"
first_create="$(transcript_first_command_index "$PR_EVAL_GH_CREATE")"

# --- the request itself was carried out ---
check_match "README now installs with ./install.sh" '\./install\.sh' "$(cat README.md)"
check_not_match "and no longer with make install" 'make install' "$(cat README.md)"
check_match "CONTRIBUTING.md asks for Conventional Commits" '[Cc]onventional [Cc]ommits' \
  "$(cat CONTRIBUTING.md 2>/dev/null || true)"
check "committed each request on its own (two commits or more)" \
  test "$(git rev-list --count eval-base..HEAD)" -ge 2
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"
check_eq "stayed on the branch it was given" "docs/install-and-contributing" \
  "$(git rev-parse --abbrev-ref HEAD)"

# --- the draft at the first commit ---
# A PR opened once everything is done is the behaviour this replaces: the work
# in progress was invisible until the end, and the run asked first.
check "opened the PR after the first commit and before the last" \
  pr_eval_between "$first_create" "$first_commit" "$last_commit"
check_eq "opened it as a draft" "true" "$(pr_eval_field .createdAsDraft)"
check "through create-pr" test -n "$(pr_eval_skill_index create-pr)"

# --- update-pr before reporting back ---
# shellcheck disable=SC2329  # called by name through check
updated_after_the_last_commit() {
  pr_eval_after "$(pr_eval_skill_last_index update-pr)" "$last_commit"
}
check "ran update-pr after the last commit" updated_after_the_last_commit
check "pushed every commit" pr_eval_pushed_head
# The body is rewritten for the whole branch, not left as the first commit's.
check_match "the PR body covers the second request too" 'CONTRIBUTING' "$(pr_eval_field .body)"
check_match "the PR title is a Conventional Commit" '^[a-z]+(\([^)]+\))?!?: .+' "$(pr_eval_field .title)"
check_eq "marked it ready once the work was done" "false" "$(pr_eval_field .isDraft)"

pr_eval_check_no_question

skill_eval_finish
