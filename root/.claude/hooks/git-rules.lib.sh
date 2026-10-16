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

# git_rules_load: read the deny rules, then the ask rules, into the parallel
# arrays GIT_RULE_P (pattern), GIT_RULE_R (rule as written) and GIT_RULE_K
# (deny or ask), once per hook run. Arrays rather than the text, because a hook
# matches for each of up to 1000 segments: walking the text per call, by
# slicing or by `read <<<` (a temporary file on bash 3.2), spent seconds of the
# timeout there.
GIT_RULE_P=()
GIT_RULE_R=()
GIT_RULE_K=()
git_rules_load() {
  local kind text p rule
  GIT_RULE_P=() GIT_RULE_R=() GIT_RULE_K=()
  for kind in deny ask; do
    text=$(git_rule_patterns "$kind")
    [[ -n "$text" ]] || continue
    while IFS= read -r p && IFS= read -r rule; do
      GIT_RULE_P+=("$p") GIT_RULE_R+=("$rule") GIT_RULE_K+=("$kind")
    done <<<"$text"
  done
}

# git_rule_match <words...>: 0 when the words, joined by single spaces, match a
# loaded rule. GIT_RULE_KIND and GIT_RULE_MATCHED then name it, a deny rule
# ahead of any ask rule, since deny rules are loaded first.
#
# Before git_rules_load it matches nothing, and an allow hook reads that as "no
# rule refuses this" -- an approval. So load before the first match, in the same
# shell: a load inside `$(...)` is lost with the subshell.
GIT_RULE_KIND=""
GIT_RULE_MATCHED=""
git_rule_match() {
  local line="$*" i=0 n=${#GIT_RULE_P[@]}
  while ((i < n)); do
    # shellcheck disable=SC2053 # the pattern is one, deliberately unquoted
    if [[ "$line" == ${GIT_RULE_P[i]} ]]; then
      # shellcheck disable=SC2034 # outputs, read by the sourcing hook
      GIT_RULE_KIND=${GIT_RULE_K[i]} GIT_RULE_MATCHED=${GIT_RULE_R[i]}
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}
