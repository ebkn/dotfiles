#!/usr/bin/env zsh
# Unit tests for the rm() wrapper (zsh/alias.zsh).
#
# rm() routes deletions through `trash` so a mistake stays recoverable. Two
# things about it are easy to break and impossible to notice by using the shell
# normally, because both failure modes look like a successful delete:
#
#   1. trash missing. It is macOS-only and absent until `brew bundle` has run,
#      so the wrapper must fall back to the real rm rather than leaving the
#      shell with no working rm at all.
#   2. what actually reaches trash. The wrapper drops flags on purpose (so
#      `rm -rf dir` still goes to the trash rather than being refused), and
#      dropping the wrong thing silently deletes the wrong file.
#
# The tests run against a stub `trash` on PATH that records its argv, so they
# assert the real contract -- what the wrapper hands the deleting command --
# without deleting anything outside a temp directory.
#
# Run: zsh zsh/rm.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/alias.zsh"

typeset -i failures=0
typeset -g work="" stub_bin="" argv_log=""

setup() {
  work=$(mktemp -d)
  stub_bin="$work/bin"
  argv_log="$work/argv"
  mkdir -p "$stub_bin"
  # One argument per line: the point of these tests is the exact argv, so the
  # log must not re-split or re-glob anything.
  cat >"$stub_bin/trash" <<'STUB'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >>"$ARGV_LOG"
STUB
  chmod +x "$stub_bin/trash"
  export ARGV_LOG="$argv_log"
  : >"$argv_log"
}

teardown() {
  [[ -n "$work" ]] && command rm -rf "$work"
}

# with_trash <argv...> — run rm() with the stub on PATH, echo what trash got.
with_trash() {
  local saved=$PATH
  PATH="$stub_bin:$PATH"
  rehash
  : >"$argv_log"
  rm "$@"
  PATH=$saved
  rehash
  cat "$argv_log"
}

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "${want//$'\n'/ | }" "${got//$'\n'/ | }"
    (( failures++ ))
  fi
}

setup

# --- the guard ---------------------------------------------------------------

# Without trash on PATH the wrapper must delete for real rather than failing.
#
# The PATH here holds exactly one binary, a link to the real rm. Trimming to
# "/bin:/usr/bin" instead would be a FALSE GREEN on macOS: recent versions ship
# their own /usr/bin/trash (confirmed on 26.1), so the guard would be skipped
# and the file would be deleted by trash -- which is what this case asserts did
# NOT happen. Anything that puts a trash back on PATH breaks the test silently,
# so keep this hermetic.
(
  touch "$work/victim"
  mkdir -p "$work/onlyrm"
  ln -s "$(whence -p rm)" "$work/onlyrm/rm"
  PATH="$work/onlyrm"
  rehash
  rm "$work/victim"
)
if [[ -e "$work/victim" ]]; then
  printf 'FAIL falls back to the real rm when trash is absent\n  file still exists\n'
  (( failures++ ))
else
  printf 'ok   falls back to the real rm when trash is absent\n'
fi
rehash

# --- what reaches trash ------------------------------------------------------

check 'passes a plain path through' \
  "$work/a" \
  "$(touch "$work/a"; with_trash "$work/a")"

check 'drops -r so rm -rf still reaches trash' \
  "$work/d" \
  "$(mkdir -p "$work/d"; with_trash -rf "$work/d")"

check 'keeps every operand when several are given' \
  "$work/a
$work/b" \
  "$(touch "$work/a" "$work/b"; with_trash "$work/a" "$work/b")"

# --- operands that look like options -----------------------------------------

# `rm -- -foo` is the standard way to delete a file whose name starts with a
# dash. Dropping every dash-prefixed argument threw away both the -- and the
# filename, so trash was called with no operands and the file survived. The
# operand is passed as ./-foo rather than after a --, because that needs nothing
# from the receiving command and so holds for the real rm fallback too.
check 'delimits an operand that starts with a dash' \
  './-dash' \
  "$(cd "$work" && touch -- -dash && with_trash -- -dash)"

check 'leaves an absolute path alone' \
  "$work/a" \
  "$(touch "$work/a"; with_trash -- "$work/a")"

# --- -f ----------------------------------------------------------------------

# -f means "ignore operands that do not exist, and never prompt". Passing a
# missing path to trash instead makes it complain and fail, so `rm -f x` broke
# in exactly the case -f exists to make quiet.
check '-f drops operands that do not exist' \
  '' \
  "$(with_trash -f "$work/gone")"

check '-f keeps the operands that do exist' \
  "$work/a" \
  "$(touch "$work/a"; with_trash -f "$work/a" "$work/gone")"

check '-f inside a bundled flag is still seen' \
  '' \
  "$(with_trash -rf "$work/gone")"

check 'GNU --force is seen too' \
  '' \
  "$(with_trash --force "$work/gone")"

# The boundary of the -f test: a long option that merely contains an "f" is not
# -f. Both operands reaching trash is the proof that force did not fire -- had
# it, the missing one would have been filtered out and trash would complain
# about nothing at all.
check '--one-file-system is not read as -f' \
  "$work/a
$work/gone" \
  "$(touch "$work/a"; with_trash --one-file-system "$work/a" "$work/gone")"

# With every operand gone there is nothing to delete, and -f says to be quiet
# about it. Calling trash with no operands would make it print its usage.
rm -f "$work/gone" >/dev/null 2>&1
check '-f with nothing left to delete succeeds quietly' '0' "$?"

teardown

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
