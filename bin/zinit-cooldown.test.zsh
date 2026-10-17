#!/usr/bin/env zsh
# Unit tests for bin/zinit-cooldown. See bin/zinit-cooldown.md.
#
# GitHub is a gh first on PATH that answers each `gh api <endpoint>` from a
# file the case wrote, and fails like a 404 for any endpoint it was not given
# -- so a case that forgot one fails loudly instead of the tool deciding on
# nothing. Timestamps are written relative to the real clock, which keeps the
# tool free of a test-only way to set the time.
#
# Most expectations are about what did NOT move: a pin the gate holds back is
# the whole point, and "unchanged" is also what a tool that never ran leaves.
# So every case checks the tool's status and the repository's own report line
# as well as the file. Lines are matched one at a time: a pattern over the
# whole report would let one repo's verdict stand in for another's.
#
# Run: zsh bin/zinit-cooldown.test.zsh   (exit 0 = pass)

set -u
zmodload zsh/datetime

TOOL=${0:A:h}/zinit-cooldown

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

TMP=$(mktemp -d "${TMPDIR:-/tmp}/zinit-cooldown-test.XXXXXX")
trap 'rm -rf $TMP' EXIT

mkdir -p $TMP/bin
print -r -- '#!/bin/sh
# gh api [flags] <endpoint>: answer from $GH_FIXTURES, keyed by the endpoint.
shift
for a; do case $a in -*) ;; *) ep=$a ;; esac; done
f=$GH_FIXTURES/$(printf %s "$ep" | tr "/?&=" "____")
printf "%s\n" "$ep" >> "$GH_FIXTURES/calls"
if [ -f "$f" ]; then cat "$f"; else echo "gh: Not Found (HTTP 404) $ep" >&2; exit 1; fi' > $TMP/bin/gh
chmod +x $TMP/bin/gh

# SHAs: P the pin, then commits newer and older than it.
Z=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
P=1111111111111111111111111111111111111111
N=2222222222222222222222222222222222222222
M=3333333333333333333333333333333333333333
O=4444444444444444444444444444444444444444
T=5555555555555555555555555555555555555555 # the branch tip a week ago

# ago <days> — an ISO timestamp that many days before now, as GitHub writes it.
ago() { TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $(( EPOCHSECONDS - $1 * 86400 )); }

# fresh_case — a new fixture set and a plugin.zsh pinning zinit at Z and
# a/one at P. It ends in a blank line and carries a comment, so a rewrite that
# touched more than the SHA shows in the whole-file comparison.
typeset -i n=0
fresh_case() {
  export GH_FIXTURES=$TMP/case$(( ++n ))
  mkdir -p $GH_FIXTURES
  PLUGIN=$GH_FIXTURES/plugin.zsh
  print -r -- "_zinit_repo=z/zinit
_zinit_pin=$Z
# the one plugin
zinit ice wait lucid ver\"$P\"
zinit light a/one
" > $PLUGIN
}

# serve <endpoint> <json>
serve() { print -r -- "$2" > $GH_FIXTURES/${${1//[\/?&=]/_}}; }

# repo_basics <owner/repo> — default branch main, pushed to 10 days ago (tip
# then: T) and 2 days ago.
repo_basics() {
  serve "repos/$1" '{"default_branch":"main"}'
  serve "repos/$1/activity?ref=refs/heads/main&per_page=100" \
    '[{"timestamp":"'$(ago 2)'","after":"9999999999999999999999999999999999999999"},
      {"timestamp":"'$(ago 10)'","after":"'$T'"}]'
}

# releases <owner/repo> <tag>... — published releases, newest first.
releases() {
  local repo=$1; shift
  serve "repos/$repo/releases?per_page=20" \
    "[$(for t; do print -rn -- '{"tag_name":"'$t'","draft":false,"prerelease":false},'; done | sed 's/,$//')]"
}

# tag_at <owner/repo> <tag> <sha>
tag_at() { serve "repos/$1/commits/$2" '{"sha":"'$3'"}'; }

# compare <owner/repo> <base> <head> <status>
compare() { serve "repos/$1/compare/$2...$3" '{"status":"'$4'"}'; }

# zinit itself held where it is in every case that is not about it: no tags.
zinit_still() {
  serve repos/z/zinit '{"default_branch":"main"}'
  serve "repos/z/zinit/activity?ref=refs/heads/main&per_page=100" '[{"timestamp":"'$(ago 10)'","after":"'$T'"}]'
  serve "repos/z/zinit/releases?per_page=20" '[]'
  serve "repos/z/zinit/tags?per_page=100" '[]'
}

# run [args...] — run the tool on the case's plugin.zsh; sets $st (status) and
# $out (the report). zsh -f, because through its `env zsh` shebang the tool
# would read ~/.zshenv, which rebuilds PATH and puts the real gh ahead of the
# stub: the first run of this suite asked GitHub about repos/z/zinit.
run() {
  out=$(PATH=$TMP/bin:$PATH zsh -f $TOOL "$@" $PLUGIN 2>&1)
  st=$?
}

# said <owner/repo> — the report's line for that repository, without the name.
said() { local l=${(M)${(f)out}:#$1: *}; print -r -- "${l#$1: }"; }

pins_now() { grep -o '[[:xdigit:]]\{40\}' $PLUGIN | tr '\n' ' '; }

# --- Moving --------------------------------------------------------------

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead   # in the branch as it was a week ago
compare a/one $P $N ahead   # and past the pin
before=$(<$PLUGIN; print x)
run
check 'moves a pin to a release tag that was on the branch a week ago' \
  "0 moved 1111111..2222222 \(v2\) https://github.com/a/one/compare/$P...$N" "$st $(said a/one)"
check '  ... rewriting that SHA and nothing else in plugin.zsh' \
  "${(b)${before//$P/$N}}" "$(<$PLUGIN; print x)"

# The case the cooldown exists for: the newest release is on a commit that
# reached main after the cutoff. Compared against the tip of a week ago, that
# commit is ahead of it -- GitHub says the tip is "behind" the tag -- and it
# must not pass.
fresh_case; zinit_still; repo_basics a/one
releases a/one v3 v2
tag_at a/one v3 $M
compare a/one $M $T behind
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'skips a tag on a commit that reached main after the cutoff' \
  '0 moved *\(v2\)*' "$st $(said a/one)"
check '  ... landing on the older release that was there' "$Z $N " "$(pins_now)"

# The newest tag fails the gate the other way -- moved onto a commit main
# never had -- so the next one is taken.
fresh_case; zinit_still; repo_basics a/one
releases a/one v3 v2
tag_at a/one v3 $M
compare a/one $M $T diverged
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'skips a tag whose commit was not on the branch a week ago' \
  '0 moved *\(v2\)*' "$st $(said a/one)"
check '  ... landing on the newest tag that passes' "$Z $N " "$(pins_now)"

# Two releases both pass: the newer is taken. The older one's comparison
# with the pin is not served, so reaching for it fails on the 404.
fresh_case; zinit_still; repo_basics a/one
releases a/one v3 v2
tag_at a/one v3 $M
compare a/one $M $T ahead
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $M ahead
run
check 'of releases that all pass, takes the newest' \
  '0 moved *\(v3\)*' "$st $(said a/one)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T identical # the tag IS the tip of a week ago
compare a/one $P $N ahead
run
check 'a tag at exactly the branch tip of a week ago passes' \
  '0 moved *\(v2\)*' "$st $(said a/one)"

# Without releases, tags are taken newest version first: 0.10 after 0.9.
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[]'
serve "repos/a/one/tags?per_page=100" '[{"name":"0.9.0"},{"name":"0.10.0"},{"name":"0.2.0"}]'
tag_at a/one 0.10.0 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'without releases, takes the highest version tag' \
  '0 moved *\(0.10.0\)*' "$st $(said a/one)"

# Drafts and pre-releases are not releases.
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[
  {"tag_name":"v3-rc1","draft":false,"prerelease":true},
  {"tag_name":"v3","draft":true,"prerelease":false},
  {"tag_name":"v2","draft":false,"prerelease":false}]'
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'passes over drafts and pre-releases' '0 moved *\(v2\)*' "$st $(said a/one)"

# zinit's own pin is a plain assignment, and moves the same way.
fresh_case; repo_basics z/zinit; repo_basics a/one
releases z/zinit v9
tag_at z/zinit v9 $M
compare z/zinit $M $T ahead
compare z/zinit $Z $M ahead
releases a/one v2
tag_at a/one v2 $P # already there
compare a/one $P $T ahead
run
check 'moves zinit'"'"'s own pin' '0 moved *\(v9\)*' "$st $(said z/zinit)"
check '  ... rewriting _zinit_pin' "$M $P " "$(pins_now)"

# Two pins move in one run: the second rewrite must start from the file the
# first one left, or the first move is lost.
fresh_case; repo_basics z/zinit; repo_basics a/one
releases z/zinit v9
tag_at z/zinit v9 $M
compare z/zinit $M $T ahead
compare z/zinit $Z $M ahead
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'moves two pins in one run' '0' "$st"
check '  ... and both moves are in the file' "$M $N " "$(pins_now)"
check '  ... leaving no temporary file behind' '' "$(print -l -- $GH_FIXTURES/*.cooldown(N))"

# --- Holding -------------------------------------------------------------

# The pin itself must pass the gate to count as up to date.
fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $P
compare a/one $P $T ahead
run
check 'a pin at the newest eligible tag is reported up to date' \
  '0 up to date \(v2\)' "$st $(said a/one)"
check '  ... and left alone' "$Z $P " "$(pins_now)"

# Forward only: a tag behind the pin is reported, never moved back to.
fresh_case; zinit_still; repo_basics a/one
releases a/one v1
tag_at a/one v1 $O
compare a/one $O $T ahead
compare a/one $P $O behind
run
check 'never moves a pin back to an older tag, but names it' \
  "0 stays: v1 \($O\) is behind the pin*" "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N diverged
run
check 'never moves to a tag that is not a descendant of the pin' \
  "0 stays: v2 \($N\) is diverged*" "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T diverged
run
check 'holds a repo when no tag passes the gate' \
  '0 stays: no release tag was on main 7 days ago' "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[]'
serve "repos/a/one/tags?per_page=100" '[]'
run
check 'holds a repo with no tags at all, saying so' '0 stays: no tags' "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# Releases exist but none is published: the repo publishes its versions as
# releases, so its bare tags (here a pre-release's) are not taken instead.
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[{"tag_name":"v3-rc1","draft":false,"prerelease":true}]'
serve "repos/a/one/tags?per_page=100" '[{"name":"v3-rc1"}]'
tag_at a/one v3-rc1 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'holds a repo whose releases are all drafts or pre-releases' \
  '0 stays: no published release' "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# Every push GitHub reports is newer than the cutoff: what the branch held a
# week ago is unknown, so nothing can pass.
fresh_case; zinit_still
serve repos/a/one '{"default_branch":"main"}'
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" '[{"timestamp":"'$(ago 2)'","after":"'$N'"}]'
releases a/one v2
tag_at a/one v2 $N
run
check 'holds a repo whose push history does not reach back a week' \
  '0 stays: no push to main older than 7 days on record' "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# The 7 days themselves: pushes a day either side of the cutoff, and only the
# 8-day-old tip is served. A cutoff computed short of 7 days picks the 6-day
# one, whose compare is not served, and the case fails on the 404.
fresh_case; zinit_still
X6=6666666666666666666666666666666666666666
X8=8888888888888888888888888888888888888888
serve repos/a/one '{"default_branch":"main"}'
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" \
  '[{"timestamp":"'$(ago 6)'","after":"'$X6'"},{"timestamp":"'$(ago 8)'","after":"'$X8'"}]'
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $X8 ahead
compare a/one $P $N ahead
run
check 'the cutoff is 7 days: the gate tip is the push 8 days ago, not 6' \
  '0 moved *\(v2\)*' "$st $(said a/one)"

# The gate reads the repository's own default branch, which for many zsh
# plugins is master. Only master's log is served, so reading main's 404s.
fresh_case; zinit_still
serve repos/a/one '{"default_branch":"master"}'
serve "repos/a/one/activity?ref=refs/heads/master&per_page=100" '[{"timestamp":"'$(ago 10)'","after":"'$T'"}]'
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T diverged
run
check 'gates on the default branch, whatever it is called' \
  '0 stays: no release tag was on master 7 days ago' "$st $(said a/one)"

# --days moves the cutoff: the 2-day-old push is the gate's tip at --days 1.
fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N 9999999999999999999999999999999999999999 ahead
compare a/one $N $T diverged
compare a/one $P $N ahead
run --days 1
check '--days sets the cutoff' '0 moved *\(v2\)*' "$st $(said a/one)"

# --- Failing -------------------------------------------------------------

# One repo's failure stops that repo only, and the run reports failure.
fresh_case; repo_basics a/one
print -r -- "zinit ice ver\"$O\"
zinit light b/two" >> $PLUGIN
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
releases b/two v1 # b/two: releases served, the repository itself is not
# z/zinit: nothing served, every call 404s.
run
check 'an API failure fails the run' '1' "$st"
check '  ... reporting it for zinit' 'error: cannot read the repository' "$(said z/zinit)"
check '  ... and for b/two' 'error: cannot read the repository' "$(said b/two)"
check '  ... while a/one is still decided' 'moved *\(v2\)*' "$(said a/one)"
check '  ... and only a/one moves' "$Z $N $O " "$(pins_now)"

# The same promise from inside the tag loop, which leaves two loops at once:
# zinit, first, fails resolving its tag, and a/one after it is still decided.
fresh_case; repo_basics z/zinit; repo_basics a/one
releases z/zinit v9 # commits/v9 not served
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'a failure inside the tag loop fails the run' '1' "$st"
check '  ... reporting it for zinit' 'error: cannot resolve v9' "$(said z/zinit)"
check '  ... while a/one after it is still decided' 'moved *\(v2\)*' "$(said a/one)"

# Not "no history": a log that cannot be read must not pass for an empty one.
fresh_case; zinit_still
serve repos/a/one '{"default_branch":"main"}'
releases a/one v2
run
check 'a push history that cannot be read is an error, not a hold' \
  '1 error: cannot read the push history' "$st $(said a/one)"

# Fetched, but not a log: the same error, not an empty history.
fresh_case; zinit_still
serve repos/a/one '{"default_branch":"main"}'
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" 'not json'
releases a/one v2
run
check 'a push history that cannot be parsed is an error, not a hold' \
  '1 error: cannot read the push history' "$st $(said a/one)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
run
check 'a tag that cannot be resolved is an error' \
  '1 error: cannot resolve v2' "$st $(said a/one)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
run
check 'a gate that cannot be checked is an error' \
  '1 error: cannot compare v2*' "$st $(said a/one)"

# The last comparison, against the pin: failing it must not read as "behind".
fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
run
check 'a pin that cannot be compared with the tag is an error' \
  '1 error: cannot compare the pin with v2' "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# Releases that cannot be read are an error, not "no releases": falling back
# to the tags would decide by a different rule without anyone choosing it.
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/tags?per_page=100" '[{"name":"v2"}]'
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'a release list that cannot be read fails the repo, not falls back to tags' \
  '1 error: cannot list the releases' "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# No releases, and the tag list cannot be read: an error, not "no tags".
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[]'
run
check 'a tag list that cannot be read is an error, not a hold' \
  '1 error: cannot list the tags' "$st $(said a/one)"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# A write that fails leaves the old file whole. plugin.zsh goes in a directory
# of its own, made read-only, so the temporary file cannot be created there
# either; the stub keeps writing its log beside the fixtures.
fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
mkdir $GH_FIXTURES/ro
mv $PLUGIN $GH_FIXTURES/ro/plugin.zsh
PLUGIN=$GH_FIXTURES/ro/plugin.zsh
before=$(cat $PLUGIN; print x)
chmod 555 $GH_FIXTURES/ro
run
chmod 755 $GH_FIXTURES/ro
check 'a plugin.zsh that cannot be written is an error' \
  '1 error: cannot write plugin.zsh' "$st $(said a/one)"
check '  ... leaving the file as it was' "${(b)before}" "$(cat $PLUGIN; print x)"
check '  ... and no temporary file' '' "$(print -l -- $GH_FIXTURES/ro/*.cooldown(N))"

fresh_case
print -r -- 'zinit light b/unpinned' >> $PLUGIN
run
check 'stops before any API call when the pins cannot be read' \
  "1 *b/unpinned*" "$st $out"
check '  ... asking GitHub nothing' '' "$(cat $GH_FIXTURES/calls 2>/dev/null)"

# The rewrite is a plain substitution of the SHA, so it must name one line.
fresh_case; zinit_still; repo_basics a/one
print -r -- "# was on $P before" >> $PLUGIN
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'refuses to rewrite a SHA that appears more than once' \
  "1 error: $P appears 2 times in plugin.zsh, not once" "$st $(said a/one)"
check '  ... and leaves the file as it was' "$Z $P $P " "$(pins_now)"

# Counted by occurrence, not by line: a comment on the pin's own line that
# quotes it would otherwise leave the old SHA behind after the rewrite.
fresh_case; zinit_still; repo_basics a/one
print -r -- "_zinit_repo=z/zinit
_zinit_pin=$Z
zinit ice ver\"$P\" # was $P
zinit light a/one" > $PLUGIN
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
run
check 'refuses a SHA that appears twice on one line' \
  "1 error: $P appears 2 times in plugin.zsh, not once" "$st $(said a/one)"

check 'refuses an unknown option' \
  '*usage*exit=2' \
  "$(PATH=$TMP/bin:$PATH zsh -f $TOOL --bogus 2>&1; print -r -- "exit=$?")"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
