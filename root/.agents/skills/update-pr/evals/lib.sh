# lib.sh — update-pr's fixture: create-pr's (see its evals/lib.sh), one
# step further on. A branch whose first commit is pushed and already has a
# draft PR, as create-pr leaves it at a unit's first commit.
#
# Sourced by scaffold.sh, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# shellcheck source=../../create-pr/evals/lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/lib.sh"

# update_pr_eval_branch
# docs/contributing, one commit ahead of main, not pushed and with no PR.
# Tagged `run-start`: eval-base is main's commit, and a case asking what the
# run itself committed counts from here.
update_pr_eval_branch() {
  pr_eval_scaffold docs/contributing
  cat >CONTRIBUTING.md <<'EOF'
# Contributing

## Commit messages

Write them as Conventional Commits (`type(scope): subject`).
EOF
  git add CONTRIBUTING.md
  git commit -q -m "docs: add CONTRIBUTING with the commit message rule"
  git tag run-start
}

# update_pr_eval_scaffold
# That branch pushed, with an open draft PR describing its commit.
update_pr_eval_scaffold() {
  update_pr_eval_branch
  skill_eval_fake_pr "docs: add CONTRIBUTING" "$(
    cat <<'EOF'
## Summary

Start a CONTRIBUTING guide, so contributors know the conventions before their first PR.

## Changes

- CONTRIBUTING.md: the commit message rule (Conventional Commits).
EOF
  )" true
}
