#!/bin/bash
# Guards default.rules against SILENT load failure.
#
# Why this exists: prefix_rule() accepts `match`/`not_match` example commands
# that Codex asserts at load time. When an assertion is violated, Codex drops
# the ENTIRE containing .rules file and says nothing -- exit status is 0 and
# stderr is empty. Because every rule lives in default.rules, one bad assertion
# silently removes every `forbidden` rule too, which fails OPEN. Verified
# against codex-cli 0.144.5.
#
# The check reads the prompt Codex actually builds (`codex debug prompt-input`)
# and asserts that allow-listed prefixes are present and that prefixes we
# deliberately gate are absent from the approved list.
#
# Limitation: the injected prompt lists only `allow` rules, so this cannot tell
# `prompt` apart from `forbidden` -- absence proves only "not auto-approved".
set -uo pipefail

command -v codex >/dev/null || { echo "codex not on PATH; skipping"; exit 0; }

# Strip JSON backslash escapes so `\"ls\"` greps as `"ls"`.
# shellcheck disable=SC1003  # '\\' is tr's escape for a literal backslash, not a quoting mistake.
dump=$(codex debug prompt-input 2>/dev/null | tr -d '\\')
if [[ -z "$dump" ]]; then
  echo "FAIL: codex debug prompt-input produced no output"
  exit 1
fi

pass=0
fail=0

present() {
  if printf '%s' "$dump" | grep -qF -- "$1"; then
    pass=$((pass + 1)); printf '  ok   present  %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL missing  %s\n' "$1"
  fi
}

absent() {
  if printf '%s' "$dump" | grep -qF -- "$1"; then
    fail=$((fail + 1)); printf '  FAIL allowed  %s\n' "$1"
  else
    pass=$((pass + 1)); printf '  ok   gated    %s\n' "$1"
  fi
}

# Sentinels spread across the file: if any is missing, the file failed to load.
echo "-- allow rules must be present (proves default.rules loaded) --"
present '["shellcheck"]'
present '["actionlint"]'
present '["ast-grep"]'
present '["terminal-notifier"]'
present '["/usr/bin/log", "show"]'
present '["git", "commit", "-m"]'
present '["git", "merge", "[main|origin/main]"]'
present '["gh", "pr", "[checks|create|diff|edit|list|status|view]"]'
present '["go", "mod", "[graph|verify|why]"]'
present '["brew", "[cat|deps|info|leaves|list|outdated|search]"]'

# These are `prompt` or `forbidden`, so they must never be auto-approved.
echo "-- gated commands must NOT be auto-approved --"
absent '["curl"]'
absent '["wget"]'
absent '["rm"]'
absent '["cp"]'
absent '["mv"]'
absent '["sudo"]'
absent '["env"]'
absent '["printenv"]'
absent '["git", "checkout"]'
absent '["git", "switch"]'
absent '["gh", "api"]'
absent '["git", "push", "--force"]'
absent '["git", "reset", "--hard"]'
absent '["npm", "publish"]'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
