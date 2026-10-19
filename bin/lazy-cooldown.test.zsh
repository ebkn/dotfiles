#!/usr/bin/env zsh
# Unit tests for bin/lazy-cooldown. See bin/lazy-cooldown.md.
#
# GitHub is a gh first on PATH that answers each `gh api <endpoint>` from a
# file the case wrote, and fails like a 404 for any endpoint it was not given,
# so a case that forgot one fails loudly instead of the tool deciding on
# nothing. nvim is a stub too: it prints the plugin list a case wrote, after
# the same unterminated line image.nvim writes to stdout under --headless, so
# the first record shares its line, and a reader that looked for records only
# at the start of a line loses that plugin. The stub runs none of the Lua the
# tool passes; that is checked by running the tool for real (see the .md).
#
# Every case checks the tool's status and the plugin's own report line as well
# as the file: "unchanged" is also what a tool that never ran leaves.
#
# Run: zsh bin/lazy-cooldown.test.zsh   (exit 0 = pass)

set -u
zmodload zsh/datetime

TOOL=${0:A:h}/lazy-cooldown

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

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lazy-cooldown-test.XXXXXX")
trap 'rm -rf $TMP' EXIT

mkdir -p $TMP/bin
print -r -- '#!/bin/sh
# gh api [flags] <endpoint>: answer from $GH_FIXTURES, keyed by the endpoint.
shift
for a; do case $a in -*) ;; *) ep=$a ;; esac; done
f=$GH_FIXTURES/$(printf %s "$ep" | tr "/?&=" "____")
printf "%s\n" "$ep" >> "$GH_FIXTURES/calls"
if [ -f "$f" ]; then cat "$f"; else echo "gh: Not Found (HTTP 404) $ep" >&2; exit 1; fi' > $TMP/bin/gh
print -r -- '#!/bin/sh
# nvim: what lazy.nvim would print, or a failure when the case wrote none.
[ -f "$GH_FIXTURES/nvim" ] || exit 1
printf "image.nvim: cannot query terminal size (non-terminal environment?)"
cat "$GH_FIXTURES/nvim"' > $TMP/bin/nvim
chmod +x $TMP/bin/gh $TMP/bin/nvim

# SHAs: P and Q the pins, then commits around them.
P=1111111111111111111111111111111111111111
Q=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
N=2222222222222222222222222222222222222222
O=4444444444444444444444444444444444444444
T=5555555555555555555555555555555555555555 # the branch tip a week ago
L=9999999999999999999999999999999999999999 # the branch tip now

ago() { TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $(( EPOCHSECONDS - $1 * 86400 )); }

# fresh_case — a new fixture set and a lockfile, in lazy.nvim's own layout,
# pinning one.nvim (a/one, main) at P and two.vim (b/two, release) at Q.
typeset -i n=0
fresh_case() {
  export GH_FIXTURES=$TMP/case$(( ++n ))
  mkdir -p $GH_FIXTURES
  LOCK=$GH_FIXTURES/lazy-lock.json
  print -r -- "{
  \"one.nvim\": { \"branch\": \"main\", \"commit\": \"$P\" },
  \"two.vim\": { \"branch\": \"release\", \"commit\": \"$Q\" }
}" > $LOCK
  plugins 'one.nvim https://github.com/a/one.git' 'two.vim https://github.com/b/two.git'
}

# plugins <name url>... — what lazy.nvim reports, one record per plugin.
plugins() { print -rl -- ${argv/#/lazy-cooldown } > $GH_FIXTURES/nvim; }

serve() { print -r -- "$2" > $GH_FIXTURES/${${1//[\/?&=]/_}}; }

# history <owner/repo> <branch> — pushed to 10 days ago (tip then: T) and 2
# days ago (tip now: L).
history() {
  serve "repos/$1/activity?ref=refs/heads/$2&per_page=100" \
    '[{"timestamp":"'$(ago 2)'","after":"'$L'"},{"timestamp":"'$(ago 10)'","after":"'$T'"}]'
}

# compare <owner/repo> <base> <head> <status>
compare() { serve "repos/$1/compare/$2...$3" '{"status":"'$4'"}'; }

# two_still — b/two held where it is in every case that is not about it.
two_still() { history b/two release; compare b/two $Q $T behind; }

run() {
  out=$(PATH=$TMP/bin:$PATH zsh -f $TOOL "$@" $LOCK 2>&1)
  st=$?
}

said() { local l=${(M)${(f)out}:#$1: *}; print -r -- "${l#$1: }"; }

pins_now() { grep -o '[[:xdigit:]]\{40\}' $LOCK | tr '\n' ' '; }

# --- Moving --------------------------------------------------------------

fresh_case; two_still; history a/one main
compare a/one $P $T ahead   # the tip of a week ago is past the pin
compare a/one $T main ahead # and still on the branch
before=$(cat $LOCK; print x)
run
check 'moves a pin to its branch tip of a week ago' \
  "0 moved 1111111..5555555 \(main 7 days ago\) https://github.com/a/one/compare/$P...$T" \
  "$st $(said one.nvim)"
check '  ... rewriting that SHA and nothing else in the lockfile' \
  "${(b)${before//$P/$T}}" "$(cat $LOCK; print x)"

# The branch the lockfile names, not the default one: coc.nvim follows release.
fresh_case; history a/one main; compare a/one $P $T behind
history b/two release
compare b/two $Q $T ahead
compare b/two $T release identical
run
check 'gates on the branch the lockfile names' \
  '0 moved aaaaaaa..5555555 \(release 7 days ago\)*' "$st $(said two.vim)"

fresh_case; history a/one main
compare a/one $P $T ahead
compare a/one $T main ahead
history b/two release
compare b/two $Q $T ahead
compare b/two $T release ahead
run
check 'moves two pins in one run' '0' "$st"
check '  ... and both moves are in the file' "$T $T " "$(pins_now)"
check '  ... leaving no temporary file behind' '' "$(print -l -- $GH_FIXTURES/*.cooldown(N))"

# The 7 days themselves: pushes a day either side of the cutoff. A cutoff
# short of 7 days picks the 6-day one, whose compare is not served.
fresh_case; two_still
X6=6666666666666666666666666666666666666666
X8=8888888888888888888888888888888888888888
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" \
  '[{"timestamp":"'$(ago 6)'","after":"'$X6'"},{"timestamp":"'$(ago 8)'","after":"'$X8'"}]'
compare a/one $P $X8 ahead
compare a/one $X8 main ahead
run
check 'the cutoff is 7 days: the tip is the push 8 days ago, not 6' \
  '0 moved 1111111..8888888*' "$st $(said one.nvim)"

fresh_case; history b/two release; compare b/two $Q $L behind; history a/one main
compare a/one $P $L ahead
compare a/one $L main identical
run --days 1
check '--days sets the cutoff' '0 moved 1111111..9999999 \(main 1 days ago\)*' "$st $(said one.nvim)"

# --- Holding -------------------------------------------------------------

fresh_case; two_still
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" \
  '[{"timestamp":"'$(ago 10)'","after":"'$P'"}]'
run
check 'a pin at the tip of a week ago is up to date' \
  '0 up to date \(main 7 days ago\)' "$st $(said one.nvim)"
check '  ... and left alone' "$P $Q " "$(pins_now)"

# A pin newer than the cutoff -- taken by hand, or before the cooldown --
# is never moved back to the older tip, but the line says it is unvetted.
fresh_case; two_still; history a/one main
compare a/one $P $T behind
run
check 'never moves a pin back, but names the tip it is ahead of' \
  "0 stays: main 7 days ago \($T\) is behind the pin*" "$st $(said one.nvim)"
check '  ... and leaves it' "$P $Q " "$(pins_now)"

fresh_case; two_still; history a/one main
compare a/one $P $T diverged
run
check 'never moves to a tip that does not descend from the pin' \
  "0 stays: main 7 days ago \($T\) has diverged from the pin*" "$st $(said one.nvim)"
check '  ... and leaves it' "$P $Q " "$(pins_now)"

# Force-pushed away since: the commit is not on the branch any more, so
# lazy.nvim would not fetch it and its restore would fail.
fresh_case; two_still; history a/one main
compare a/one $P $T ahead
compare a/one $T main diverged
run
check 'holds a pin whose target was force-pushed off the branch' \
  "0 stays: 5555555 is no longer on main" "$st $(said one.nvim)"
check '  ... and leaves it' "$P $Q " "$(pins_now)"

fresh_case; two_still
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" \
  '[{"timestamp":"'$(ago 2)'","after":"'$L'"}]'
run
check 'holds a plugin whose push history does not reach back a week' \
  '0 stays: no push to main older than 7 days on record' "$st $(said one.nvim)"
check '  ... and leaves it' "$P $Q " "$(pins_now)"

# rust.vim renamed master to main: the lockfile still names master, whose
# last push is its deletion, with the zero SHA for `after`.
fresh_case; two_still
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" \
  '[{"timestamp":"'$(ago 10)'","after":"0000000000000000000000000000000000000000"}]'
run
check 'holds a plugin whose branch had been deleted at the cutoff' \
  '0 stays: no main branch 7 days ago \(deleted or renamed\)' "$st $(said one.nvim)"
check '  ... and leaves it' "$P $Q " "$(pins_now)"

# --- Failing -------------------------------------------------------------

# One plugin's failure stops that plugin only.
fresh_case; history a/one main
compare a/one $P $T ahead
compare a/one $T main ahead
run
check 'an API failure fails the run' '1' "$st"
check '  ... reporting it for two.vim' 'error: cannot read the push history' "$(said two.vim)"
check '  ... while one.nvim is still decided' 'moved *' "$(said one.nvim)"
check '  ... and only one.nvim moves' "$T $Q " "$(pins_now)"

fresh_case; two_still
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" 'not json'
run
check 'a push history that cannot be parsed is an error, not a hold' \
  '1 error: cannot read the push history' "$st $(said one.nvim)"

fresh_case; two_still; history a/one main
run
check 'a pin that cannot be compared is an error' \
  '1 error: cannot compare the pin with main 7 days ago' "$st $(said one.nvim)"

fresh_case; two_still; history a/one main
compare a/one $P $T ahead
run
check 'a tip that cannot be checked against the branch is an error' \
  '1 error: cannot compare 5555555 with main' "$st $(said one.nvim)"
check '  ... and leaves it' "$P $Q " "$(pins_now)"

# In the lockfile, but lazy.nvim does not name it: removed from the specs, or
# lazy.nvim's list changed shape. Not skipped -- that would read as held.
fresh_case; two_still
plugins 'two.vim https://github.com/b/two.git'
run
check 'a plugin lazy.nvim does not list is an error' \
  '1 error: lazy.nvim does not list this plugin' "$st $(said one.nvim)"

fresh_case; two_still
plugins 'one.nvim https://gitlab.com/a/one.git' 'two.vim https://github.com/b/two.git'
run
check 'a plugin not on GitHub is an error' \
  '1 error: not a GitHub repository: https://gitlab.com/a/one.git' "$st $(said one.nvim)"

fresh_case
rm $GH_FIXTURES/nvim
run
check 'stops before any API call when lazy.nvim cannot be asked' \
  '1 *cannot ask lazy.nvim*' "$st $out"
check '  ... asking GitHub nothing' '' "$(cat $GH_FIXTURES/calls 2>/dev/null)"

fresh_case
print -r -- 'not json' > $LOCK
run
check 'stops before any API call when the lockfile cannot be read' \
  '1 *cannot read*lazy-lock.json*' "$st $out"
check '  ... asking GitHub nothing' '' "$(cat $GH_FIXTURES/calls 2>/dev/null)"

# The rewrite is a plain substitution, so the SHA must appear exactly once:
# two plugins pinned at one commit would both move.
fresh_case; history a/one main
compare a/one $P $T ahead
compare a/one $T main ahead
two_still
print -r -- "{
  \"one.nvim\": { \"branch\": \"main\", \"commit\": \"$P\" },
  \"two.vim\": { \"branch\": \"release\", \"commit\": \"$P\" }
}" > $LOCK
compare b/two $P $T behind
run
check 'refuses to rewrite a SHA that appears more than once' \
  "1 error: $P appears 2 times in lazy-lock.json, not once" "$st $(said one.nvim)"
check '  ... and leaves the file as it was' "$P $P " "$(pins_now)"

fresh_case; two_still; history a/one main
compare a/one $P $T ahead
compare a/one $T main ahead
mkdir $GH_FIXTURES/ro
mv $LOCK $GH_FIXTURES/ro/lazy-lock.json
LOCK=$GH_FIXTURES/ro/lazy-lock.json
before=$(cat $LOCK; print x)
chmod 555 $GH_FIXTURES/ro
run
chmod 755 $GH_FIXTURES/ro
check 'a lockfile that cannot be written is an error' \
  '1 error: cannot write lazy-lock.json' "$st $(said one.nvim)"
check '  ... leaving the file as it was' "${(b)before}" "$(cat $LOCK; print x)"

check 'refuses an unknown option' \
  '*usage*exit=2' \
  "$(PATH=$TMP/bin:$PATH zsh -f $TOOL --bogus 2>&1; print -r -- "exit=$?")"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
