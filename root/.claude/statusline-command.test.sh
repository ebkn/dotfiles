#!/bin/bash
# Pins two parts of statusline-command.sh's output. The config-dir segment of
# the second row: the name of the dir CLAUDE_CONFIG_DIR points at, shown only
# when that is somewhere other than ~/.claude. And the ~ abbreviation of paths
# in the first row. Every failure here is silent -- a wrong comparison just
# drops or adds the segment -- so each case asserts on the rendered row.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline-command.sh"
# shellcheck source=bin/test-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../bin/test-lib.sh" || exit 2

test_tmpdir
home="$TEST_TMPDIR/home"
mkdir -p "$home"

input='{"workspace":{"project_dir":"/p","current_dir":"/p"},"model":{"display_name":"Opus"}}'

# row2 [CLAUDE_CONFIG_DIR] -- the second row the script renders under $home;
# no argument leaves CLAUDE_CONFIG_DIR unset.
row2() {
  local out
  if (($# == 0)); then
    out=$(printf '%s' "$input" | env -u CLAUDE_CONFIG_DIR HOME="$home" "$SCRIPT")
  else
    out=$(printf '%s' "$input" | HOME="$home" CLAUDE_CONFIG_DIR="$1" "$SCRIPT")
  fi
  printf '%s' "${out#*$'\n'}"
}

assert_eq "CLAUDE_CONFIG_DIR unset: no segment, no separator" "Opus ・ --%(session)・--%(week)" "$(row2)"
assert_eq "CLAUDE_CONFIG_DIR set but empty: no segment, no separator" \
  "Opus ・ --%(session)・--%(week)" "$(row2 "")"
assert_eq "CLAUDE_CONFIG_DIR=~/.claude is the default: no segment" \
  "Opus ・ --%(session)・--%(week)" "$(row2 "$home/.claude")"
assert_eq "a trailing slash on ~/.claude is still the default" \
  "Opus ・ --%(session)・--%(week)" "$(row2 "$home/.claude/")"
assert_eq "another config dir: its name" \
  "Opus ・ --%(session)・--%(week) ・ .claude-work" "$(row2 "$home/.claude-work")"
assert_eq "a trailing slash on another dir does not empty its name" \
  "Opus ・ --%(session)・--%(week) ・ .claude-work" "$(row2 "$home/.claude-work/")"
assert_eq "a config dir outside \$HOME: its name too" \
  "Opus ・ --%(session)・--%(week) ・ elsewhere" "$(row2 "$TEST_TMPDIR/elsewhere")"
assert_eq "a .claude outside \$HOME is not the default: the full path decides" \
  "Opus ・ --%(session)・--%(week) ・ .claude" "$(row2 "$TEST_TMPDIR/other/.claude")"

# The segment goes last, after every other part, with one separator each.
full='{"workspace":{"project_dir":"/p","current_dir":"/p"},"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":20}}}'
out=$(printf '%s' "$full" | HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude-work" "$SCRIPT")
assert_eq "with every part present the config dir comes last" \
  "Opus ・ high ・ 42% Used ・ 10%(session)・20%(week) ・ .claude-work" \
  "${out#*$'\n'}"

# Usage limits. Each case starts from an empty cache in the default config dir
# ($home/.claude, so no config-dir segment trails the row).
cfg="$home/.claude"
cache="$cfg/statusline-rate-limits.json"
future=4102444800 # 2100-01-01: a window that has not reset
past=1            # 1970: a window that has reset
red=$'\033[1;97;41m'
reset=$'\033[0m'

# limits <rate_limits JSON or ""> -- row2 for a session whose input carries
# that rate_limits object; "" leaves the field out, as before the first API
# response.
limits() {
  local in out
  in=$(jq -nc --arg rl "$1" '{workspace:{project_dir:"/p",current_dir:"/p"},
    model:{display_name:"Opus"}} + (if $rl == "" then {} else {rate_limits:($rl | fromjson)} end)')
  out=$(printf '%s' "$in" | HOME="$home" CLAUDE_CONFIG_DIR="$cfg" "$SCRIPT")
  printf '%s' "${out#*$'\n'}"
}
fresh_cache() {
  rm -rf "$cfg"
  mkdir -p "$cfg"
}

fresh_cache
assert_eq "no live limits and no cache: both windows read --" \
  "Opus ・ --%(session)・--%(week)" "$(limits "")"
assert_eq "live limits render rounded" \
  "Opus ・ 11%(session)・20%(week)" \
  "$(limits "{\"five_hour\":{\"used_percentage\":10.6,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}")"
assert_eq "a later session without live limits shows the cached ones" \
  "Opus ・ 11%(session)・20%(week)" "$(limits "")"
assert_eq "a window missing from live limits falls back to the cache" \
  "Opus ・ 30%(session)・20%(week)" \
  "$(limits "{\"five_hour\":{\"used_percentage\":30,\"resets_at\":$future}}")"
assert_eq "the cache took the newer live window" \
  "Opus ・ 30%(session)・20%(week)" "$(limits "")"

fresh_cache
limits "{\"five_hour\":{\"used_percentage\":80,\"resets_at\":$past},\"seven_day\":{\"used_percentage\":20,\"resets_at\":$future}}" >/dev/null
assert_eq "a cached window past its reset reads 0" \
  "Opus ・ 0%(session)・20%(week)" "$(limits "")"

fresh_cache
printf 'not json' >"$cache"
assert_eq "a corrupt cache reads as no cache" \
  "Opus ・ --%(session)・--%(week)" "$(limits "")"
limits "{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$future}}" >/dev/null
assert_eq "live limits replace a corrupt cache" \
  "Opus ・ 5%(session)・--%(week)" "$(limits "")"

fresh_cache
assert_eq "a full session window: highlighted as on credits" \
  "Opus ・ ${red} 100%(session)・40%(week) credits ${reset}" \
  "$(limits "{\"five_hour\":{\"used_percentage\":100,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":40,\"resets_at\":$future}}")"
fresh_cache
limits "{\"five_hour\":{\"used_percentage\":3,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":100,\"resets_at\":$future}}" >/dev/null
assert_eq "a full week window from the cache: still highlighted" \
  "Opus ・ ${red} 3%(session)・100%(week) credits ${reset}" "$(limits "")"
assert_eq "99.6 rounds to 100% but is not full: no highlight" \
  "Opus ・ 100%(session)・3%(week)" \
  "$(limits "{\"five_hour\":{\"used_percentage\":99.6,\"resets_at\":$future},\"seven_day\":{\"used_percentage\":3,\"resets_at\":$future}}")"

fresh_cache
limits "{\"five_hour\":{\"used_percentage\":100,\"resets_at\":$past},\"seven_day\":{\"used_percentage\":40,\"resets_at\":$future}}" >/dev/null
assert_eq "a full window that has since reset: no highlight" \
  "Opus ・ 0%(session)・40%(week)" "$(limits "")"
rm -rf "$cfg"

# row1 <dir> -- the first row for a session launched and working in <dir>.
row1() {
  local out
  out=$(jq -n --arg d "$1" '{workspace:{project_dir:$d,current_dir:$d},model:{display_name:"Opus"}}' |
    env -u CLAUDE_CONFIG_DIR HOME="$home" "$SCRIPT")
  printf '%s' "${out%%$'\n'*}"
}

# The suite runs the script through its #!/bin/bash shebang, so on macOS these
# also pin bash 3.2, where a \~ substitution printed the backslash.
# shellcheck disable=SC2088 # a literal ~ is the expected output, not a path
assert_eq "a dir under \$HOME abbreviates to ~/" "~/proj" "$(row1 "$home/proj")"
assert_eq "\$HOME itself abbreviates to ~" "~" "$(row1 "$home")"
assert_eq "a sibling sharing \$HOME's prefix stays absolute" \
  "$home-other/x" "$(row1 "$home-other/x")"

test_summary
