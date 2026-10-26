#!/bin/bash
#
# install-helpers.test.sh -- pins what bin/init/common.sh's install helpers
# hand on: install_or_upgrade_npm_global leaves install scripts to
# ~/.npmrc's ignore-scripts=true (zsh/README.md), install_go_tools passes
# its arguments to bin/go-tools-install (bin/go-cooldown.md), or fails when go
# is missing, and update_homebrew has GitHub credentials before it upgrades
# anything (bin/init/homebrew-env.sh). npm, go and go-tools-install are stubs
# that log their arguments; PATH holds only the stubs and the system
# directories, so no real npm or go is found.
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
  ) </dev/null >/dev/null 2>"$TEST_TMPDIR/err"
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

# --- Homebrew's GitHub credentials ------------------------------------------
# HOMEBREW_VERIFY_ATTESTATIONS=1 fails every bottle but gh's when Homebrew
# finds no GitHub credentials, so update_homebrew must have them before its
# first `brew upgrade`. brew and gh are stubs in directories of their own:
# PATH holds nothing else, because a runner ships a real gh in /usr/bin.
# `brew install gh` puts the gh stub into $GH_INSTALL_TO; `gh auth token`
# succeeds only when $GH_AUTHED is set.
BREW="$TEST_TMPDIR/brew"
GH_SRC="$TEST_TMPDIR/gh-src"
mkdir -p "$BREW" "$GH_SRC"
cat >"$BREW/brew" <<'EOF'
#!/bin/sh
echo "brew $*" >>"$LOG"
if [ "$*" = "install gh" ] && [ -n "${GH_INSTALL_TO:-}" ]; then
  /bin/cp "$GH_SRC/gh" "$GH_INSTALL_TO/gh"
fi
EOF
cat >"$GH_SRC/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >>"$LOG"
[ "$*" = "auth token" ] && { [ -n "${GH_AUTHED:-}" ]; exit; }
exit 0
EOF
chmod +x "$BREW/brew" "$GH_SRC/gh"
export GH_SRC
unset HOMEBREW_GITHUB_API_TOKEN GH_AUTHED GH_INSTALL_TO
WITH_GH="$TEST_TMPDIR/with-gh"
mkdir -p "$WITH_GH"
cp "$GH_SRC/gh" "$WITH_GH/gh"

: >"$LOG"
st=$(HOMEBREW_GITHUB_API_TOKEN=x helper "$BREW" ensure_homebrew_github_auth)
assert_eq "auth: a HOMEBREW_GITHUB_API_TOKEN is enough, and nothing runs" \
  "0 " "$st $(cat "$LOG")"

: >"$LOG"
st=$(GH_AUTHED=1 helper "$BREW:$WITH_GH" ensure_homebrew_github_auth)
assert_eq "auth: a gh login is enough" "0 gh auth token" "$st $(cat "$LOG")"

: >"$LOG"
st=$(GH_AUTHED=1 GH_INSTALL_TO="$BREW" helper "$BREW" ensure_homebrew_github_auth)
assert_eq "auth: without gh, gh is installed first" \
  "0 brew install gh gh auth token" "$st $(tr '\n' ' ' <"$LOG" | sed 's/ $//')"
rm -f "$BREW/gh"

: >"$LOG"
st=$(helper "$BREW:$WITH_GH" ensure_homebrew_github_auth)
assert_eq "auth: no credentials and no terminal fails" "1" "$st"
assert_eq "  ... without trying to log in" "gh auth token" "$(cat "$LOG")"
assert_contains "  ... naming the way out" "$(cat "$TEST_TMPDIR/err")" \
  "HOMEBREW_GITHUB_API_TOKEN"

: >"$LOG"
st=$(GH_AUTHED=1 helper "$BREW:$WITH_GH" update_homebrew)
assert_eq "update_homebrew: credentials are checked between update and upgrade" \
  "0 brew update|gh auth token|brew upgrade" "$st $(tr '\n' '|' <"$LOG" | sed 's/|$//')"

: >"$LOG"
st=$(helper "$BREW:$WITH_GH" update_homebrew)
assert_eq "update_homebrew: without credentials it fails" "1" "$st"
assert_not_contains "  ... before upgrading anything" "$(cat "$LOG")" "brew upgrade"

test_summary
