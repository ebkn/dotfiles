#!/usr/bin/env zsh
# Unit tests for bin/zinit-pins, the one reader of the commit pins in
# zsh/plugin.zsh. See bin/zinit-pins.md.
#
# What it must never do is pass over a pin it could not read: whatever reads
# its output (plugin.test.zsh, the cooldown updater) would then leave that
# plugin where it is, and "not updated" looks the same as "up to date". So most
# cases are files it has to refuse -- with nothing on stdout, since stdout is
# what a caller acts on.
#
# Run: zsh bin/zinit-pins.test.zsh   (exit 0 = pass)

set -u

READER=${0:A:h}/zinit-pins

typeset -i failures=0

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == $~want ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zinit-pins-test.XXXXXX")
trap 'rm -rf $TMP' EXIT

A=1111111111111111111111111111111111111111
B=2222222222222222222222222222222222222222
Z=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
HEADER="_zinit_repo=zdharma-continuum/zinit
_zinit_pin=$Z"

# run_reader [args...] — run the reader; prints three labelled lines so a case
# can pin the status exactly and see stdout and stderr apart:
#   exit=<status>
#   out=<stdout>
#   err=<stderr>
run_reader() {
  local out
  out=$($READER "$@" 2>$TMP/err)
  print -r -- "exit=$?"
  print -r -- "out=$out"
  print -rn -- "err=$(<$TMP/err)"
}

# read_file <content> — the reader on a file holding exactly <content>.
read_file() {
  print -r -- "$1" > $TMP/plugin.zsh
  run_reader $TMP/plugin.zsh
}

# read_pins <body> — the same, with zinit's own pin in front of <body>.
read_pins() { read_file "$HEADER"$'\n'"$1"; }

# A refusal: status 1, nothing on stdout, and stderr matching <pattern>.
refused() { print -r -- $'exit=1\nout=\nerr='"$1"; }

# --- What it reads ----------------------------------------------------------

check 'lists zinit, then each plugin, as <repo> <sha>' \
  $'exit=0\nout='"zdharma-continuum/zinit $Z"$'\n'"a/one $A"$'\n'"b/two $B"$'\nerr=' \
  "$(read_pins "zinit ice ver\"$A\"
zinit light a/one
# a comment, and a blank line, between an ice and its plugin

zinit ice wait lucid atload\"bindkey '^j' x\" ver'$B'
zinit load b/two # trailing comment")"

check 'reads indented lines, and tabs between the words' \
  $'exit=0\nout='"zdharma-continuum/zinit $Z"$'\n'"a/one $A"$'\nerr=' \
  "$(read_pins "  zinit	ice ver\"$A\"
  zinit	light a/one")"

# --- What it refuses, printing no pins --------------------------------------

check 'refuses a plugin without a ver, naming it' \
  "$(refused '*a/one*')" \
  "$(read_pins 'zinit light a/one')"

check 'refuses a ver that is not a full SHA' \
  "$(refused '*a/one*')" \
  "$(read_pins 'zinit ice ver"1111111"
zinit light a/one')"

check 'refuses a ver one hex digit too long' \
  "$(refused '*a/one*')" \
  "$(read_pins "zinit ice ver\"${A}1\"
zinit light a/one")"

check 'refuses a ver whose quotes do not match' \
  "$(refused '*a/one*')" \
  "$(read_pins "zinit ice ver\"$A'
zinit light a/one")"

# An ice belongs to the next plugin only; a stray line in between ends it.
check 'refuses an ice separated from its plugin by other code' \
  "$(refused '*a/one*')" \
  "$(read_pins "zinit ice ver\"$A\"
true
zinit light a/one")"

check 'refuses an ice with no plugin after it' \
  "$(refused '*ice*')" \
  "$(read_pins "zinit ice ver\"$A\"")"

check 'refuses a zinit form it cannot read, naming the line' \
  "$(refused '*zinit snippet OMZ::lib/git.zsh*')" \
  "$(read_pins 'zinit snippet OMZ::lib/git.zsh')"

check 'refuses an inline ice' \
  "$(refused '*zinit wait light a/one*')" \
  "$(read_pins 'zinit wait light a/one')"

check 'refuses zinit run from inside another command' \
  "$(refused '*zinit light c/cond*')" \
  "$(read_pins '[[ -n $X ]] && zinit light c/cond')"

# The pins it could read are withheld too, and every problem is named, not
# just the first: a caller fixes them all in one pass.
check 'names every problem, and prints none of the pins it did read' \
  "$(refused '*a/one*zinit snippet x*c/three*')" \
  "$(read_pins "zinit light a/one
zinit ice ver\"$B\"
zinit light b/two
zinit snippet x
zinit light c/three")"

check 'refuses a file without _zinit_pin' \
  "$(refused '*_zinit_pin*')" \
  "$(read_file '_zinit_repo=zdharma-continuum/zinit')"

check 'refuses a file without _zinit_repo' \
  "$(refused '*_zinit_repo*')" \
  "$(read_file "_zinit_pin=$Z")"

check 'refuses a _zinit_pin that is not a full SHA' \
  "$(refused '*_zinit_pin*')" \
  "$(read_file '_zinit_repo=zdharma-continuum/zinit
_zinit_pin=abc')"

check 'refuses a missing file' \
  "$(refused '*cannot read*nowhere.zsh*')" \
  "$(run_reader $TMP/nowhere.zsh)"

# --- Where it reads by default ----------------------------------------------

# Without an argument it reads the plugin.zsh of the checkout it lives in,
# through any symlink to it.
ln -s $READER $TMP/zinit-pins
own=$(run_reader ${0:A:h}/../zsh/plugin.zsh)
check "the checkout's own plugin.zsh is read without refusal" \
  $'exit=0\nout=?*\nerr=' \
  "$own"
check 'with no argument, through a symlink, reads that same file' \
  "${(b)own}" \
  "$(READER=$TMP/zinit-pins run_reader)"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
