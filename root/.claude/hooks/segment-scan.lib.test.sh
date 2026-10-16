#!/bin/bash
# Pins segment-scan.lib.sh's own contract, apart from the hooks that source it:
# the scanner calls the caller's predicate from inside its functions, and bash
# scope is dynamic, so a predicate that assigns a common name without `local`
# writes straight into the scanner's variables. git-dash-c-allow.sh did, with
# `line`, and the rest of the line it was scanning -- `; rm -rf x` -- vanished
# and the command was approved. The scanner's names must not be ones a
# predicate would plausibly use.
set -uo pipefail

# shellcheck source=root/.claude/hooks/segment-scan.lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/segment-scan.lib.sh"

pass=0
fail=0

ok() {
  if [[ "$2" == "$3" ]]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$1"
  else
    fail=$((fail + 1))
    printf '  FAIL %s: want %s, got %s\n' "$1" "$3" "$2"
  fi
}

SEEN=()
# Records each segment's command word, and clobbers every name a predicate is
# likely to use, none of them declared local.
# shellcheck disable=SC2034 # the assignments are the point
clobbering() {
  SEEN[${#SEEN[@]}]=$1
  line=x lines=x li=99 i=99 n=0 c=x seg=x pre=x j=99 q=x tag=x body=x found=1 total=0
  return 0
}

SEEN=()
scan_command 'git status; rm -rf x' clobbering && rc=0 || rc=$?
ok "a clobbering predicate still sees every segment" "${SEEN[*]}" "git rm"
ok "and the scan still succeeds" "$rc" 0

SEEN=()
scan_command $'git add a\ngit commit -m x\nnpm test' clobbering && rc=0 || rc=$?
ok "across lines too" "${SEEN[*]}" "git git npm"

SEEN=()
scan_command $'git commit -F - <<\'EOF\'\nbody; rm -rf x\nEOF\nnpm test' clobbering && rc=0 || rc=$?
ok "and past a heredoc body" "${SEEN[*]}" "git npm"

# A predicate rejecting a segment fails the scan, wherever the segment ends.
reject_rm() { [[ "$1" != rm ]]; }
scan_command 'git status; rm -rf x' reject_rm && rc=0 || rc=$?
ok "a rejected segment after ; fails the scan" "$rc" 1
scan_command 'git status && rm -rf x' reject_rm && rc=0 || rc=$?
ok "after && too" "$rc" 1
scan_command $'git status\nrm -rf x' reject_rm && rc=0 || rc=$?
ok "after a newline too" "$rc" 1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
