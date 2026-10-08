#!/usr/bin/env zsh
# Unit tests for the worktree workflow in zsh/git.zsh: gw() and gdmerged().
#
# These two are the most destructive functions in this repo -- gdmerged deletes
# branches and removes worktrees, gw checks out other people's PRs -- and until
# now they had no coverage at all. Every case here runs against a REAL git
# repository built in a temp directory, because the contract is what git ends up
# holding (which branches exist, which worktrees are registered), and a stubbed
# git would keep passing if that changed.
#
# gh and fzf are stubbed, since neither may touch the network or block. git is
# never stubbed.
#
# The confirmation prompt is reached through _gdmerged_confirm, which exists as
# a seam: the prompt reads /dev/tty directly (deliberately -- the branch list is
# already on stdin), so a test cannot answer it by redirecting. Overriding the
# one function is the only way to exercise both answers.
#
# Run: zsh zsh/git-worktree.test.zsh   (exit 0 = pass)

set -u

# alias.zsh first, exactly as .zshrc loads it: zsh expands aliases when it
# parses a function body, so `alias mkdir='mkdir -p'` is part of what gw() is.
source "${0:A:h}/alias.zsh"
source "${0:A:h}/git.zsh"

typeset -i failures=0

# :A resolves the /var -> /private/var symlink macOS hands back from mktemp.
# Without it every path comparison below is against the wrong prefix, and gw's
# "changing directory to repository root" branch fires on every call.
work=${$(mktemp -d):A}
stub_bin="$work/bin"
mkdir -p "$stub_bin"

# gh stub. GH_PR_REPO / GH_PR_BRANCH drive the two queries gw makes; unsetting
# either stands for the query failing.
cat >"$stub_bin/gh" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "repo view") [ -n "${GH_PR_REPO:-}" ] || exit 1; printf '%s\n' "$GH_PR_REPO" ;;
  "pr view")   [ -n "${GH_PR_BRANCH:-}" ] || exit 1; printf '%s\n' "$GH_PR_BRANCH" ;;
  *) exit 1 ;;
esac
STUB

# fzf stub: FZF_PICK selects a line from stdin by substring, and also records
# everything it was offered so the tests can assert on the menu itself.
cat >"$stub_bin/fzf" <<'STUB'
#!/bin/sh
# FZF_PICK selects a line by substring; unset stands for the user cancelling.
# FZF_MENU, when set, keeps a copy of everything the picker was offered.
# --accept-nth is honoured because gw depends on it: the menu carries the
# absolute path in a hidden column, and returning the whole line instead would
# hand cd three tab-separated fields.
tee "${FZF_MENU:-/dev/null}" > "$0.stdin"
[ -n "${FZF_PICK:-}" ] || exit 1
nth=
for arg in "$@"; do
  case "$arg" in --accept-nth=*) nth="${arg#--accept-nth=}" ;; esac
done
line=$(grep -F -- "$FZF_PICK" "$0.stdin") || exit 1
if [ -n "$nth" ]; then
  printf '%s\n' "$line" | awk -F'\t' -v n="$nth" '{print $n}'
else
  printf '%s\n' "$line"
fi
STUB

chmod +x "$stub_bin/gh" "$stub_bin/fzf"

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

contains() {
  local desc="$1" needle="$2" hay="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want to contain: %s\n  got : %s\n' "$desc" "$needle" "$hay"
    (( failures++ ))
  fi
}

lacks() {
  local desc="$1" needle="$2" hay="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  must not contain: %s\n  got : %s\n' "$desc" "$needle" "$hay"
    (( failures++ ))
  fi
}

# run <dir> <command...> -- run in a subshell rooted at <dir> with the stubs on
# PATH. Output is stdout+stderr, then a "STATUS=<n>" line and a final
# "PWD=<dir>" line, so tests can see what the function returned and where it
# left the shell (gw's whole no-arg contract). The status is part of the
# contract because agents run gw and act on it: a failure that returned 0
# would leave them working in the main checkout.
run() {
  local dir="$1"; shift
  (
    PATH="$stub_bin:$PATH"
    rehash
    cd "$dir" || exit 1
    # CONFIRM stands in for the y/N prompt, which reads /dev/tty and so cannot
    # be answered by redirecting stdin.
    if [[ -n "${CONFIRM:-}" ]]; then
      _gdmerged_confirm() { [[ "$CONFIRM" == yes ]] }
    fi
    "$@"
    printf 'STATUS=%s\n' "$?"
    printf 'PWD=%s\n' "$PWD"
  ) 2>&1
}

# Pick the two trailer lines back out of run's output.
pwd_of() { print -r -- "${1##*$'\n'}"; }
# The leading newline lets the pattern match when STATUS is the first line,
# as it is for a call that printed nothing.
status_of() { local s=$'\n'"$1"; s="${s##*$'\n'STATUS=}"; print -r -- "${s%%$'\n'*}"; }

# without_gh <command...> -- run with nothing but git on PATH, standing for a
# machine without the gh CLI. Removing the stub dir is not enough: a real gh
# shares /usr/bin with git on the CI runner.
nogh_bin="$work/nogh"
mkdir -p "$nogh_bin"
ln -s "${commands[git]}" "$nogh_bin/git"
without_gh() { PATH="$nogh_bin"; "$@"; }

# new_repo <name> -- a repository with one commit on main and no remote.
new_repo() {
  local root="$work/$1"
  mkdir -p "$root"
  git -C "$root" init -q -b main
  git -C "$root" config user.email t@example.com
  git -C "$root" config user.name test
  git -C "$root" config commit.gpgsign false
  : > "$root/README"
  git -C "$root" add README
  git -C "$root" commit -qm init
  print -r -- "$root"
}

# --------------------------------------------------------------------------
# gw
# --------------------------------------------------------------------------

out=$(run "$work" gw some-branch)
contains 'gw outside a repository refuses' 'not inside a git repository' "$out"
check 'and fails' 1 "$(status_of "$out")"

repo=$(new_repo gw-basic)
out=$(run "$repo" gw feature/thing)
check 'gw creates the worktree under git-worktrees/, slashes flattened' \
  "PWD=$repo/git-worktrees/feature-thing" "$(pwd_of "$out")"
check 'gw creates the branch' 'feature/thing' \
  "$(git -C "$repo" branch --list --format='%(refname:short)' feature/thing)"

# A name that is already a branch must fail outright. The danger is the
# opposite: carrying on past the failed `worktree add` would copy .env into a
# plain directory, cd into it and return 0, and the caller would go on working
# in something that is not a worktree at all.
repo=$(new_repo gw-taken)
git -C "$repo" branch taken
printf 'secret\n' > "$repo/.env"
print -r -- .env > "$repo/.worktree-copy"
out=$(run "$repo" gw taken)
check 'gw on an existing branch name fails' 1 "$(status_of "$out")"
check 'and leaves no directory behind' 'absent' \
  "$([[ -e "$repo/git-worktrees/taken" ]] && echo present || echo absent)"
check 'and does not move into one' "PWD=$repo" "$(pwd_of "$out")"

# gw run from inside a linked worktree -- how an agent working in one calls it
# -- still files the new worktree under the MAIN checkout and copies from the
# main checkout's .worktree-copy. Resolving the root to the current worktree
# instead would nest worktrees inside worktrees, and every other case here runs
# from the main root, where the two answers coincide.
repo=$(new_repo gw-nested)
printf 'secret\n' > "$repo/.env"
print -r -- .env > "$repo/.worktree-copy"
run "$repo" gw first >/dev/null
mkdir -p "$repo/git-worktrees/first/sub"
out=$(run "$repo/git-worktrees/first/sub" gw second)
check 'gw from inside a linked worktree files the new one under the main checkout' \
  "PWD=$repo/git-worktrees/second" "$(pwd_of "$out")"
check 'and copies from the main checkout' 'secret' \
  "$(cat "$repo/git-worktrees/second/.env" 2>&1)"

# .worktree-copy: the untracked local files a new worktree needs to be usable.
repo=$(new_repo gw-copy)
mkdir -p "$repo/config"
printf 'secret\n' > "$repo/.env"
printf 'x\n' > "$repo/config/local.yml"
cat > "$repo/.worktree-copy" <<'COPY'
# a comment

.env
config
missing-file
COPY
out=$(run "$repo" gw copied)
wt="$repo/git-worktrees/copied"
check 'gw copies a listed file' 'secret' "$(cat "$wt/.env" 2>&1)"
check 'gw copies a listed directory recursively' 'x' "$(cat "$wt/config/local.yml" 2>&1)"
contains 'gw warns about a missing entry' 'missing-file not found' "$out"
lacks 'gw ignores comment lines' 'a comment not found' "$out"

# No-argument picker.
repo=$(new_repo gw-pick)
out=$(run "$repo" gw)
contains 'gw with no worktrees says so' 'No worktrees to pick' "$out"
check 'and that is not an error' 0 "$(status_of "$out")"

run "$repo" gw one >/dev/null
run "$repo" gw two >/dev/null
export FZF_MENU="$work/menu"
out=$(FZF_PICK=two run "$repo" gw)
# Only the visible columns: the hidden third one is the absolute path, which
# contains both the branch name and the relative path, so a substring match
# on the whole menu would pass whatever the first two columns said.
visible=$(awk -F'\t' '{ sub(/ +$/, "", $1); print $1 " | " $2 }' "$work/menu")
check 'gw picks the worktree by its absolute path' \
  "PWD=$repo/git-worktrees/two" "$(pwd_of "$out")"
check 'the picker offers each linked worktree by branch and path relative to the main checkout, not main' \
  "one | git-worktrees/one"$'\n'"two | git-worktrees/two" "$visible"
unset FZF_MENU

out=$(run "$repo/git-worktrees/one" gw)
check 'cancelling the picker leaves the shell where it was' \
  "PWD=$repo/git-worktrees/one" "$(pwd_of "$out")"
check 'and is not an error' 0 "$(status_of "$out")"

# PR URLs. The guard that matters is the origin check: without it,
# `git fetch origin pull/<n>/head` reaches into whatever origin happens to be.
repo=$(new_repo gw-pr)
out=$(GH_PR_REPO=someone/other GH_PR_BRANCH=pr-branch \
      run "$repo" gw https://github.com/me/mine/pull/7)
contains 'gw refuses a PR from another repository' \
  "PR belongs to 'me/mine' but current repo is 'someone/other'" "$out"
check 'and fails' 1 "$(status_of "$out")"
check 'and creates no branch' '' \
  "$(git -C "$repo" branch --list --format='%(refname:short)' pr-branch)"

# GitHub compares owner/repo case-insensitively, so must the guard. Getting as
# far as the fetch is the proof the guard let it through; this repo has no
# origin, so the fetch itself fails.
out=$(GH_PR_REPO=Me/Mine GH_PR_BRANCH=pr-branch \
      run "$repo" gw https://github.com/me/mine/pull/7)
contains 'the origin check ignores case' 'Fetching PR #7 (pr-branch)' "$out"

out=$(GH_PR_REPO=me/mine run "$repo" gw https://github.com/me/mine/pull/7)
contains 'gw reports a PR it cannot look up' 'failed to fetch PR info' "$out"
check 'and fails' 1 "$(status_of "$out")"

out=$(run "$repo" without_gh gw https://github.com/me/mine/pull/7)
contains 'gw needs gh for a PR URL' 'gh CLI is required' "$out"
check 'and fails' 1 "$(status_of "$out")"

git -C "$repo" branch existing-pr-branch
out=$(GH_PR_REPO=me/mine GH_PR_BRANCH=existing-pr-branch \
      run "$repo" gw https://github.com/me/mine/pull/7)
contains 'gw refuses to reuse an existing local branch' \
  "local branch 'existing-pr-branch' already exists" "$out"
check 'and fails' 1 "$(status_of "$out")"
check 'and creates no worktree for it' 'absent' \
  "$([[ -e "$repo/git-worktrees/existing-pr-branch" ]] && echo present || echo absent)"

# The happy path actually fetches: origin gets a refs/pull/7/head, which is the
# ref GitHub exposes for a PR and the only thing gw asks for.
repo=$(new_repo gw-pr-ok)
origin="$work/gw-pr-ok.git"
git init -q --bare "$origin"
git -C "$repo" remote add origin "$origin"
git -C "$repo" push -q origin main
git -C "$repo" switch -qc contributor-work
git -C "$repo" commit -q --allow-empty -m "from the PR"
git -C "$repo" push -q origin contributor-work:refs/pull/7/head
git -C "$repo" switch -q main
git -C "$repo" branch -qD contributor-work
out=$(GH_PR_REPO=me/mine GH_PR_BRANCH=contributor-work \
      run "$repo" gw https://github.com/me/mine/pull/7)
check 'gw checks a PR out into its own worktree' \
  "PWD=$repo/git-worktrees/contributor-work" "$(pwd_of "$out")"
check 'and the worktree holds the PR head commit' 'from the PR' \
  "$(git -C "$repo/git-worktrees/contributor-work" log -1 --format=%s 2>&1)"

# --------------------------------------------------------------------------
# gdmerged
# --------------------------------------------------------------------------

# merged_repo -- main plus:
#   gone/*    merged, upstream deleted  -> auto-deleted, no prompt
#   kept      merged, upstream present  -> prompted
#   unmerged  not merged               -> never considered
#   develop   merged but protected     -> never deleted
merged_repo() {
  local root=$(new_repo "$1")
  local origin="$work/$1.git"
  git init -q --bare "$origin"
  git -C "$root" remote add origin "$origin"
  git -C "$root" push -q -u origin main

  local b
  for b in gone/one gone/two kept develop; do
    git -C "$root" switch -qc "$b"
    git -C "$root" commit -q --allow-empty -m "$b"
    git -C "$root" push -q -u origin "$b"
    git -C "$root" switch -q main
    git -C "$root" merge -q --no-ff -m "merge $b" "$b"
  done
  git -C "$root" switch -qc unmerged
  git -C "$root" commit -q --allow-empty -m unmerged
  git -C "$root" switch -q main

  # Delete the gone/* branches upstream, then prune, so their upstream reads
  # [gone] -- the "PR merged and the remote branch is already cleaned up"
  # signal gdmerged treats as consent.
  git -C "$origin" branch -q -D gone/one gone/two
  git -C "$root" fetch -q -p origin
  print -r -- "$root"
}

branches() { git -C "$1" branch --format='%(refname:short)' | tr '\n' ' '; }

repo=$(new_repo gd-none)
out=$(run "$repo" gdmerged)
contains 'gdmerged reports when there is nothing to delete' 'No merged branches found.' "$out"

# Answering "no" must leave everything alone.
repo=$(merged_repo gd-no)
out=$(CONFIRM=no run "$repo" gdmerged)
contains 'declining leaves the branch alone' 'skipped: kept' "$out"
check 'declining deletes only the [gone] branches' 'develop kept main unmerged ' "$(branches "$repo")"

# Answering "yes" deletes the prompted branch too.
repo=$(merged_repo gd-yes)
out=$(CONFIRM=yes run "$repo" gdmerged)
check 'accepting deletes the prompted branch as well' 'develop main unmerged ' "$(branches "$repo")"
lacks 'gdmerged never offers a protected branch' "delete 'develop'" "$out"
lacks 'gdmerged ignores unmerged branches' 'Processing branch: unmerged' "$out"

# The trunk branches are one list, read by gpushf (refuses to force-push),
# gdmerged (never deletes) and directory.zsh (shows no branch label for them).
# It was four lists, and the two in directory.zsh had lost `master`. Whole
# names only: a branch that merely contains one is an ordinary branch.
trunk_of() { _git_is_trunk "$1" && print yes || print no; }
for b in main master develop staging; do
  check "$b is a trunk branch" yes "$(trunk_of "$b")"
done
for b in mainline feature/main xmaster ''; do
  check "[$b] is not a trunk branch" no "$(trunk_of "$b")"
done

# A worktree on a merged branch goes with it.
repo=$(merged_repo gd-worktree)
git -C "$repo" worktree add -q "$repo/git-worktrees/gone-one" gone/one
out=$(run "$repo" gdmerged)
check 'the worktree of a merged branch is removed' 'absent' \
  "$([[ -d "$repo/git-worktrees/gone-one" ]] && echo present || echo absent)"
lacks 'and its branch goes with it' 'gone/one' "$(branches "$repo")"

# ...unless it holds untracked work, which would be lost with it.
repo=$(merged_repo gd-untracked)
git -C "$repo" worktree add -q "$repo/git-worktrees/gone-two" gone/two
printf 'scratch\n' > "$repo/git-worktrees/gone-two/notes.txt"
out=$(run "$repo" gdmerged)
contains 'a worktree with untracked files is kept' 'Skipping worktree removal' "$out"
check 'and its files survive' 'scratch' "$(cat "$repo/git-worktrees/gone-two/notes.txt" 2>&1)"
# The branch has to stay too: deleting it would leave the worktree checked out
# on a ref that no longer exists, which is worse than not cleaning up.
contains 'and so does its branch' 'gone/two' "$(branches "$repo")"

# Manually deleted worktree directories: git still thinks the branch is checked
# out there, so a plain `git branch -d` refuses. Note this asserts the outcome,
# not the `git worktree prune` that opens gdmerged -- `git worktree remove
# --force` clears the same stale record, so the two cover each other here.
repo=$(merged_repo gd-prune)
git -C "$repo" worktree add -q "$repo/git-worktrees/gone-one" gone/one
/bin/rm -rf "$repo/git-worktrees/gone-one"
out=$(run "$repo" gdmerged)
lacks 'a manually deleted worktree does not block its branch' 'gone/one' "$(branches "$repo")"

/bin/rm -rf "$work"

if (( failures )); then
  printf '\nFAIL=%d\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
