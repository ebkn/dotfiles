#!/usr/bin/env zsh
# Unit tests for his() and gs() -- the two functions that used to exist twice,
# once per platform, differing only in `gsed` vs `sed`.
#
# Collapsing them rests on one claim: `-E` is the ERE flag BSD sed and GNU sed
# both accept, so `gsed -r` and `sed -E` do the same thing. That claim cannot be
# checked on one machine. This file is the differential -- it runs on macOS
# against BSD sed locally, and on ubuntu-latest against GNU sed in CI. Neither
# run alone proves much; disagreement between them is the signal.
#
# his() ends in `print -z`, which pushes onto the editor buffer stack and is not
# readable from a non-interactive shell, so the substitutions live in
# _his_clean and are tested there. gs() is tested end to end with git and fzf
# stubbed, because the part worth pinning is which branch name it hands to
# `git switch`.
#
# Run: zsh zsh/his.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/alias.zsh"
source "${0:A:h}/git.zsh"

typeset -i failures=0
work=${$(mktemp -d):A}
stub_bin="$work/bin"
mkdir -p "$stub_bin"

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

# --- _his_clean: strip fzf's history number, re-escape backslashes ----------

clean() { print -r -- "$1" | _his_clean; }

check 'strips a plain history number'      'git status'   "$(clean '  123  git status')"
check 'strips the * that marks the current entry' 'vim ~/.zshrc' "$(clean ' 1234* vim ~/.zshrc')"
check 'handles a number with no padding'   'ls'           "$(clean '12345  ls')"
# The backslash pass is why this is not a single expression: a history line is
# put back on the command line, where a lone backslash would escape whatever
# follows it instead of standing for itself.
check 'doubles a backslash'                'echo a\\b'    "$(clean '  1  echo a\b')"
check 'doubles each of several'            'printf x\\\\y' "$(clean '  1  printf x\\y')"
# Only the leading run is a history number; digits inside the command stay.
check 'leaves digits in the command alone' 'grep -E "^[0-9]+$" f' "$(clean '  42  grep -E "^[0-9]+$" f')"

# --- gs: which branch name reaches `git switch` -----------------------------

cat >"$stub_bin/fzf" <<'STUB'
#!/bin/sh
# Stands in for the picker: FZF_PICK selects a line from the branch list.
grep -F -- "$FZF_PICK" || exit 1
STUB
cat >"$stub_bin/git" <<'STUB'
#!/bin/sh
# Records the switch target; serves a fixed branch list for everything else.
if [ "$1" = switch ]; then
  shift
  printf '%s\n' "$*" > "$GIT_SWITCH_LOG"
  exit 0
fi
cat "$GIT_BRANCH_LIST"
STUB
chmod +x "$stub_bin/fzf" "$stub_bin/git"

cat > "$work/branches" <<'BRANCHES'
* main
  feature/local
  remotes/origin/HEAD -> origin/main
  remotes/origin/feature/remote
  remotes/upstream/other
BRANCHES

switched_to() {
  (
    PATH="$stub_bin:$PATH"
    rehash
    export GIT_BRANCH_LIST="$work/branches" GIT_SWITCH_LOG="$work/switch"
    : > "$GIT_SWITCH_LOG"
    FZF_PICK="$1" gs >/dev/null 2>&1
    cat "$GIT_SWITCH_LOG"
  )
}

check 'a local branch switches by name'    'feature/local'  "$(switched_to feature/local)"
# The remote cases are the whole reason for the two substitutions: the first
# takes the last whitespace-separated field, the second drops the remotes/<name>/
# prefix so the switch creates a tracking branch rather than failing.
check 'a remote branch loses its remote prefix' 'feature/remote' "$(switched_to origin/feature/remote)"
check 'and so does one on another remote' 'other' "$(switched_to upstream/other)"
# grep -v HEAD in gs() drops the symbolic ref, which would otherwise switch to
# whatever "-> origin/main" reduced to.
check 'the HEAD pointer is not offered'    ''               "$(switched_to 'origin/HEAD')"

/bin/rm -rf "$work"

if (( failures )); then
  printf '\nFAIL=%d\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
