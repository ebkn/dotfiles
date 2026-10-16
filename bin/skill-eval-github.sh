# skill-eval-github.sh — a GitHub that exists only inside an eval fixture.
#
# create-pr and update-pr push a branch and call `gh pr`. Against the real
# GitHub an eval run would open a PR on someone's repository per run, and a
# grader could read back only what the API happens to show. Here `origin` is a
# bare repository inside the fixture's .git/, and `gh` is a stub that keeps one
# PR per branch as a JSON file, so a case reads exactly what was pushed, what
# the PR says, and whether it is a draft.
#
# The stub decides as little as possible (see "Stubbing a toolchain" in
# bin/skill-eval.md), but refuses what the real gh refuses where a skill's
# flow depends on it: a PR for a branch nobody pushed, a second PR for the same
# branch, a PR from the default branch, and viewing, editing or readying a PR
# that does not exist. A subcommand it does not know fails loudly instead of
# exiting 0, so a run cannot believe a call worked that nothing carried out.
#
# Sourced by a scaffold.sh (after skill_eval_init_repo) and by an assert.sh.
# Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

SKILL_EVAL_FAKE_ORIGIN=.git/fake-origin.git
SKILL_EVAL_FAKE_ORIGIN_URL=git@github.com:example/fixture.git
# The URL the stub prints for every PR; for a grader or test comparing to it.
# shellcheck disable=SC2034
SKILL_EVAL_FAKE_PR_URL=https://github.com/example/fixture/pull/1

# skill_eval_fake_github
# Give the fixture an `origin` holding main, with origin/HEAD set as a clone's
# is (create-pr reads the default branch from it), and put the gh stub in
# bin/. The bare repository sits inside .git/, where git status never looks.
#
# The remote's URL is a GitHub one, because root/CLAUDE.md opens a PR only
# with a GitHub origin: a local path as the URL, which `git remote -v` shows
# even through url.insteadOf, made a run conclude there was no GitHub and
# publish nothing -- correctly. git reaches it over SSH, so core.sshCommand
# points at a stub that serves the bare repository instead of dialling out.
skill_eval_fake_github() {
  local origin="$PWD/$SKILL_EVAL_FAKE_ORIGIN"
  git init -q --bare -b main "$SKILL_EVAL_FAKE_ORIGIN"
  mkdir -p bin/gh-state
  cat >bin/ssh <<SSH_STUB
#!/bin/bash
# The ssh git runs for the fixture's origin; see bin/skill-eval-github.sh in
# dotfiles. The last argument is the remote command, such as
# git-receive-pack 'example/fixture.git'; it is run against the bare
# repository instead.
set -eo pipefail
remote_command="\${*: -1}"
case "\$remote_command" in
  git-receive-pack* | git-upload-pack*) exec "\${remote_command%% *}" "$origin" ;;
  *) echo "ssh (eval stub): refusing: \$remote_command" >&2 && exit 1 ;;
esac
SSH_STUB
  chmod +x bin/ssh
  git config core.sshCommand "$PWD/bin/ssh"
  git remote add origin "$SKILL_EVAL_FAKE_ORIGIN_URL"
  git push -q -u origin main
  git remote set-head origin main >/dev/null
  cat >bin/gh <<'GH_STUB'
#!/bin/bash
# The gh of an eval fixture; see bin/skill-eval-github.sh in dotfiles.
set -eo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
{
  printf 'gh'
  printf ' %q' "$@"
  printf '\n'
} >>"$here/gh-calls.log"

url=https://github.com/example/fixture/pull/1
branch="$(git rev-parse --abbrev-ref HEAD)"
pr="$here/gh-state/${branch//\//_}.json"

# Flags shared by the subcommands below; positional arguments (a PR number or
# URL) are accepted and ignored, since a fixture has one PR per branch.
# `--flag=value` is split as gh's own parser does. A flag the stub does not
# know fails, as an unknown subcommand does: ignored, `--title=x` or `--fill`
# would open a PR with an empty title and fail a correct run on its content.
title= body= body_set=0 draft=false json= jq_filter= undo=0 head= state=open
parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --*=*) set -- "${1%%=*}" "${1#*=}" "${@:2}" ;;
    esac
    case "$1" in
      -t | --title) title="$2" && shift ;;
      -b | --body) body="$2" && body_set=1 && shift ;;
      -F | --body-file)
        if [ "$2" = - ]; then body="$(cat)"; else body="$(cat "$2")"; fi
        body_set=1 && shift
        ;;
      -d | --draft) draft=true ;;
      --json) json="$2" && shift ;;
      -q | --jq) jq_filter="$2" && shift ;;
      --undo) undo=1 ;;
      -H | --head) head="$2" && shift ;;
      -s | --state) state="$2" && shift ;;
      -B | --base | -R | --repo | -a | --assignee | -l | --label | -r | --reviewer | -L | --limit) shift ;;
      -*)
        printf 'gh (eval stub): flag %s is not stubbed\n' "$1" >&2
        exit 1
        ;;
      *) ;;
    esac
    shift
  done
}
# Print JSON as gh does: through --jq when given, as-is otherwise.
emit() {
  if [ -n "$jq_filter" ]; then jq -r "$jq_filter"; else cat; fi
}
no_pr() {
  printf 'no pull requests found for branch "%s"\n' "$branch" >&2
  exit 1
}

case "${1:-} ${2:-}" in
  "repo view")
    shift 2
    parse "$@"
    printf '{"name":"fixture","nameWithOwner":"example/fixture","url":"https://github.com/example/fixture","defaultBranchRef":{"name":"main"}}\n' | emit
    ;;
  "pr create")
    shift 2
    parse "$@"
    if [ "$branch" = main ]; then
      echo 'pull request create failed: head branch "main" is the same as base branch "main"' >&2
      exit 1
    fi
    if ! git ls-remote --exit-code origin "refs/heads/$branch" >/dev/null 2>&1; then
      printf 'aborted: you must first push the current branch to a remote, or use the --head flag\n' >&2
      exit 1
    fi
    if [ -f "$pr" ]; then
      printf 'a pull request for branch "%s" into branch "main" already exists:\n%s\n' "$branch" "$url" >&2
      exit 1
    fi
    jq -n --arg title "$title" --arg body "$body" --argjson draft "$draft" \
      --arg branch "$branch" --arg url "$url" '
      { number: 1, url: $url, title: $title, body: $body, state: "OPEN",
        isDraft: $draft, createdAsDraft: $draft, edits: 0, readied: 0,
        baseRefName: "main", headRefName: $branch }' >"$pr"
    echo "$url"
    ;;
  "pr view")
    shift 2
    parse "$@"
    [ -f "$pr" ] || no_pr
    if [ -n "$json" ]; then
      emit <"$pr"
    else
      jq -r '"title:\t\(.title)\nstate:\t\(.state)\ndraft:\t\(.isDraft)\nurl:\t\(.url)\n--\n\(.body)"' "$pr"
    fi
    ;;
  "pr list")
    shift 2
    parse "$@"
    # Every PR is open, so --state closed or merged lists none.
    all="$(cat "$here"/gh-state/*.json 2>/dev/null | jq -s --arg head "$head" --arg state "$state" '
      [ .[] | select(($head == "" or .headRefName == $head) and ($state == "open" or $state == "all")) ]')"
    if [ -n "$json" ]; then
      emit <<<"$all"
    else
      jq -r '.[] | "\(.number)\t\(.title)\t\(.headRefName)\t\(if .isDraft then "DRAFT" else "OPEN" end)"' <<<"$all"
    fi
    ;;
  "pr edit")
    shift 2
    parse "$@"
    [ -f "$pr" ] || no_pr
    jq --arg title "$title" --arg body "$body" --argjson body_set "$body_set" '
      (if $title != "" then .title = $title else . end)
      | (if $body_set == 1 then .body = $body else . end)
      | .edits += 1' "$pr" >"$pr.new"
    mv "$pr.new" "$pr"
    echo "$url"
    ;;
  "pr ready")
    shift 2
    parse "$@"
    [ -f "$pr" ] || no_pr
    if [ "$undo" -eq 1 ]; then
      jq '.isDraft = true' "$pr" >"$pr.new"
    else
      jq '.isDraft = false | .readied += 1' "$pr" >"$pr.new"
    fi
    mv "$pr.new" "$pr"
    echo "✓ Pull request example/fixture#1 is marked as \"ready for review\""
    ;;
  *)
    printf 'gh (eval stub): `gh %s` is not stubbed\n' "$*" >&2
    exit 1
    ;;
esac
GH_STUB
  chmod +x bin/gh
}

# skill_eval_fake_pr <title> <body> <draft: true|false>
# A PR already open for the current branch, as if create-pr had run in an
# earlier session. The branch is pushed first, since a PR needs it there.
# Opened through the stub's own `pr create`, so the record has one shape,
# defined there; the call is the scaffold's, not the run's, so the log that
# fake_github_calls reads starts empty again.
skill_eval_fake_pr() {
  local draft=()
  [ "$3" = true ] && draft=(--draft)
  git push -q -u origin HEAD
  bin/gh pr create ${draft[@]+"${draft[@]}"} --title "$1" --body "$2" >/dev/null
  : >bin/gh-calls.log
}

# fake_github_pr [<branch>]
# The PR of that branch (default: the current one) as JSON; empty when there
# is none.
fake_github_pr() {
  local branch="${1:-$(git rev-parse --abbrev-ref HEAD)}"
  local file="bin/gh-state/${branch//\//_}.json"
  [ -f "$file" ] || return 0
  cat "$file"
}

# fake_github_remote_head <branch>
# The commit origin holds for that branch; empty when it was never pushed.
fake_github_remote_head() {
  git --git-dir="$SKILL_EVAL_FAKE_ORIGIN" rev-parse --verify -q "refs/heads/$1" || true
}

# fake_github_remote_refs
# Every branch origin holds, as "<branch> <commit>" lines in name order. For a
# case asking that nothing was pushed anywhere: `git push origin main:other`
# leaves origin's main as it was.
fake_github_remote_refs() {
  git --git-dir="$SKILL_EVAL_FAKE_ORIGIN" for-each-ref --format='%(refname:short) %(objectname)' refs/heads
}

# fake_github_calls
# Every gh call of the run, one per line, shell-quoted.
fake_github_calls() {
  [ -f bin/gh-calls.log ] || return 0
  cat bin/gh-calls.log
}
