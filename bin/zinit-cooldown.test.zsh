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
# So every case checks the tool's report as well as the file.
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
# a/one at P.
fresh_case() {
  export GH_FIXTURES=$TMP/case$(( ++n ))
  mkdir -p $GH_FIXTURES
  PLUGIN=$GH_FIXTURES/plugin.zsh
  print -r -- "_zinit_repo=z/zinit
_zinit_pin=$Z
zinit ice ver\"$P\"
zinit light a/one" > $PLUGIN
}
typeset -i n=0

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

# run_tool [args...] — prints exit=<status>, the report, then the plugin.zsh pins.
# zsh -f, because through its `env zsh` shebang the tool would read ~/.zshenv,
# which rebuilds PATH and puts the real gh ahead of the stub: the first run of
# this suite asked GitHub about repos/z/zinit.
run_tool() {
  local out
  out=$(PATH=$TMP/bin:$PATH zsh -f $TOOL "$@" $PLUGIN 2>&1)
  print -r -- "exit=$?"
  print -r -- "$out"
  print -r -- "--- pins"
  grep -o '[[:xdigit:]]\{40\}' $PLUGIN
}

pins_now() { grep -o '[[:xdigit:]]\{40\}' $PLUGIN | tr '\n' ' '; }

# --- Moving --------------------------------------------------------------

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead   # in the branch as it was a week ago
compare a/one $P $N ahead   # and past the pin
got=$(run_tool)
check 'moves a pin to a release tag that was on the branch a week ago' \
  "exit=0*a/one*moved*v2*https://github.com/a/one/compare/$P...$N*" "$got"
check '  ... and rewrites that SHA in plugin.zsh' "$Z $N " "$(pins_now)"

# The newest tag fails the gate (tagged after the cutoff, or moved onto a
# commit main did not have), so the next one is taken.
fresh_case; zinit_still; repo_basics a/one
releases a/one v3 v2
tag_at a/one v3 $M
compare a/one $M $T diverged
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
got=$(run_tool)
check 'skips a tag whose commit was not on the branch a week ago' \
  '*a/one*moved*v2*' "$got"
check '  ... landing on the newest tag that passes' "$Z $N " "$(pins_now)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T identical # the tag IS the tip of a week ago
compare a/one $P $N ahead
check 'a tag at exactly the branch tip of a week ago passes' \
  "$Z $N " "$(run_tool >/dev/null; pins_now)"

# Without releases, tags are taken newest version first: 0.10 after 0.9.
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[]'
serve "repos/a/one/tags?per_page=100" '[{"name":"0.9.0"},{"name":"0.10.0"},{"name":"0.2.0"}]'
tag_at a/one 0.10.0 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
got=$(run_tool)
check 'without releases, takes the highest version tag' '*a/one*moved*0.10.0*' "$got"

# Drafts and pre-releases are not releases.
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[
  {"tag_name":"v3-rc1","draft":false,"prerelease":true},
  {"tag_name":"v3","draft":true,"prerelease":false},
  {"tag_name":"v2","draft":false,"prerelease":false}]'
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
got=$(run_tool)
check 'passes over drafts and pre-releases' '*a/one*moved*v2*' "$got"

# zinit's own pin is a plain assignment, and moves the same way.
fresh_case; repo_basics z/zinit; repo_basics a/one
releases z/zinit v9
tag_at z/zinit v9 $M
compare z/zinit $M $T ahead
compare z/zinit $Z $M ahead
releases a/one v2
tag_at a/one v2 $P # already there
compare a/one $P $T ahead
got=$(run_tool)
check 'moves zinit'"'"'s own pin' '*z/zinit*moved*v9*' "$got"
check '  ... rewriting _zinit_pin' "$M $P " "$(pins_now)"

# --- Holding -------------------------------------------------------------

# The pin itself must pass the gate to count as up to date.
fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $P
compare a/one $P $T ahead
got=$(run_tool)
check 'a pin at the newest eligible tag is reported up to date' \
  'exit=0*a/one*up to date*v2*' "$got"
check '  ... and left alone' "$Z $P " "$(pins_now)"

# Forward only: a tag behind the pin is reported, never moved back to.
fresh_case; zinit_still; repo_basics a/one
releases a/one v1
tag_at a/one v1 $O
compare a/one $O $T ahead
compare a/one $P $O behind
got=$(run_tool)
check 'never moves a pin back to an older tag, but names it' \
  "exit=0*a/one*stays*v1*$O*behind*" "$got"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N diverged
check 'never moves to a tag that is not a descendant of the pin' \
  "$Z $P " "$(run_tool >/dev/null; pins_now)"

fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T diverged
got=$(run_tool)
check 'holds a repo when no tag passes the gate' "exit=0*a/one*stays*no release tag*7 days*" "$got"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/releases?per_page=20" '[]'
serve "repos/a/one/tags?per_page=100" '[]'
got=$(run_tool)
check 'holds a repo with no tags at all, saying so' "exit=0*a/one*stays*no tags*" "$got"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# Every push GitHub reports is newer than the cutoff: what the branch held a
# week ago is unknown, so nothing can pass.
fresh_case; zinit_still
serve repos/a/one '{"default_branch":"main"}'
serve "repos/a/one/activity?ref=refs/heads/main&per_page=100" '[{"timestamp":"'$(ago 2)'","after":"'$N'"}]'
releases a/one v2
tag_at a/one v2 $N
got=$(run_tool)
check 'holds a repo whose push history does not reach back a week' \
  "exit=0*a/one*stays*no push*" "$got"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

# --days moves the cutoff: the 2-day-old push is the gate's tip at --days 1.
fresh_case; zinit_still; repo_basics a/one
releases a/one v2
tag_at a/one v2 $N
compare a/one $N 9999999999999999999999999999999999999999 ahead
compare a/one $N $T diverged
compare a/one $P $N ahead
check '--days sets the cutoff' "*a/one*moved*v2*" "$(run_tool --days 1)"

# --- Failing -------------------------------------------------------------

# One repo's API failure stops that repo only, and the run reports failure.
fresh_case; repo_basics a/one
print -r -- "zinit ice ver\"$O\"
zinit light b/two" >> $PLUGIN
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
# z/zinit and b/two: nothing served, every call 404s.
got=$(run_tool)
check 'an API failure fails the run, naming the repo' "exit=1*z/zinit*error*" "$got"
check '  ... and the other repos are still processed' "$Z $N $O " "$(pins_now)"

# Releases that cannot be read are an error, not "no releases": falling back
# to the tags would decide by a different rule without anyone choosing it.
fresh_case; zinit_still; repo_basics a/one
serve "repos/a/one/tags?per_page=100" '[{"name":"v2"}]'
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
got=$(run_tool)
check 'a release list that cannot be read fails the repo, not falls back to tags' \
  "exit=1*a/one*error*tags*" "$got"
check '  ... and leaves it' "$Z $P " "$(pins_now)"

fresh_case
print -r -- 'zinit light b/unpinned' >> $PLUGIN
got=$(run_tool)
check 'stops before any API call when the pins cannot be read' \
  "exit=1*b/unpinned*" "$got"
check '  ... asking GitHub nothing' '' "$(cat $GH_FIXTURES/calls 2>/dev/null)"

# The rewrite is a plain substitution of the SHA, so it must name one line.
fresh_case; zinit_still; repo_basics a/one
print -r -- "# was on $P before" >> $PLUGIN
releases a/one v2
tag_at a/one v2 $N
compare a/one $N $T ahead
compare a/one $P $N ahead
got=$(run_tool)
check 'refuses to rewrite a SHA that appears more than once' \
  "exit=1*a/one*$P*2 times*" "$got"
check '  ... and leaves the file as it was' "$Z $P $P " "$(pins_now)"

check 'refuses an unknown option' \
  '*usage*exit=2' \
  "$(PATH=$TMP/bin:$PATH zsh -f $TOOL --bogus 2>&1; print -r -- "exit=$?")"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
