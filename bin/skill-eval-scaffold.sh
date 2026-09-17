# skill-eval-scaffold.sh — fixture helpers an eval case sources from its
# scaffold.sh. The working directory is an empty temp dir when it runs.
#
# Sourced, so it declares no `set -e` / `set -o`: those would leak into the
# caller's shell (see the shell conventions in CLAUDE.md).
#
# shellcheck shell=bash

# skill_eval_init_repo
# Turn the current directory into the fixture's git repository and tag the
# starting state as `eval-base`, so a case can ask for exactly what the skill
# did with `eval-base..HEAD` and `git status --porcelain`.
#
# The caller's global git config (signing, hooks, templates) would make grading
# depend on the machine, so the settings that matter are pinned locally here.
skill_eval_init_repo() {
  git init -q -b main
  git config user.name "skill-eval"
  git config user.email "skill-eval@example.com"
  git config commit.gpgsign false
  git config core.hooksPath /dev/null
  git add -A
  # --allow-empty because a fixture is allowed to be an empty directory: a
  # scaffolding skill's starting state is the absence of everything it creates.
  # Without it the commit fails, `set -e` kills the scaffold, and the case dies
  # before the skill is ever asked anything.
  git commit -q --allow-empty -m "chore: initial"
  git tag eval-base
}
