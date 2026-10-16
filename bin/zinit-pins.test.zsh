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

# No plugins is a valid configuration: zinit's own pin is still listed. A
# plugin line the reader did not recognise is refused by the cases below, so
# an empty plugin list here does mean there are none.
check 'with no plugins, lists zinit alone' \
  $'exit=0\nout='"zdharma-continuum/zinit $Z"$'\nerr=' \
  "$(read_pins '# nothing else')"

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

# The pin is a ver word of the ice, as zinit reads the line -- not the text
# "ver" anywhere on it. In the first two zinit loads the plugin unpinned.
check 'refuses a ver that is only in a comment on the ice' \
  "$(refused '*a/one*')" \
  "$(read_pins "zinit ice wait lucid # was ver\"$A\"
zinit light a/one")"

check 'refuses a ver that is inside another ice'"'"'s value' \
  "$(refused '*a/one*')" \
  "$(read_pins "zinit ice atload\"echo ver'$A'\"
zinit light a/one")"

check 'refuses a ver that is the tail of another ice name' \
  "$(refused '*a/one*')" \
  "$(read_pins "zinit ice nover\"$A\"
zinit light a/one")"

# Which of two would a caller moving the pin rewrite?
check 'refuses two vers on one ice' \
  "$(refused '*a/one*')" \
  "$(read_pins "zinit ice ver\"$A\" ver\"$B\"
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

# An ice line that goes on to run more: zinit applies the ice to b/two, and
# a/one, on the next line, loads unpinned.
check 'refuses an ice line followed by ; and another zinit' \
  "$(refused '*cannot read: zinit ice ver"'"$A"'"; zinit light b/two*')" \
  "$(read_pins "zinit ice ver\"$A\"; zinit light b/two
zinit light a/one")"

check 'refuses an ice line followed by && and another zinit' \
  "$(refused '*cannot read: zinit ice ver"'"$A"'" && zinit light b/two*')" \
  "$(read_pins "zinit ice ver\"$A\" && zinit light b/two
zinit light a/one")"

# The operator alone is enough, with no second zinit on the line: `| cat`
# runs the ice in a subshell, so it never reaches a/one.
check 'refuses an ice line piped into another command' \
  "$(refused '*cannot read: zinit ice ver"'"$A"'" ? cat*')" \
  "$(read_pins "zinit ice ver\"$A\" | cat
zinit light a/one")"

check 'refuses an ice line followed by ; and a command other than zinit' \
  "$(refused '*cannot read: zinit ice ver"'"$A"'"; true*')" \
  "$(read_pins "zinit ice ver\"$A\"; true
zinit light a/one")"

# What the shell words leave alone: text inside a quoted string. plugin.zsh
# has such a line itself, and an ice value may hold shell code.
check 'reads past zinit inside a quoted string' \
  $'exit=0\nout='"zdharma-continuum/zinit $Z"$'\n'"a/one $A"$'\nerr=' \
  "$(read_pins "print -u2 -- \"plugin.zsh: cannot check out zinit's pin\"
zinit ice ver\"$A\"
zinit light a/one")"

check 'reads an ice whose value holds an operator' \
  $'exit=0\nout='"zdharma-continuum/zinit $Z"$'\n'"a/one $A"$'\nerr=' \
  "$(read_pins "zinit ice atload\"a; b && c\" ver\"$A\"
zinit light a/one")"

# No operator, but a second zinit as a word of the ice line: b/two is loaded
# from inside the substitution and would be missing from the list.
check 'refuses an ice line that runs zinit again in a substitution' \
  "$(refused '*cannot read: zinit ice ver"'"$A"'" $?zinit light b/two?*')" \
  "$(read_pins "zinit ice ver\"$A\" \$(zinit light b/two)
zinit light a/one")"

# Ways of writing the command name that still run zinit.
check 'refuses \zinit' \
  "$(refused '*cannot read: \\zinit light b/two*')" \
  "$(read_pins '\zinit light b/two')"

check 'refuses a quoted zinit' \
  "$(refused "*cannot read: 'zinit' light b/two*")" \
  "$(read_pins "'zinit' light b/two")"

check 'refuses a double-quoted zinit' \
  "$(refused '*cannot read: "zinit" light b/two*')" \
  "$(read_pins '"zinit" light b/two')"

check 'refuses zinit run inside $(…)' \
  "$(refused '*cannot read: x=$?zinit light c/cond?*')" \
  "$(read_pins 'x=$(zinit light c/cond)')"

check 'refuses an escaped zinit inside $(…)' \
  "$(refused '*cannot read: x=$?\\zinit light c/x?*')" \
  "$(read_pins 'x=$(\zinit light c/x)')"

check 'refuses a quoted zinit inside $(…)' \
  "$(refused '*cannot read: x=$?"zinit" light c/x?*')" \
  "$(read_pins 'x=$("zinit" light c/x)')"

# eval runs a string, so the zinit inside it is one quoted word to the split.
check 'refuses zinit run through eval' \
  "$(refused '*cannot read: eval "zinit light c/x"*')" \
  "$(read_pins 'eval "zinit light c/x"')"

# ...but an eval that does not mention zinit is ordinary shell, and must not
# stop a caller reading the pins.
check 'reads past an eval line that does not mention zinit' \
  $'exit=0\nout='"zdharma-continuum/zinit $Z"$'\n'"a/one $A"$'\nerr=' \
  "$(read_pins "eval \"\$(direnv hook zsh)\"
zinit ice ver\"$A\"
zinit light a/one")"

check 'refuses zinit run inside backquotes' \
  "$(refused '*cannot read: x=`zinit light c/cond`*')" \
  "$(read_pins 'x=`zinit light c/cond`')"

# The same, the other way round: a plugin line that goes on to run more.
check 'refuses a plugin line followed by && and another zinit' \
  "$(refused '*cannot read: zinit light a/one && zinit light b/two*')" \
  "$(read_pins "zinit ice ver\"$A\"
zinit light a/one && zinit light b/two")"

check 'refuses a plugin line followed by ; and another zinit' \
  "$(refused '*cannot read: zinit light a/one; zinit light b/two*')" \
  "$(read_pins "zinit ice ver\"$A\"
zinit light a/one; zinit light b/two")"

check 'refuses a plugin continued onto the next line' \
  "$(refused '*cannot read: zinit light \\*')" \
  "$(read_pins "zinit ice ver\"$A\"
zinit light \\
  a/one")"

check 'refuses a quoted plugin name' \
  "$(refused '*cannot read: zinit light "a/one"*')" \
  "$(read_pins "zinit ice ver\"$A\"
zinit light \"a/one\"")"

# zinit would merge two ices; the reader does not try to, and refuses the file
# whichever of them holds the ver.
check 'refuses two ices in a row, the ver on the first' \
  "$(refused '*an ice with no zinit light?load after it*')" \
  "$(read_pins "zinit ice ver\"$A\"
zinit ice wait lucid
zinit light a/one")"

check 'refuses two ices in a row, the ver on the second' \
  "$(refused '*an ice with no zinit light?load after it*')" \
  "$(read_pins "zinit ice wait lucid
zinit ice ver\"$A\"
zinit light a/one")"

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

check 'refuses a _zinit_repo that is not owner/repo alone' \
  "$(refused '*_zinit_repo*')" \
  "$(read_file "_zinit_repo=zdharma-continuum/zinit # the fork
_zinit_pin=$Z")"

check 'refuses a second _zinit_repo' \
  "$(refused '*_zinit_repo*')" \
  "$(read_file "$HEADER
_zinit_repo=other/zinit")"

check 'refuses a second _zinit_pin' \
  "$(refused '*_zinit_pin*')" \
  "$(read_file "$HEADER
_zinit_pin=$A")"

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
