#!/bin/bash
# Pins two parts of statusline-command.sh's output. The account segment of the
# second row: the email of the account the session is logged in as, read from
# the global config of the active config dir, and that dir itself whenever
# CLAUDE_CONFIG_DIR points somewhere other than ~/.claude. And the ~
# abbreviation of paths, which both rows use. Every failure here is silent -- a
# wrong path just drops the segment -- so each case asserts on the rendered row.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline-command.sh"
# shellcheck source=bin/test-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../bin/test-lib.sh" || exit 2

test_tmpdir
home="$TEST_TMPDIR/home"
mkdir -p "$home/.claude" "$home/.claude-work" "$home/.claude-nologin"
printf '{"oauthAccount":{"emailAddress":"me@example.com"}}' >"$home/.claude.json"
# The same dir's .claude.json differs from ~/.claude.json on purpose: an unset
# CLAUDE_CONFIG_DIR must read the latter, an explicit ~/.claude the former.
printf '{"oauthAccount":{"emailAddress":"inner@example.com"}}' >"$home/.claude/.claude.json"
printf '{"oauthAccount":{"emailAddress":"work@example.com"}}' >"$home/.claude-work/.claude.json"
printf '{}' >"$home/.claude-nologin/.claude.json"

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

assert_eq "default config dir: email only, read from ~/.claude.json" \
  "Opus ・ me@example.com" "$(row2)"
assert_eq "CLAUDE_CONFIG_DIR=~/.claude is the default: no dir shown" \
  "Opus ・ inner@example.com" "$(row2 "$home/.claude")"
assert_eq "a trailing slash on ~/.claude is still the default" \
  "Opus ・ inner@example.com" "$(row2 "$home/.claude/")"
assert_eq "another config dir: its email and the dir, ~-abbreviated" \
  "Opus ・ work@example.com (~/.claude-work)" "$(row2 "$home/.claude-work")"
assert_eq "no logged-in account: the dir alone" \
  "Opus ・ (~/.claude-nologin)" "$(row2 "$home/.claude-nologin")"
assert_eq "a config dir with no .claude.json: the dir alone" \
  "Opus ・ (~/.claude-missing)" "$(row2 "$home/.claude-missing")"

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
