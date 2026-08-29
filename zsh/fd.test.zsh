#!/usr/bin/env zsh
# Unit tests for the fd() directory picker (zsh/alias.zsh).
#
# fd() lists directories, hands them to fzf, and cds into the pick. The whole
# observable behaviour is "where did the shell end up", which is why the bug it
# had was so quiet: cd ran twice, and the second one usually failed harmlessly
# with the shell already in the right place. It only misfires when the second
# cd can succeed -- i.e. when the selected path also resolves from inside
# itself, as with a/a -- and then it silently lands a level too deep.
#
# fzf is replaced by a stub so the picker is non-interactive: the stub prints
# the line named by FZF_PICK, or exits 1 to stand for the user pressing Escape.
#
# Run: zsh zsh/fd.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/alias.zsh"

typeset -i failures=0

work=$(mktemp -d)
stub_bin="$work/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/fzf" <<'STUB'
#!/bin/sh
# Stands in for the picker. FZF_PICK selects a line from stdin; unset means the
# user cancelled, which fzf reports as a non-zero exit with no output.
[ -n "${FZF_PICK:-}" ] || { cat >/dev/null; exit 1; }
grep -x -F -- "$FZF_PICK" || exit 1
STUB
chmod +x "$stub_bin/fzf"

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

# pick_from <start-dir> <line> — run fd() in a subshell with the stub on PATH
# and report where the shell ended up, relative to the start.
pick_from() {
  local start="$1" pick="$2"
  (
    PATH="$stub_bin:$PATH"
    rehash
    cd "$start" || exit 1
    FZF_PICK="$pick" fd >/dev/null 2>&1
    print -r -- "${PWD#$start}"
  )
}

# a/a is the shape that exposes a repeated cd: "./a" resolves again from inside
# the first a, so a second cd succeeds and lands a level too deep instead of
# failing harmlessly.
mkdir -p "$work/nested/a/a"
check 'cds once, not twice, when the name repeats' \
  '/a' \
  "$(pick_from "$work/nested" './a')"

mkdir -p "$work/plain/target"
check 'cds into the selected directory' \
  '/target' \
  "$(pick_from "$work/plain" './target')"

# Escape from fzf must leave the shell where it was.
check 'stays put when the picker is cancelled' \
  '' \
  "$(
    (
      PATH="$stub_bin:$PATH"
      rehash
      cd "$work/plain" || exit 1
      unset FZF_PICK
      fd >/dev/null 2>&1
      print -r -- "${PWD#$work/plain}"
    )
  )"

command rm -rf "$work"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
