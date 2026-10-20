#!/bin/bash
#
# install-helpers.test.sh -- pins what two of bin/init/common.sh's install
# helpers hand on: install_or_upgrade_npm_global leaves install scripts to
# ~/.npmrc's ignore-scripts=true (zsh/README.md), and install_go_tools passes
# its arguments to bin/go-tools-install (bin/go-cooldown.md), or fails when go
# is missing. npm, go and go-tools-install are stubs that log their
# arguments; PATH holds only the stubs and the system directories, so no real
# npm or go is found.
#
# Written for bash 3.2 (/bin/bash on macOS), as the init scripts are.
set -uo pipefail
. "$(dirname "$0")/../test-lib.sh" || exit 2

COMMON="$(cd "$(dirname "$0")" && pwd -P)/common.sh"
test_tmpdir

STUB="$TEST_TMPDIR/stub"
mkdir -p "$STUB" "$TEST_TMPDIR/dotfiles/bin"
# npm: `npm list -g ...` succeeds when $NPM_HAS is set, so the helper updates
# rather than installs.
cat >"$STUB/npm" <<'EOF'
#!/bin/sh
[ "$1" = list ] && { [ -n "${NPM_HAS:-}" ]; exit; }
echo "npm $*" >>"$LOG"
EOF
cat >"$STUB/go" <<'EOF'
#!/bin/sh
echo "go $*" >>"$LOG"
EOF
cat >"$TEST_TMPDIR/dotfiles/bin/go-tools-install" <<'EOF'
#!/bin/sh
echo "go-tools-install $*" >>"$LOG"
exit "${GTI_EXIT:-0}"
EOF
chmod +x "$STUB/npm" "$STUB/go" "$TEST_TMPDIR/dotfiles/bin/go-tools-install"
export LOG="$TEST_TMPDIR/log" DOTFILES_DIR="$TEST_TMPDIR/dotfiles"

# helper <PATH> <function> [args...] -- run one helper from a freshly sourced
# common.sh; prints its status.
helper() {
  local path=$1
  shift
  (
    PATH=$path
    # shellcheck source=bin/init/common.sh
    . "$COMMON"
    "$@"
  ) >/dev/null 2>"$TEST_TMPDIR/err"
  echo $?
}

: >"$LOG"
helper "$STUB:/usr/bin:/bin" install_or_upgrade_npm_global textlint >/dev/null
assert_eq "npm: a new global is installed, scripts left to ~/.npmrc" \
  "npm install --global textlint" "$(cat "$LOG")"

: >"$LOG"
NPM_HAS=1 helper "$STUB:/usr/bin:/bin" install_or_upgrade_npm_global textlint >/dev/null
assert_eq "npm: an installed global is updated, scripts left to ~/.npmrc" \
  "npm update --global textlint" "$(cat "$LOG")"

: >"$LOG"
st=$(helper "$STUB:/usr/bin:/bin" install_go_tools --except tailscale.com)
assert_eq "go: install_go_tools runs go-tools-install with its arguments" \
  "0 go-tools-install --except tailscale.com" "$st $(cat "$LOG")"

: >"$LOG"
st=$(GTI_EXIT=1 helper "$STUB:/usr/bin:/bin" install_go_tools)
assert_eq "go: ... and fails when it fails" "1" "$st"

mkdir -p "$TEST_TMPDIR/nogo"
cp "$STUB/npm" "$TEST_TMPDIR/nogo/"
: >"$LOG"
# Only the stubs' directory: a runner may have go in /usr/bin.
st=$(helper "$TEST_TMPDIR/nogo" install_go_tools)
assert_eq "go: without go it fails" "1" "$st"
assert_contains "  ... saying so" "$(cat "$TEST_TMPDIR/err")" "go is not installed yet"
assert_eq "  ... and installs nothing" "" "$(cat "$LOG")"

test_summary
