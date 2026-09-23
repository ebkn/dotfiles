#!/bin/bash
# Exercises rm-guard.sh against the cases that decide whether it is safe.
# ALLOW = hook emits an allow decision. DEFER = hook stays silent, so the call
# falls through to the normal permission path (the `deny` literals, then the
# auto-mode classifier, then a prompt).
#
# Written for bash 3.2 (see CLAUDE.md): no mapfile, no associative arrays.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rm-guard.sh"

# A throwaway project tree stands in for the caller's cwd, so the DEFER cases
# that hinge on "outside the scratch dir" have a real directory to be outside
# of. Without it every case would defer for the mundane reason that cwd does
# not exist, and the ALLOW half would fail rather than pass vacuously.
FIXTURE=$(mktemp -d)

# tmpfoo and outside/tmp exist so the "resolved path starts with the root"
# boundary has something real to be tested against: both are a prefix match on
# "<cwd>/tmp" yet neither is inside it.
mkdir -p "$FIXTURE/proj/tmp/sub" "$FIXTURE/proj/src" "$FIXTURE/outside" \
  "$FIXTURE/proj/tmpfoo" "$FIXTURE/outside/tmp"
: >"$FIXTURE/proj/tmp/pr-body.md"
: >"$FIXTURE/proj/src/main.go"
: >"$FIXTURE/outside/.env"
: >"$FIXTURE/proj/tmpfoo/keep"
: >"$FIXTURE/outside/tmp/keep"
# A symlinked ancestor is the case a raw-string permission pattern cannot see.
ln -s "$FIXTURE/outside" "$FIXTURE/proj/tmp/escape"

CWD="$FIXTURE/proj"

# The session scratchpad tree, under the real uid-scoped root the hook derives.
SCRATCH="/tmp/claude-$(id -u)/rm-guard-test-$$/scratchpad"
mkdir -p "$SCRATCH"
# Sibling of the scratchpad root sharing its prefix, for the same boundary.
SCRATCH_SIBLING="/tmp/claude-$(id -u)-rm-guard-test-$$"
mkdir -p "$SCRATCH_SIBLING"
cleanup() {
  rm -rf "$FIXTURE" "/tmp/claude-$(id -u)/rm-guard-test-$$" "$SCRATCH_SIBLING"
}
trap cleanup EXIT

pass=0
fail=0

check() {
  local expect=$1 cmd=$2 cwd=${3-$CWD} out got
  out=$(jq -Rn --arg c "$cmd" --arg d "$cwd" \
    '{tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' | "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision": *"allow"'; then
    got=ALLOW
  else
    got=DEFER
  fi
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass + 1))
    printf '  ok   %-5s %s\n' "$got" "$cmd"
  else
    fail=$((fail + 1))
    printf '  FAIL want=%s got=%s  %s\n' "$expect" "$got" "$cmd"
  fi
}

echo "-- must ALLOW (inside the project scratch dir) --"
check ALLOW 'rm tmp/pr-body.md'
check ALLOW 'rm -f tmp/pr-body.md'
check ALLOW 'rm -rf tmp'
check ALLOW 'rm -rf ./tmp'
check ALLOW 'rm -rf tmp/sub'
check ALLOW "rm -rf $CWD/tmp"
check ALLOW 'rm -r -f tmp/sub'
check ALLOW 'rm -rfv tmp/sub'
check ALLOW 'rm -- tmp/pr-body.md'
check ALLOW 'rm tmp/pr-body.md tmp/sub'
# rm -r on a symlink unlinks the link itself; it never descends into the
# target. So removing the link is in scope, and only a path *through* it
# (the case below) escapes the scratch dir.
check ALLOW 'rm -rf tmp/escape'

echo "-- must ALLOW (inside the session scratchpad tree) --"
check ALLOW "rm -rf $SCRATCH"
check ALLOW "rm -rf $SCRATCH/probe"

echo "-- must DEFER (outside the scratch roots) --"
check DEFER 'rm src/main.go'
check DEFER 'rm -rf src'
check DEFER "rm $FIXTURE/outside/.env"
check DEFER 'rm -rf .'
check DEFER 'rm -rf ..'
check DEFER 'rm -rf /'
check DEFER 'rm -rf ~'
check DEFER 'rm -rf .git'

echo "-- must DEFER (the documented raw-string bypass) --"
check DEFER 'rm tmp/../src/main.go'
check DEFER 'rm ./tmp/../../outside/.env'
check DEFER 'rm -rf tmp/escape/.env'
# A trailing slash is only a different spelling of the same link; rm errors on
# it rather than descending, so it is in scope like the bare form above.
check ALLOW 'rm -rf tmp/escape/'
check DEFER "rm -rf /tmp/claude-$(id -u)"

echo "-- must DEFER (root boundary: prefix match is not containment) --"
# The one-character regression these pin: `== "$root"*` instead of
# `== "$root"/*` would approve every one of these.
check DEFER 'rm -rf tmpfoo'
check DEFER 'rm tmpfoo/keep'
check DEFER "rm -rf $FIXTURE/outside/tmp"
check DEFER "rm $FIXTURE/outside/tmp/keep"
check DEFER "rm -rf $SCRATCH_SIBLING"
check DEFER "rm $SCRATCH_SIBLING/anything"
# A `..` final component inside the root is refused rather than reasoned about.
check DEFER 'rm -rf tmp/sub/..'

echo "-- must DEFER (no usable cwd) --"
# Without cwd the hook cannot tell what `tmp` means; dropping this gate would
# make PROJECT_TMP "/tmp" and resolve relative operands against the hook's own
# working directory.
check DEFER 'rm -rf tmp' ''
check DEFER 'rm -rf tmp' "$FIXTURE/does-not-exist"
check DEFER 'rm tmp/pr-body.md' ''

echo "-- must DEFER (rm reached by an absolute path) --"
# Out of scope on purpose: the hook's engage regex excludes a path-qualified rm,
# so these go to the auto-mode classifier and never depended on this hook.
check DEFER '/bin/rm -rf tmp/sub'
check DEFER '/bin/rm -rf src'
check DEFER '/bin/rmdir tmp'

echo "-- must DEFER (unverifiable flags / shape) --"
check DEFER 'rm -i tmp/pr-body.md'
check DEFER 'rm --no-preserve-root -rf tmp'
check DEFER 'rm --one-file-system -rf tmp'
check DEFER 'rm -rf'
check DEFER 'rm'
check DEFER 'rm tmp/*.log'
check DEFER 'rm tmp/pr-body.md 2>/dev/null'
check DEFER 'rm -rf tmp/pr-body.md tmp/../src/main.go'

echo "-- must DEFER (chaining / expansion) --"
check DEFER 'rm -rf tmp; git status --short'
check DEFER 'rm -rf tmp && git add -A'
check DEFER 'rm -rf tmp | tee log'
# Unexpanded on purpose: the post-expansion path is not knowable here.
# shellcheck disable=SC2016
check DEFER 'D=src; rm -rf $D'
# shellcheck disable=SC2016
check DEFER 'rm -rf "$(pwd)/src"'
# shellcheck disable=SC2016
check DEFER 'rm -rf `echo src`'
# A newline is the third expansion guard: a heredoc or a multi-line script can
# carry an unverifiable second command that the segment split does not see.
check DEFER $'rm -rf tmp\nrm -rf src'

echo "-- must DEFER (not an rm call at all) --"
check DEFER 'echo hello'
check DEFER 'rmdir tmp'
check DEFER 'git rm src/main.go'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
