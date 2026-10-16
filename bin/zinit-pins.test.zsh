#!/usr/bin/env zsh
# Unit tests for bin/zinit-pins, the one reader of the commit pins in
# zsh/plugin.zsh. See bin/zinit-pins.md.
#
# What it must never do is pass over a pin it could not read: whatever reads
# its output (plugin.test.zsh, the cooldown updater) would then leave that
# plugin where it is, and "not updated" looks the same as "up to date". So most
# cases are files it has to refuse.
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

# read_pins <body> — run the reader on a plugin.zsh holding zinit's pin and
# <body>; prints stdout, then "exit=<status>", then stderr.
read_pins() {
  local file=$TMP/plugin.zsh
  print -r -- "_zinit_repo=zdharma-continuum/zinit
_zinit_pin=$Z
$1" > $file
  local out err
  out=$($READER $file 2>$TMP/err)
  local -i st=$?
  err=$(<$TMP/err)
  print -r -- "$out"
  print -r -- "exit=$st"
  print -rn -- "$err"
}

check 'lists zinit, then each plugin, as <repo> <sha>' \
  "zdharma-continuum/zinit $Z"$'\n'"a/one $A"$'\n'"b/two $B"$'\n'"exit=0" \
  "$(read_pins "zinit ice ver\"$A\"
zinit light a/one
# a comment, and a blank line, between an ice and its plugin

zinit ice wait lucid atload\"bindkey '^j' x\" ver'$B'
zinit load b/two # trailing comment")"

check 'reads an indented ice and plugin' \
  "zdharma-continuum/zinit $Z"$'\n'"a/one $A"$'\n'"exit=0" \
  "$(read_pins "  zinit ice ver\"$A\"
  zinit light a/one")"

check 'refuses a plugin without a ver, naming it' \
  '*exit=1*a/one*' \
  "$(read_pins 'zinit light a/one')"

check 'refuses a ver that is not a full SHA' \
  '*exit=1*a/one*' \
  "$(read_pins 'zinit ice ver"1111111"
zinit light a/one')"

# An ice belongs to the next plugin only; a stray line in between ends it.
check 'refuses an ice separated from its plugin by other code' \
  '*exit=1*a/one*' \
  "$(read_pins "zinit ice ver\"$A\"
true
zinit light a/one")"

check 'refuses a zinit form it cannot read, naming the line' \
  '*exit=1*zinit snippet OMZ::lib/git.zsh*' \
  "$(read_pins 'zinit snippet OMZ::lib/git.zsh')"

check 'refuses an inline ice' \
  '*exit=1*zinit wait light a/one*' \
  "$(read_pins 'zinit wait light a/one')"

check 'refuses a file without _zinit_pin' \
  '*_zinit_pin*exit=1' \
  "$(print -r -- "_zinit_repo=x/y" > $TMP/nopin.zsh; $READER $TMP/nopin.zsh 2>&1; print -r -- "exit=$?")"

check 'refuses a missing file' \
  '*exit=1*' \
  "$($READER $TMP/nowhere.zsh 2>&1; print -r -- "exit=$?")"

# Without an argument it reads the plugin.zsh of the checkout it lives in,
# through the ~/.local/bin symlink as much as directly.
ln -s $READER $TMP/zinit-pins
check 'with no argument, reads its own checkout'"'"'s zsh/plugin.zsh' \
  "$($READER ${0:A:h}/../zsh/plugin.zsh)" \
  "$($TMP/zinit-pins)"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
