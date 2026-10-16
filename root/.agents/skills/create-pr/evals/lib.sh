# lib.sh — the fixture create-pr's and update-pr's eval cases share.
#
# A small command, `tally`, whose README is out of date: the requests the
# cases make are documentation changes. Deliberately: with root/CLAUDE.md in,
# a change to tests or to an interface also starts review-test and
# review-design, which the fixture does not carry and which would spend the
# run on something these cases do not measure. A doc change starts neither
# (both skip "a small fix that changes no interface").
#
# The PR cases live in two skills, so update-pr's scaffolds source this file
# from create-pr's evals/ through $SKILL_EVAL_REPO_ROOT.
#
# Sourced by scaffold.sh, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# pr_eval_write_project
# The project at the state every case starts from, uncommitted.
pr_eval_write_project() {
  cat >README.md <<'EOF'
# tally

Counts the lines of the files it is given.

## Install

```sh
make install
```

## Usage

```sh
./tally.sh FILE...
```
EOF
  cat >install.sh <<'EOF'
#!/bin/bash
# Installs tally.sh into ~/.local/bin. Replaced the Makefile, which is gone.
set -eo pipefail
mkdir -p "$HOME/.local/bin"
cp tally.sh "$HOME/.local/bin/tally"
EOF
  cat >tally.sh <<'EOF'
#!/bin/bash
# Prints the line count of each file, then the total.
set -eo pipefail
wc -l "$@"
EOF
  # update-pr's request documents this script; a CONTRIBUTING.md pointing at
  # a file that does not exist is a question a careful run would stop to ask.
  cat >run-tests.sh <<'EOF'
#!/bin/bash
# tally.sh names the file it counted.
set -eo pipefail
out="$(./tally.sh README.md)"
case "$out" in
  *README.md*) echo ok ;;
  *) echo "FAIL: $out" >&2 && exit 1 ;;
esac
EOF
  chmod +x install.sh tally.sh run-tests.sh
}

# pr_eval_scaffold <branch>
# The project committed on main, main pushed to the fake origin, and the
# working tree switched to <branch> -- or left on main when <branch> is main.
pr_eval_scaffold() {
  # shellcheck source=../../../../../bin/skill-eval-scaffold.sh
  source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
  # shellcheck source=../../../../../bin/skill-eval-github.sh
  source "$SKILL_EVAL_LIB_DIR/skill-eval-github.sh"
  pr_eval_write_project
  skill_eval_init_repo
  skill_eval_fake_github
  if [ "$1" != main ]; then
    git switch -q -c "$1"
  fi
}
