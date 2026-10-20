#!/usr/bin/env zsh
# Unit tests for bin/go-cooldown. See bin/go-cooldown.md.
#
# Three stubs stand in for the network. gh answers each `gh api <endpoint>`
# from a file the case wrote and fails like a 404 for any other, as in
# lazy-cooldown's suite. go answers `go env GOPROXY` and `go list -m -json
# -versions <module>@latest` from files too. The module proxy is a directory:
# GOPROXY is a file:// URL, which curl reads like any other, so the tool's own
# fetch is what runs.
#
# Every case checks the tool's status and the module's own report line as
# well as the file: "unchanged" is also what a tool that never ran leaves.
#
# Run: zsh bin/go-cooldown.test.zsh   (exit 0 = pass)

set -u
zmodload zsh/datetime

TOOL=${0:A:h}/go-cooldown

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

TMP=$(mktemp -d "${TMPDIR:-/tmp}/go-cooldown-test.XXXXXX")
trap 'rm -rf $TMP' EXIT

mkdir -p $TMP/bin
print -r -- '#!/bin/sh
# gh api [flags] <endpoint>: answer from $GH_FIXTURES, keyed by the endpoint.
shift
for a; do case $a in -*) ;; *) ep=$a ;; esac; done
f=$GH_FIXTURES/$(printf %s "$ep" | tr "/?&=" "____")
if [ -f "$f" ]; then cat "$f"; else echo "gh: Not Found (HTTP 404) $ep" >&2; exit 1; fi' > $TMP/bin/gh
print -r -- '#!/bin/sh
# go env GOPROXY | go list -m -json -versions <module>@latest
case "$1 $2" in
  "env GOPROXY") printf "%s\n" "$FAKE_GOPROXY"; exit 0 ;;
  "list -m")
    for a; do m=$a; done
    f=$GH_FIXTURES/versions_$(printf %s "${m%@latest}" | tr "/" "_")
    [ -f "$f" ] && exec cat "$f"
    echo "go: module ${m%@latest}: not found" >&2; exit 1 ;;
esac
echo "go stub: unexpected: $*" >&2; exit 1' > $TMP/bin/go
chmod +x $TMP/bin/gh $TMP/bin/go

# Commits: P the pin's, then three releases after it.
P=1111111111111111111111111111111111111111
A=2222222222222222222222222222222222222222
B=3333333333333333333333333333333333333333
C=4444444444444444444444444444444444444444
T=5555555555555555555555555555555555555555 # the branch tip a week ago
L=9999999999999999999999999999999999999999 # the branch tip now

ago() { TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $(( EPOCHSECONDS - $1 * 86400 )); }

# fresh_case — a new fixture set, and a pin file holding the comment line, a
# module on its default branch at v1.0.0 (a/one), and a module of two
# packages on release branches at v1.2.0 (b/two). Every module has its
# versions, the proxy has every version's commit, and b/two stays put unless
# a case says otherwise.
typeset -i n=0
fresh_case() {
  export GH_FIXTURES=$TMP/case$(( ++n )) FAKE_GOPROXY=file://$TMP/case$n/proxy
  mkdir -p $GH_FIXTURES/proxy
  PINS=$GH_FIXTURES/go-tools.txt
  print -r -- "# <module> <version> <github repo> <branch> <package>...
example.com/one v1.0.0 a/one main example.com/one/cmd/one
example.com/two v1.2.0 b/two release-branch/{X.Y} example.com/two/cmd/x example.com/two/cmd/y" > $PINS
  versions example.com/one v0.9.0 v1.0.0 v1.1.0 v1.2.0-rc.1 v1.2.0 v1.3.0
  origin example.com/one v1.0.0 a/one $P
  origin example.com/one v1.1.0 a/one $A
  origin example.com/one v1.2.0 a/one $B
  origin example.com/one v1.3.0 a/one $C
  versions example.com/two v1.2.0
  origin example.com/two v1.2.0 b/two $P
}

# versions <module> <version>... — what `go list -m -versions` reports.
versions() {
  local m=$1; shift
  print -r -- "{\"Path\":\"$m\",\"Versions\":[${(j:,:)${(qqq)@}}]}" > $GH_FIXTURES/versions_${m//\//_}
}

# origin <module> <version> <owner/repo> <sha> — the proxy's .info.
origin() {
  mkdir -p $GH_FIXTURES/proxy/$1/@v
  print -r -- "{\"Version\":\"$2\",\"Time\":\"2001-01-01T00:00:00Z\",\"Origin\":{\"VCS\":\"git\",\"URL\":\"https://github.com/$3\",\"Hash\":\"$4\",\"Ref\":\"refs/tags/$2\"}}" \
    > $GH_FIXTURES/proxy/$1/@v/$2.info
}

serve() { print -r -- "$2" > $GH_FIXTURES/${${1//[\/?&=]/_}}; }

# history <owner/repo> <branch> — pushed to 10 days ago (tip then: T) and 2
# days ago (tip now: L).
history() {
  serve "repos/$1/activity?ref=refs/heads/$2&per_page=100" \
    '[{"timestamp":"'$(ago 2)'","after":"'$L'"},{"timestamp":"'$(ago 10)'","after":"'$T'"}]'
}

# compare <owner/repo> <base> <head> <status>
compare() { serve "repos/$1/compare/$2...$3" '{"status":"'$4'"}'; }

run() {
  out=$(PATH=$TMP/bin:$PATH zsh -f $TOOL "$@" $PINS 2>&1)
  st=$?
}

said() { local l=${(M)${(f)out}:#$1: *}; print -r -- "${l#$1: }"; }

file_now() { cat $PINS; print x; }

# --- Moving --------------------------------------------------------------

# v1.3.0 is newer than the tip of a week ago; v1.2.0 was on it. The release
# candidate between them is not a release.
fresh_case; history a/one main
compare a/one $C $T behind
compare a/one $B $T ahead
before=$(file_now)
run
check 'moves to the newest release that was on its branch a week ago' \
  "0 moved v1.0.0..v1.2.0 \(on main 7 days ago\) https://github.com/a/one/compare/$P...$B" \
  "$st $(said example.com/one)"
check '  ... rewriting that version and nothing else in the file' \
  "${(b)${before/one v1.0.0 /one v1.2.0 }}" "$(file_now)"
check '  ... leaving no temporary file behind' '' "$(print -l -- $GH_FIXTURES/*.cooldown(N))"

fresh_case; history a/one main
compare a/one $C $T identical
run
check 'a release that is the tip of a week ago counts as on it' \
  '0 moved v1.0.0..v1.3.0 *' "$st $(said example.com/one)"

# Never back to v0.9.0, and never to v1.0.0 itself, whatever their commits.
fresh_case; history a/one main
compare a/one $C $T diverged
compare a/one $B $T behind
compare a/one $A $T behind
run
check 'holds when no release after the pin was on its branch a week ago' \
  '0 stays: no release after v1.0.0 was on its branch 7 days ago' "$st $(said example.com/one)"
check '  ... and the file is as it was' "*example.com/one v1.0.0 *" "$(file_now)"

# A blank line of spaces too, which go-tools-install skips the same way: a
# file one of them accepts, the other must not reject.
fresh_case
versions example.com/one v0.9.0 v1.0.0 v1.1.0-pre
printf '  \n' >> $PINS
run
check 'up to date when no release follows the pin, a pre-release aside' \
  '0 up to date \(v1.0.0\)' "$st $(said example.com/one)"

# The cutoff: with --days 1 the push of 2 days ago is the tip to compare with.
fresh_case; history a/one main
compare a/one $C $L ahead
run --days 1
check '--days moves the cutoff' \
  '0 moved v1.0.0..v1.3.0 \(on main 1 days ago\)*' "$st $(said example.com/one)"

# The proxy protocol spells a capital as ! and its lower case, so a module
# with one is read from example.com/!upper; read as written, it is not found.
fresh_case; history a/one main
compare a/one $C $T ahead
versions example.com/one v1.0.0
print -r -- "example.com/Upper v1.0.0 a/one main example.com/Upper" >> $PINS
versions example.com/Upper v1.0.0 v1.1.0
mkdir -p $GH_FIXTURES/proxy/example.com/!upper/@v
print -r -- "{\"Version\":\"v1.0.0\",\"Origin\":{\"URL\":\"https://github.com/a/one\",\"Hash\":\"$P\"}}" \
  > $GH_FIXTURES/proxy/example.com/!upper/@v/v1.0.0.info
print -r -- "{\"Version\":\"v1.1.0\",\"Origin\":{\"URL\":\"https://github.com/a/one\",\"Hash\":\"$C\"}}" \
  > $GH_FIXTURES/proxy/example.com/!upper/@v/v1.1.0.info
run
check 'reads a module with a capital from the proxy in its escaped form' \
  '0 moved v1.0.0..v1.1.0 *' "$st $(said example.com/Upper)"

# GitHub names are not case-sensitive, and a URL may end in .git.
fresh_case; history a/one main
compare a/one $C $T ahead
origin example.com/one v1.3.0 A/One.git $C
run
check 'takes a release from the same repository, spelt in another case or with .git' \
  '0 moved v1.0.0..v1.3.0 *' "$st $(said example.com/one)"

# golang.org/x/tools comes from go.googlesource.com: its GitHub mirror is asked.
fresh_case; history a/one main
compare a/one $C $T ahead
print -r -- "{\"Version\":\"v1.3.0\",\"Origin\":{\"URL\":\"https://go.googlesource.com/one\",\"Hash\":\"$C\"}}" \
  > $GH_FIXTURES/proxy/example.com/one/@v/v1.3.0.info
run
check 'takes a release from outside GitHub, asking the repository the line names' \
  '0 moved v1.0.0..v1.3.0 *' "$st $(said example.com/one)"

# --- A release branch -----------------------------------------------------

# Each release's branch is named from its own major.minor: v1.4.0's branch is
# a day old, so it has no tip a week ago; v1.3.1 was on release-branch/1.3.
fresh_case
versions example.com/one v1.0.0
versions example.com/two v1.2.0 v1.3.0 v1.3.1 v1.4.0
origin example.com/two v1.3.0 b/two $A
origin example.com/two v1.3.1 b/two $B
origin example.com/two v1.4.0 b/two $C
serve "repos/b/two/activity?ref=refs/heads/release-branch/1.4&per_page=100" \
  '[{"timestamp":"'$(ago 1)'","after":"'$C'"}]'
history b/two release-branch/1.3
compare b/two $B $T ahead
run
check 'gates each release on the branch its version names' \
  "0 moved v1.2.0..v1.3.1 \(on release-branch/1.3 7 days ago\) https://github.com/b/two/compare/$P...$B" \
  "$st $(said example.com/two)"
check '  ... keeping both packages on the line' \
  '*example.com/two v1.3.1 b/two release-branch/{X.Y} example.com/two/cmd/x example.com/two/cmd/y*' \
  "$(file_now)"

fresh_case
versions example.com/one v1.0.0
versions example.com/two v1.2.0 v1.3.0
origin example.com/two v1.3.0 b/two $A
serve "repos/b/two/activity?ref=refs/heads/release-branch/1.3&per_page=100" \
  '[{"timestamp":"'$(ago 10)'","after":"0000000000000000000000000000000000000000"}]'
run
check 'a branch deleted by the cutoff holds no release' \
  '0 stays: no release after v1.2.0 was on its branch 7 days ago' "$st $(said example.com/two)"

# --- Failing ------------------------------------------------------------

fresh_case; history a/one main
origin example.com/one v1.3.0 c/elsewhere $C
before=$(file_now)
run
check 'fails a release the proxy got from another repository' \
  '1 error: v1.3.0 comes from https://github.com/c/elsewhere, not github.com/a/one' \
  "$st $(said example.com/one)"
check '  ... and the file is as it was' "${(b)before}" "$(file_now)"
check '  ... while the other modules are still decided' 'up to date \(v1.2.0\)' "$(said example.com/two)"

fresh_case
print -r -- '{"Version":"v1.3.0","Time":"2001-01-01T00:00:00Z"}' > $GH_FIXTURES/proxy/example.com/one/@v/v1.3.0.info
run
check 'fails a release the proxy records no commit for' \
  '1 error: the proxy records no commit for v1.3.0' "$st $(said example.com/one)"

fresh_case
command rm $GH_FIXTURES/proxy/example.com/one/@v/v1.3.0.info
run
check 'fails when the proxy cannot be read' \
  '1 error: cannot read v1.3.0 from the proxy' "$st $(said example.com/one)"

# The pin's own commit is read only for the compare URL, once a release has
# passed; a pin the proxy cannot vouch for still stops the move.
fresh_case; history a/one main
compare a/one $C $T ahead
command rm $GH_FIXTURES/proxy/example.com/one/@v/v1.0.0.info
before=$(file_now)
run
check 'fails when the pin cannot be read from the proxy' \
  '1 error: cannot read v1.0.0 from the proxy' "$st $(said example.com/one)"
check '  ... and the file is as it was' "${(b)before}" "$(file_now)"

fresh_case; history a/one main
compare a/one $C $T ahead
print -r -- '{"Version":"v1.0.0"}' > $GH_FIXTURES/proxy/example.com/one/@v/v1.0.0.info
run
check 'fails a pin the proxy records no commit for' \
  '1 error: the proxy records no commit for v1.0.0' "$st $(said example.com/one)"

fresh_case
versions example.com/one v1.1.0 v1.2.0
run
check 'fails a pin that is not a listed release (retracted?)' \
  '1 error: v1.0.0 is not among the released versions \(retracted\?\)' "$st $(said example.com/one)"

fresh_case
command rm $GH_FIXTURES/versions_example.com_one
run
check 'fails when the versions cannot be listed' \
  '1 error: cannot list the versions' "$st $(said example.com/one)"

fresh_case
run
check 'fails when the push history cannot be read' \
  '1 error: cannot read the push history of main' "$st $(said example.com/one)"

fresh_case; history a/one main
run
check 'fails when a release cannot be compared with its branch' \
  '1 error: cannot compare v1.3.0 with main 7 days ago' "$st $(said example.com/one)"

fresh_case; history a/one main
compare a/one $C $T ahead
print -r -- "# was: example.com/one v1.0.0 a/one main" >> $PINS
before=$(file_now)
run
check 'fails a pin that appears twice, rewriting nothing' \
  '1 error: "example.com/one v1.0.0 " appears 2 times in go-tools.txt, not once' \
  "$st $(said example.com/one)"
check '  ... and the file is as it was' "${(b)before}" "$(file_now)"

# As root the directory's mode is ignored and the write succeeds: skip there
# rather than report a bug that does not exist (.claude/rules/testing.md).
if (( EUID )); then
  fresh_case; history a/one main
  compare a/one $C $T ahead
  chmod 500 $GH_FIXTURES
  before=$(file_now)
  run
  chmod 700 $GH_FIXTURES
  check 'fails when the file cannot be written' \
    '1 error: cannot write go-tools.txt' "$st $(said example.com/one)"
  check '  ... and the file is as it was' "${(b)before}" "$(file_now)"
else
  print 'skip a file that cannot be written: running as root'
fi

fresh_case
out=$(PATH=$TMP/bin:$PATH zsh -f $TOOL $GH_FIXTURES/none.txt 2>&1); st=$?
check 'fails a file it cannot read' "1 *go-cooldown: cannot read $GH_FIXTURES/none.txt" "$st $out"

fresh_case; FAKE_GOPROXY=direct
run
check 'refuses to run without a proxy to read' \
  '1 go-cooldown: GOPROXY is "direct"; a module proxy is needed to read what was published' \
  "$st $out"

fresh_case
print -r -- "example.com/one v1.0.0 a/one" > $PINS
run
check 'fails a line it cannot read, naming it' \
  '1 go-cooldown: go-tools.txt line 1 is not <module> <version> <repo> <branch> <package>...' \
  "$st $out"

out=$(zsh -f $TOOL --days 2>&1); st=$?
check 'a usage error exits 2' '2 usage: *' "$st $out"

(( failures == 0 )) && print '\nall tests passed' || print "\n$failures test(s) failed"
(( failures == 0 ))
