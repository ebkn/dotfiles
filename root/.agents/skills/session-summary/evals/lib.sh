# lib.sh — the fixture session-summary's eval cases share.
#
# A small command, `tally`, with a stale README (it names a Makefile that is
# gone). The proactive cases ask for a documentation change: with
# root/CLAUDE.md in, a change to tests or to an interface also starts
# review-test and review-design, which the fixture does not carry and which
# would spend the run on something these cases do not measure.
#
# No case gives the fixture an `origin`: root/CLAUDE.md then opens no PR and
# the commits are reported as local, so no fake GitHub is needed.
#
# Sourced by scaffold.sh, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# shellcheck source=../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"

# summary_eval_project
# The project on main, committed and tagged eval-base.
summary_eval_project() {
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
  chmod +x install.sh tally.sh
  skill_eval_init_repo
}

# summary_eval_finished_branch
# feat/json-output, finished: the requested --json flag, its test, and a fix
# nobody asked for (a usage error with no arguments, where wc used to wait on
# stdin). Then main moves on with a CHANGELOG.md the branch never saw: a
# two-dot diff against main would list it as removed by this branch.
# Tagged `run-start`, so a case can tell whether the run committed anything,
# and its refs recorded in .git/refs-at-start.
summary_eval_finished_branch() {
  summary_eval_project
  git checkout -q -b feat/json-output

  cat >tally.sh <<'EOF'
#!/bin/bash
# Prints the line count of each file, then the total.
# --json prints {"files":[{"path":...,"lines":N}],"total":N} instead, for
# other tools to read.
set -eo pipefail
json=false
if [ "${1:-}" = "--json" ]; then
  json=true
  shift
fi
if [ "$json" = true ]; then
  total=0
  sep=""
  printf '{"files":['
  for f in "$@"; do
    n=$(wc -l <"$f" | tr -d ' ')
    total=$((total + n))
    p=$(printf '%s' "$f" | sed 's/[\\"]/\\&/g')
    printf '%s{"path":"%s","lines":%s}' "$sep" "$p" "$n"
    sep=","
  done
  printf '],"total":%s}\n' "$total"
else
  wc -l "$@"
fi
EOF
  git commit -qam "feat(tally): add --json output for other tools to read" \
    -m "The flag is --json, not --format=json: no other format is planned."

  cat >run-tests.sh <<'EOF'
#!/bin/bash
set -eo pipefail
printf 'a\nb\n' >tmp-two-lines
out="$(./tally.sh --json tmp-two-lines)"
rm -f tmp-two-lines
[ "$out" = '{"files":[{"path":"tmp-two-lines","lines":2}],"total":2}' ] || {
  echo "FAIL: $out" >&2
  exit 1
}
echo ok
EOF
  chmod +x run-tests.sh
  git add run-tests.sh
  git commit -qm "test(tally): pin the --json output"

  # Inserted after the flag is consumed, so `--json` alone is a usage error
  # too: a fixture a careful reader can fault puts that fault in the report.
  # awk, because BSD sed takes no \n in a replacement.
  awk '{ print } /^fi$/ && !done { print "[ $# -gt 0 ] || { echo \"usage: tally.sh [--json] FILE...\" >&2; exit 2; }"; done = 1 }' \
    tally.sh >tally.tmp
  mv tally.tmp tally.sh
  chmod +x tally.sh
  git commit -qam "fix(tally): exit with usage when no file is given" \
    -m "Not part of the request: noticed while adding --json. With no file, wc read stdin and the command hung."

  git checkout -q main
  printf '# Changelog\n\n- 0.1.0: first release\n' >CHANGELOG.md
  git add CHANGELOG.md
  git commit -qm "docs: start a CHANGELOG"
  git checkout -q feat/json-output
  git tag run-start
  # Every branch and tag with its commit, for a grader to compare after the
  # run. Inside .git/, so the fixture's tree and status never show it.
  git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags >.git/refs-at-start
}

# summary_eval_docs_branch
# A fresh branch for the proactive cases' README fix.
summary_eval_docs_branch() {
  summary_eval_project
  git checkout -q -b docs/install
}
