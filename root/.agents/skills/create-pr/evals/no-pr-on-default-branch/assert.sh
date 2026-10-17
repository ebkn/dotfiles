#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../../../../../../bin/skill-eval-github.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/grading.sh"

# --- the request itself was carried out ---
check_match "README now installs with ./install.sh" '\./install\.sh' "$(cat README.md)"
check "committed the work" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- and went no further ---
check_eq "stayed on main" "main" "$(git rev-parse --abbrev-ref HEAD)"
check_eq "created no branch to open a PR from" "main" "$(git for-each-ref --format='%(refname:short)' refs/heads)"
# Every branch on origin, not just main: `git push origin main:docs/x` leaves
# origin's main as the scaffold pushed it.
check_eq "pushed nothing" "main $(git rev-parse eval-base)" "$(fake_github_remote_refs)"
check_eq "never ran gh pr create" "" "$(transcript_first_command_index "$PR_EVAL_GH_CREATE")"
check_eq "started neither PR skill" "0 0" \
  "$(transcript_skill_uses create-pr) $(transcript_skill_uses update-pr)"

pr_eval_check_nothing_left

skill_eval_finish
