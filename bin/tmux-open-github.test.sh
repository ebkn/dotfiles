#!/bin/bash
# tmux-open-github.test.sh -- the URL it picks and where it sends it.
# See bin/tmux-open-github.md. gh, tmux, open and xdg-open are stubs on PATH,
# so no real tmux is started and no browser opens. The binding that calls it
# is pressed in bin/tmux-conf.test.sh.
# Run: bin/test-in-docker bin/tmux-open-github.test.sh
set -eo pipefail
# Guarded by name rather than need: every bin/tmux-*.test.sh is, and
# bin/tmux-test-guard.test.sh enforces it.
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2
. "$(dirname "$0")/test-lib.sh" || exit 2

SCRIPT="$(cd "$(dirname "$0")" && pwd)/tmux-open-github"
test_tmpdir
STUB="$TEST_TMPDIR/stub"
mkdir -p "$STUB"

# gh answers from GH_PR_URL / GH_REPO_URL; an empty one means "no such thing
# here", which gh reports with a non-zero exit.
cat >"$STUB/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$PWD" >"$STUB_LOG/gh.cwd"
case "$1 $2" in
  'pr view') url=$GH_PR_URL ;;
  'repo view') url=$GH_REPO_URL ;;
  *) exit 64 ;;
esac
[ -n "$url" ] || exit 1
printf '%s\n' "$url"
EOF
for cmd in tmux open xdg-open; do
  cat >"$STUB/$cmd" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"\$STUB_LOG/$cmd"
[ -z "\${FAIL_OPENER:-}" ] || [ "$cmd" = tmux ]
EOF
done
chmod +x "$STUB"/*

# run <case> [VAR=value...] -- run the script with a fresh log dir and tty
# file; the case's outputs are read back from $TEST_TMPDIR/<case>/.
run() {
  local dir=$TEST_TMPDIR/$1
  shift
  mkdir -p "$dir/log" "$dir/repo dir"
  : >"$dir/tty"
  env -u SSH_CONNECTION PATH="$STUB:/usr/bin:/bin" STUB_LOG="$dir/log" \
    GH_PR_URL= GH_REPO_URL= "$@" "$SCRIPT" "$dir/tty" "$dir/repo dir" >/dev/null 2>&1
}
log() { cat "$TEST_TMPDIR/$1/log/$2" 2>/dev/null || :; }
# Which of open/xdg-open ran depends on the platform the suite runs on.
opened() { printf '%s%s' "$(log "$1" open)" "$(log "$1" xdg-open)"; }

PR=https://github.com/o/r/pull/7
REPO=https://github.com/o/r

run local-pr GH_PR_URL=$PR GH_REPO_URL=$REPO
assert_eq "locally, a branch with a PR opens the PR" "$PR" "$(opened local-pr)"
assert_eq "locally, nothing is written to the pane" "" "$(cat "$TEST_TMPDIR/local-pr/tty")"
assert_contains "it says what it opened" "$(log local-pr tmux)" "$PR"
# pwd -P: macOS's $TMPDIR is a symlink, and the script's cd resolves it.
assert_eq "gh asks about the directory it was given" \
  "$(cd "$TEST_TMPDIR/local-pr/repo dir" && pwd -P)" "$(cd "$(log local-pr gh.cwd)" && pwd -P)"

run local-repo GH_REPO_URL=$REPO
assert_eq "without a PR the repository opens" "$REPO" "$(opened local-repo)"

run opener-fails GH_PR_URL=$PR FAIL_OPENER=1
assert_contains "a failing opener is reported, not swallowed by set -e" "$(log opener-fails tmux)" "failed for $PR"
assert_not_contains "and not reported as opened" "$(log opener-fails tmux)" "opening"

run none
assert_eq "outside a GitHub repo nothing opens" "" "$(opened none)"
assert_contains "and it says so instead of failing silently" "$(log none tmux)" "not a GitHub repository"

# Over ssh: open(1) here would launch a browser on the far end. The URL goes to
# the pane instead, wrapped for two tmux layers (the remote's and the one
# beside WezTerm), which is what reaches WezTerm in the myssh shape.
# A URL longer than 57 bytes, because GNU base64 wraps its output at 76
# columns and a newline inside the OSC would end it early.
LONG=https://github.com/some-organisation/some-repository-name/pull/12345
run ssh SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' GH_PR_URL=$LONG
assert_eq "over ssh nothing opens on the remote" "" "$(opened ssh)"
b64=$(printf '%s' "$LONG" | base64 | tr -d '\n')
esc=$(printf '\033')
bel=$(printf '\007')
osc="${esc}]1337;SetUserVar=open_url=${b64}${bel}"
d1="${esc}Ptmux;${osc//${esc}/${esc}${esc}}${esc}\\"
d2="${esc}Ptmux;${d1//${esc}/${esc}${esc}}${esc}\\"
tty_out=$(cat "$TEST_TMPDIR/ssh/tty")
# Exact, not "contains": $osc is a substring of $d1, so only the whole write
# shows that depth 0 (a remote tmux with nothing beside WezTerm) was sent.
assert_eq "over ssh the open_url user var is written at depths 0, 1 and 2, and nothing else" \
  "$osc$d1$d2" "$tty_out"

mkdir -p "$TEST_TMPDIR/no-dir/log"
env -u SSH_CONNECTION PATH="$STUB:/usr/bin:/bin" STUB_LOG="$TEST_TMPDIR/no-dir/log" GH_PR_URL=$PR \
  "$SCRIPT" "$TEST_TMPDIR/no-dir/tty" "$TEST_TMPDIR/no-dir/repo dir" >/dev/null 2>&1
assert_eq "a directory that is gone opens nothing" "" "$(opened no-dir)"
assert_contains "and says it cannot enter it" "$(log no-dir tmux)" "cannot enter"

mkdir -p "$TEST_TMPDIR/no-tty/log" "$TEST_TMPDIR/no-tty/repo"
env PATH="$STUB:/usr/bin:/bin" STUB_LOG="$TEST_TMPDIR/no-tty/log" GH_PR_URL=$PR \
  SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' \
  "$SCRIPT" "$TEST_TMPDIR/no-tty/missing/tty" "$TEST_TMPDIR/no-tty/repo" >/dev/null 2>&1
assert_contains "over ssh a tty it cannot write says so" "$(log no-tty tmux)" "cannot write to"

test_summary
