#!/bin/bash
#
# install-helpers.test.sh -- pins what bin/init/common.sh's install helpers
# hand on: install_or_upgrade_npm_global leaves install scripts to
# ~/.npmrc's ignore-scripts=true (zsh/README.md), install_go_tools passes
# its arguments to bin/go-tools-install (bin/go-cooldown.md), or fails when go
# is missing, and update_homebrew has GitHub credentials before it upgrades
# anything (bin/init/homebrew-env.sh), and fetch_verified keeps a download only
# when it hashes to its pin (bin/init/pins.md). npm, go and go-tools-install are stubs
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
# `brew install gh` puts the gh stub into $GH_INSTALL_TO; a brew subcommand
# named in $BREW_FAIL fails. `gh auth token` succeeds when $GH_AUTHED is set or
# a login has happened: `gh auth login` leaves $GH_MARK behind when
# $GH_LOGIN_WORKS is set.
BREW="$TEST_TMPDIR/brew"
GH_SRC="$TEST_TMPDIR/gh-src"
mkdir -p "$BREW" "$GH_SRC"
cat >"$BREW/brew" <<'EOF'
#!/bin/sh
echo "brew $*" >>"$LOG"
[ "$1" = "${BREW_FAIL:-}" ] && exit 1
if [ "$*" = "install gh" ] && [ -n "${GH_INSTALL_TO:-}" ]; then
  /bin/cp "$GH_SRC/gh" "$GH_INSTALL_TO/gh"
fi
exit 0
EOF
cat >"$GH_SRC/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >>"$LOG"
case "$*" in
  "auth token") [ -n "${GH_AUTHED:-}" ] || [ -e "$GH_MARK" ] ;;
  "auth login"*) [ -z "${GH_LOGIN_WORKS:-}" ] || : >"$GH_MARK" ;;
esac
EOF
chmod +x "$BREW/brew" "$GH_SRC/gh"
export GH_SRC GH_MARK="$TEST_TMPDIR/gh-logged-in"
unset HOMEBREW_GITHUB_API_TOKEN GH_AUTHED GH_INSTALL_TO BREW_FAIL GH_LOGIN_WORKS
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

# An empty token is what `${{ secrets.X }}` gives for a missing secret.
: >"$LOG"
st=$(HOMEBREW_GITHUB_API_TOKEN='' GH_AUTHED=1 helper "$BREW:$WITH_GH" ensure_homebrew_github_auth)
assert_eq "auth: an empty HOMEBREW_GITHUB_API_TOKEN counts as none" \
  "0 gh auth token" "$st $(cat "$LOG")"

: >"$LOG"
st=$(BREW_FAIL=install GH_AUTHED=1 GH_INSTALL_TO="$BREW" helper "$BREW" ensure_homebrew_github_auth)
assert_eq "auth: a failed gh install fails, and gh is not run" \
  "1 brew install gh" "$st $(cat "$LOG")"
rm -f "$BREW/gh"

# The login is offered only on a terminal, which `helper` never gives, so these
# run under script(1). Its arguments differ between BSD (macOS:
# `script -q <file> <cmd...>`) and util-linux (CI: `script -qec "<cmd>"
# <file>`); probed, as the tmux suites do.
cat >"$TEST_TMPDIR/in-tty" <<EOF
#!/bin/bash
PATH=\$1
shift
. "$COMMON"
"\$@" >/dev/null 2>"$TEST_TMPDIR/err"
echo \$? >"$TEST_TMPDIR/st"
EOF
chmod +x "$TEST_TMPDIR/in-tty"
if script -q /dev/null echo probe 2>/dev/null | grep -q probe; then
  in_tty() { script -q /dev/null "$TEST_TMPDIR/in-tty" "$@" </dev/null >/dev/null 2>&1; }
else
  in_tty() { script -qec "$TEST_TMPDIR/in-tty $*" /dev/null </dev/null >/dev/null 2>&1; }
fi

: >"$LOG"
rm -f "$GH_MARK" "$TEST_TMPDIR/st"
GH_LOGIN_WORKS=1 in_tty "$BREW:$WITH_GH" ensure_homebrew_github_auth
assert_eq "auth: on a terminal, a login is offered and then used" \
  "0 gh auth token|gh auth login --hostname github.com --git-protocol ssh|gh auth token" \
  "$(cat "$TEST_TMPDIR/st" 2>/dev/null) $(tr '\n' '|' <"$LOG" | sed 's/|$//')"

: >"$LOG"
rm -f "$GH_MARK" "$TEST_TMPDIR/st"
in_tty "$BREW:$WITH_GH" ensure_homebrew_github_auth
assert_eq "auth: a login that leaves no token fails" "1" "$(cat "$TEST_TMPDIR/st" 2>/dev/null)"
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

: >"$LOG"
st=$(BREW_FAIL=update GH_AUTHED=1 helper "$BREW:$WITH_GH" update_homebrew)
assert_eq "update_homebrew: a failed update fails, checking and upgrading nothing" \
  "1 brew update" "$st $(cat "$LOG")"

# fetch_verified: what is downloaded is kept only when it hashes to the pin.
# file:// keeps it off the network; curl and the hasher are the real ones.
printf 'payload\n' >"$TEST_TMPDIR/payload"
PAYLOAD_URL="file://$TEST_TMPDIR/payload"
PAYLOAD_SHA=$(shasum -a 256 "$TEST_TMPDIR/payload" | cut -d' ' -f1)
st=$(helper "/usr/bin:/bin" fetch_verified "$PAYLOAD_URL" "$PAYLOAD_SHA" "$TEST_TMPDIR/got")
assert_eq "fetch_verified: a matching download is kept" \
  "0 payload" "$st $(cat "$TEST_TMPDIR/got" 2>/dev/null)"

st=$(helper "/usr/bin:/bin" fetch_verified "$PAYLOAD_URL" "$(printf '0%.0s' {1..64})" "$TEST_TMPDIR/bad")
assert_eq "fetch_verified: a mismatching download fails" "1" "$st"
assert_eq "  ... and leaves nothing at the destination" "absent" \
  "$([ -e "$TEST_TMPDIR/bad" ] || [ -e "$TEST_TMPDIR/bad.part" ] || echo absent)"
assert_contains "  ... saying why" "$(cat "$TEST_TMPDIR/err")" "checksum mismatch"

st=$(helper "/usr/bin:/bin" fetch_verified "$PAYLOAD_URL" "" "$TEST_TMPDIR/nopin")
assert_eq "fetch_verified: an empty pin fails rather than accepting anything" \
  "1" "$st"
assert_eq "  ... and downloads nothing" "absent" \
  "$([ -e "$TEST_TMPDIR/nopin" ] || echo absent)"

# pinned_sha256: the checksum for this OS and architecture, per uname.
UNAME="$TEST_TMPDIR/uname"
mkdir -p "$UNAME"
cat >"$UNAME/uname" <<'EOF'
#!/bin/sh
case "$1" in -s) echo "$UNAME_S" ;; -m) echo "$UNAME_M" ;; esac
EOF
chmod +x "$UNAME/uname"
export TOOL_SHA256_DARWIN_ARM64=da TOOL_SHA256_DARWIN_X64=dx \
  TOOL_SHA256_LINUX_X64=lx TOOL_SHA256_LINUX_ARM64=la
for case in "Darwin arm64 da" "Darwin x86_64 dx" "Linux x86_64 lx" "Linux aarch64 la"; do
  read -r s m want <<<"$case"
  out=$(UNAME_S=$s UNAME_M=$m PATH="$UNAME:/usr/bin:/bin" bash -c \
    '. "$1"; pinned_sha256 TOOL' _ "$COMMON" 2>/dev/null)
  assert_eq "pinned_sha256: $s $m picks its own checksum" "$want" "$out"
done
UNAME_S=FreeBSD UNAME_M=amd64 PATH="$UNAME:/usr/bin:/bin" bash -c \
  '. "$1"; pinned_sha256 TOOL' _ "$COMMON" >/dev/null 2>&1
assert_eq "pinned_sha256: an unpinned platform fails" "1" "$?"

test_summary
