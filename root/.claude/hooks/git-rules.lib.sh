# shellcheck shell=bash
# The settings' git deny and ask rules, as patterns a hook can apply to the
# `git <subcommand> ...` that a `git -C <dir> <subcommand> ...` runs.
#
# Claude Code matches a rule against the command as written, so a deny rule
# for `git push --force*` never matches `git -C x push --force`. settings.json
# keeps no `git -C *` copies of its rules (root/README.md, git permissions):
# git-guard.sh applies the rules to the -C form instead, and
# git-dash-c-allow.sh stays silent on a command they cover.
#
# Every settings layer is read -- the user's, the project's and its local one
# -- as Claude Code applies all three. Unlike allow rules (see
# git-dash-c-allow.sh), a cloned repository's own deny and ask rules are safe
# to honour: they can only refuse more. Managed settings are not read.
#
# A `*` matches any text, spaces included, wherever it stands, as in Claude
# Code; a trailing ` *` or `:*` also matches the bare command. Everything else
# compares literally -- a `[` in a rule is no bracket expression. Matching more
# than Claude Code would is the safe direction for a deny or an ask, so where
# its matcher is not documented this one is the wider.
#
# Sourced by git-guard.sh and git-dash-c-allow.sh; tested through both.

# git_rule_patterns <deny|ask>: each git rule of that kind in the settings, as
# two lines -- a bash pattern, then the rule as written, for a reason to quote.
# A file that is missing or not JSON holds no rules.
git_rule_patterns() {
  local f
  for f in "$HOME/.claude/settings.json" \
    ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR/.claude/settings.json" "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"}; do
    [[ -f "$f" ]] || continue
    jq -r --arg k "$1" '
      .permissions[$k]? | arrays | .[] | strings
      | select(test("^Bash\\(git([ :*]|\\))"))
      # Two lines to a rule: a newline in one would make patterns of its
      # pieces -- a bare `*` among them -- so such a rule is not read.
      | select(contains("\n") | not)
      | . as $rule
      | ltrimstr("Bash(") | rtrimstr(")")
      | if endswith(":*") then rtrimstr(":*") + " *" else . end
      | (split("*") | map(gsub("(?<c>[^A-Za-z0-9 ])"; "\\\(.c)")) | join("*")) as $p
      | ($p, $rule),
        (if endswith(" *") then ($p | rtrimstr(" *")), $rule else empty end)
    ' "$f" 2>/dev/null || true
  done
}

# git_rule_match <patterns> <words...>: 0 when the words, joined by single
# spaces, match a pattern from git_rule_patterns; GIT_RULE_MATCHED is then the
# rule as written.
GIT_RULE_MATCHED=""
git_rule_match() {
  local patterns=$1 p rule
  shift
  local line="$*"
  while IFS= read -r p && IFS= read -r rule; do
    # shellcheck disable=SC2053 # $p is a pattern, deliberately unquoted
    if [[ "$line" == $p ]]; then
      # shellcheck disable=SC2034 # an output, read by the sourcing hook
      GIT_RULE_MATCHED=$rule
      return 0
    fi
  done <<<"$patterns"
  return 1
}
