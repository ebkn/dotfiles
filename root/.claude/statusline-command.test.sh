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

assert_eq "CLAUDE_CONFIG_DIR unset: no segment, no separator" "Opus" "$(row2)"
assert_eq "CLAUDE_CONFIG_DIR=~/.claude is the default: no segment" \
  "Opus" "$(row2 "$home/.claude")"
assert_eq "a trailing slash on ~/.claude is still the default" \
  "Opus" "$(row2 "$home/.claude/")"
assert_eq "another config dir: its name" \
  "Opus ・ .claude-work" "$(row2 "$home/.claude-work")"
assert_eq "a trailing slash on another dir does not empty its name" \
  "Opus ・ .claude-work" "$(row2 "$home/.claude-work/")"
assert_eq "a config dir outside \$HOME: its name too" \
  "Opus ・ elsewhere" "$(row2 "$TEST_TMPDIR/elsewhere")"

# The segment goes last, after every other part, with one separator each.
full='{"workspace":{"project_dir":"/p","current_dir":"/p"},"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":20}}}'
out=$(printf '%s' "$full" | HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude-work" "$SCRIPT")
assert_eq "with every part present the config dir comes last" \
  "Opus ・ high ・ 42% Used ・ 10%(session)・20%(week) ・ .claude-work" \
  "${out#*$'\n'}"

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
