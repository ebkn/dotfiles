#!/bin/bash
#
# tmux-plugins-install.test.sh -- pins that every tmux plugin ends up checked
# out at the commit bin/tmux-plugins.txt names, and at nothing newer: a fresh
# clone, a pin moved to a commit the clone has not fetched, a working tree the
# .tmux.conf sed patch has dirtied. And that what cannot be vouched for -- a
# clone of another repository, a commit the remote does not have, a directory
# that is not a clone, a line that cannot be read -- fails, names the plugin,
# and leaves the checkout alone. Upstreams are local repositories, so nothing
# here reaches the network. See bin/tmux-plugins-install.md.
#
# Written for bash 3.2 (/bin/bash on macOS), as the tool is.
set -uo pipefail
# A tmux suite by name: container or CI only (see bin/tmux-test-guard.sh).
# It never starts tmux, but enrollment is by name on purpose -- see
# bin/tmux-test-guard.test.sh -- so it follows the rule rather than being
# its exception.
# shellcheck source=bin/tmux-test-guard.sh
. "$(dirname "$0")/tmux-test-guard.sh" || exit 2
. "$(dirname "$0")/test-lib.sh" || exit 2

BIN="$(cd "$(dirname "$0")" && pwd -P)"
TOOL="$BIN/tmux-plugins-install"
test_tmpdir

# The developer's ~/.gitconfig rewrites URLs, signs commits and runs hooks;
# none of it may reach these repositories.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
G="git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main"

# One upstream, built once (testing.md rule 3): a plugin with two commits, so
# a pin on the first is not the tip a plain clone would check out.
UP="$TEST_TMPDIR/up/plugin-a"
mkdir -p "$UP"
$G -C "$UP" init -q
echo one >"$UP/a.tmux"
$G -C "$UP" add a.tmux
$G -C "$UP" commit -qm one
C1=$($G -C "$UP" rev-parse HEAD)
echo two >"$UP/a.tmux"
$G -C "$UP" commit -qam two
C2=$($G -C "$UP" rev-parse HEAD)

# case_dir: a fresh $HOME and a copy of the upstream, per case.
case_dir() {
  D="$TEST_TMPDIR/case-$1"
  mkdir -p "$D/home" "$D/up"
  cp -R "$UP" "$D/up/plugin-a"
  export HOME="$D/home"
  URL="$D/up/plugin-a"
  P="$HOME/.tmux/plugins/plugin-a"
}

head_of() { git -C "$1" rev-parse HEAD 2>/dev/null; }

test_fresh_clone() {
  case_dir fresh
  printf '# comment\n\n%s %s\n' "$URL" "$C1" >"$D/list"
  assert_status "a missing plugin is cloned" 0 "$TOOL" "$D/list"
  assert_eq "  ... at the pin, not the tip" "$C1" "$(head_of "$P")"
  assert_eq "  ... with the pin's files" one "$(cat "$P/a.tmux")"
  assert_status "a second run changes nothing and passes" 0 "$TOOL" "$D/list"
  assert_eq "  ... still at the pin" "$C1" "$(head_of "$P")"
}

# A --no-checkout clone already has HEAD at the tip, so a pin on the tip
# looks done by HEAD alone while nothing is on disk. tpm is pinned to its tip.
test_fresh_clone_pinned_to_tip() {
  case_dir fresh-tip
  printf '%s %s\n' "$URL" "$C2" >"$D/list"
  assert_status "a missing plugin pinned to the tip is cloned" 0 "$TOOL" "$D/list"
  assert_eq "  ... with the tip's files on disk" two "$(cat "$P/a.tmux" 2>/dev/null)"
}

test_moved_pin_fetches() {
  case_dir moved
  printf '%s %s\n' "$URL" "$C1" >"$D/list"
  "$TOOL" "$D/list" >/dev/null 2>&1
  # A commit pushed after the clone: the tool has to fetch to find it.
  echo three >"$URL/a.tmux"
  $G -C "$URL" commit -qam three
  c3=$($G -C "$URL" rev-parse HEAD)
  printf '%s %s\n' "$URL" "$c3" >"$D/list"
  assert_status "a pin the clone has not fetched" 0 "$TOOL" "$D/list"
  assert_eq "  ... is fetched and checked out" "$c3" "$(head_of "$P")"
}

test_dirty_tree_is_reset() {
  case_dir dirty
  printf '%s %s\n' "$URL" "$C1" >"$D/list"
  "$TOOL" "$D/list" >/dev/null 2>&1
  # What .tmux.conf's sed does to tmux-fzf-url on every load.
  echo patched >"$P/a.tmux"
  printf '%s %s\n' "$URL" "$C2" >"$D/list"
  assert_status "a pin moves over a patched working tree" 0 "$TOOL" "$D/list"
  assert_eq "  ... to the new pin" "$C2" "$(head_of "$P")"
  assert_eq "  ... with its files, not the patch" two "$(cat "$P/a.tmux")"
}

test_tpm_style_origin_is_the_same_repo() {
  case_dir tpm-origin
  git clone -q "$URL" "$P"
  git -C "$P" checkout -q --detach "$C1"
  # tpm clones as https://git::@github.com/<repo>; init cloned tpm itself
  # with a .git-less https URL. Both name the line's repository.
  git -C "$P" remote set-url origin "https://git::@github.com/o/plugin-a.git"
  printf 'https://github.com/o/plugin-a %s\n' "$C1" >"$D/list"
  assert_status "an origin tpm wrote is the line's repository" 0 "$TOOL" "$D/list"
}

test_other_origin_is_refused() {
  case_dir other-origin
  printf '%s %s\n' "$URL" "$C1" >"$D/list"
  "$TOOL" "$D/list" >/dev/null 2>&1
  git -C "$P" remote set-url origin "https://github.com/evil/plugin-a"
  printf '%s %s\n' "$URL" "$C2" >"$D/list"
  out=$("$TOOL" "$D/list" 2>&1)
  assert_eq "a clone of another repository fails" 1 "$?"
  assert_contains "  ... naming the plugin and both origins" "$out" \
    "plugin-a: origin is https://github.com/evil/plugin-a, not $URL"
  assert_eq "  ... and is not checked out" "$C1" "$(head_of "$P")"
}

test_unknown_commit_fails_and_others_still_run() {
  case_dir unknown
  cp -R "$URL" "$D/up/plugin-b"
  missing=0123456789abcdef0123456789abcdef01234567
  printf '%s %s\n%s %s\n' "$URL" "$missing" "$D/up/plugin-b" "$C1" >"$D/list"
  out=$("$TOOL" "$D/list" 2>&1)
  assert_eq "a commit the remote does not have fails" 1 "$?"
  assert_contains "  ... naming it" "$out" "plugin-a: $missing is not in $URL"
  assert_eq "  ... after the next plugin was still installed" "$C1" \
    "$(head_of "$HOME/.tmux/plugins/plugin-b")"
}

test_not_a_clone_fails() {
  case_dir not-a-clone
  mkdir -p "$P"
  printf '%s %s\n' "$URL" "$C1" >"$D/list"
  out=$("$TOOL" "$D/list" 2>&1)
  assert_eq "a directory that is not a clone fails" 1 "$?"
  assert_contains "  ... naming it" "$out" "plugin-a: $P is not a git clone"
}

# Each bad line breaks one condition of the check, so loosening any one of
# them (a length, the hex class, the word count) lets its line through.
test_unreadable_line_fails_first() {
  local bad what
  case_dir bad-line
  while IFS='|' read -r what bad; do
    printf '%s %s\n%s\n' "$URL" "$C1" "$bad" >"$D/list"
    out=$("$TOOL" "$D/list" 2>&1)
    assert_eq "a line with $what fails" 1 "$?"
    assert_contains "  ... naming it" "$out" "list line 2"
    assert_status "  ... before anything is cloned" 1 test -e "$P"
  done <<EOF
a branch for a commit|$URL main
39 hex digits|$URL ${C1:0:39}
41 hex digits|$URL ${C1}0
upper-case hex|$URL $(tr a-f A-F <<<"$C1")
a third word|$URL $C1 extra
no commit|$URL
EOF
}

# A clone or a fetch that git itself fails is a failed plugin like any other:
# named, and the next one still installed.
test_git_failures_fail_and_others_still_run() {
  case_dir git-fails
  cp -R "$URL" "$D/up/plugin-b"
  printf '%s %s\n%s %s\n' "$D/up/no-such-repo" "$C1" "$D/up/plugin-b" "$C1" >"$D/list"
  out=$("$TOOL" "$D/list" 2>&1)
  assert_eq "a clone that fails fails the run" 1 "$?"
  assert_contains "  ... naming it" "$out" "tmux-plugins-install: no-such-repo failed"
  assert_eq "  ... after the next plugin was still installed" "$C1" \
    "$(head_of "$HOME/.tmux/plugins/plugin-b")"

  # The remote gone: the pin is absent, so the fetch is tried, and fails.
  printf '%s %s\n' "$URL" "$C1" >"$D/list"
  "$TOOL" "$D/list" >/dev/null 2>&1
  rm -rf "$URL"
  printf '%s %s\n' "$URL" 0123456789abcdef0123456789abcdef01234567 >"$D/list"
  out=$("$TOOL" "$D/list" 2>&1)
  assert_eq "a fetch that fails fails the run" 1 "$?"
  assert_contains "  ... naming it" "$out" "tmux-plugins-install: plugin-a failed"
  assert_eq "  ... and the checkout is left alone" "$C1" "$(head_of "$P")"
}

test_run_through_link_finds_its_list() {
  case_dir link
  # As update-all runs it: through ~/.local/bin, no file named. A copy of the
  # tool beside a fixture list, so the real list's GitHub URLs are not cloned.
  mkdir -p "$D/bin" "$D/home-bin"
  cp "$TOOL" "$D/bin/tmux-plugins-install"
  printf '%s %s\n' "$URL" "$C1" >"$D/bin/tmux-plugins.txt"
  ln -s "$D/bin/tmux-plugins-install" "$D/home-bin/tmux-plugins-install"
  assert_status "run through a link, it reads the list beside its target" 0 \
    "$D/home-bin/tmux-plugins-install"
  assert_eq "  ... and installs from it" "$C1" "$(head_of "$P")"
}

test_usage() {
  assert_status "a missing list fails" 1 "$TOOL" "$TEST_TMPDIR/none.txt"
  assert_status "an option is a usage error" 2 "$TOOL" --all
}

# tpm loads the plugins .tmux.conf names, from the directories this tool
# fills. A plugin in one and not the other is either loaded unpinned (cloned
# by prefix + I) or pinned and never loaded.
test_list_matches_tmux_conf() {
  conf=$(sed -n "s/^set -g @plugin '\\([^']*\\)'.*/\\1/p" "$BIN/../.tmux.conf")
  list=$(sed -n 's|^https://github.com/\([^ ]*\) .*|\1|p' "$BIN/tmux-plugins.txt")
  assert_eq "bin/tmux-plugins.txt names exactly .tmux.conf's @plugin lines" \
    "$(sort <<<"$conf")" "$(sort <<<"$list")"
}

# Called by name, not through run_tests, so shellcheck sees each one used.
# Every case sets its own $HOME and directory through case_dir.
test_fresh_clone
test_fresh_clone_pinned_to_tip
test_moved_pin_fetches
test_dirty_tree_is_reset
test_tpm_style_origin_is_the_same_repo
test_other_origin_is_refused
test_unknown_commit_fails_and_others_still_run
test_not_a_clone_fails
test_unreadable_line_fails_first
test_git_failures_fail_and_others_still_run
test_run_through_link_finds_its_list
test_usage
test_list_matches_tmux_conf
test_summary
