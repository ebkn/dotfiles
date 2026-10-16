#!/bin/bash
# Exercises git-dash-c-allow.sh, a hook that emits "allow". ALLOW = the hook
# approves the command. DEFER = it stays silent and the normal permission flow
# decides.
#
# As with approve-multiline-commands.test.sh, the DEFER half is the half that
# matters: an over-approval is silent by construction. Each DEFER case is one
# way the command could leave the project or run something no rule allows. The
# ALLOW half is what stops "defer on everything" from passing.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-dash-c-allow.sh"

pass=0
fail=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Physical, so the fixture paths compare as the hook resolves them (/tmp is a
# symlink on macOS).
TMP=$(cd -P "$TMP" && pwd -P)

PROJ="$TMP/proj"
mkdir -p "$PROJ/sub" "$PROJ/a b" "$TMP/outside" "$PROJ/.claude"
ln -s "$TMP/outside" "$PROJ/link-out"
ln -s "$PROJ/sub" "$PROJ/link-in"

# User-level settings: the only rules the hook may read.
mkdir -p "$TMP/home/.claude"
jq -n '{permissions: {allow: [
  "Bash(git status*)", "Bash(git log *)", "Bash(git add *)", "Bash(git diff*)",
  "Bash(git commit -m *)", "Bash(git push)", "Bash(git rev-parse:*)",
  "Bash(git --no-pager log*)", "Bash(npm test)"
]}}' >"$TMP/home/.claude/settings.json"

# Project settings are untrusted until the trust dialog is accepted, so a rule
# here must never be honoured.
jq -n '{permissions: {allow: ["Bash(git reset *)"]}}' >"$PROJ/.claude/settings.json"

# A user whose only -C rule is the wildcard kind this hook exists to replace.
mkdir -p "$TMP/home-wild/.claude"
jq -n '{permissions: {allow: ["Bash(git -C * status*)", "Bash(git * status*)"]}}' \
  >"$TMP/home-wild/.claude/settings.json"

# run <cwd> <command> [home] [project]
run() {
  local cwd=$1 cmd=$2 home=${3:-$TMP/home} project=${4-$PROJ}
  jq -n --arg c "$cmd" --arg d "$cwd" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' |
    HOME=$home CLAUDE_PROJECT_DIR=$project "$HOOK" 2>/dev/null
}

check() {
  local expect=$1 label=$2 cmd=$3 cwd=${4:-$PROJ} home=${5:-$TMP/home} project=${6-$PROJ} out rc got
  out=$(run "$cwd" "$cmd" "$home" "$project") && rc=0 || rc=$?
  if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q '"permissionDecision": *"allow"'; then
    got=ALLOW
  elif [[ $rc -eq 0 && -z "$out" ]]; then
    got=DEFER
  else
    got="ERROR(rc=$rc)"
  fi
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass + 1))
    printf '  ok   %-5s %s\n' "$got" "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL want=%s got=%s  %s\n' "$expect" "$got" "$label"
  fi
}

echo "-- must ALLOW: -C inside the project, rest matching a user rule --"
check ALLOW 'relative path' 'git -C sub status'
check ALLOW 'absolute path' "git -C $PROJ/sub log --oneline"
check ALLOW 'the project root itself' 'git -C . diff'
check ALLOW 'quoted path with a space' 'git -C "a b" status'
check ALLOW 'chained -C resolved as git does' 'git -C sub -C .. status'
check ALLOW 'symlink that stays inside' 'git -C link-in status'
check ALLOW 'from a subdirectory, up to the root' 'git -C .. status' "$PROJ/sub"
check ALLOW 'word-prefix rule matches the bare command' 'git -C sub log'
check ALLOW 'exact rule' 'git -C sub push'
check ALLOW ':* rule' 'git -C sub rev-parse HEAD'
check ALLOW 'a global option the rule itself names' 'git -C sub --no-pager log -1'
check ALLOW 'every segment approved' 'git -C sub add . && git -C sub commit -m "x"'
check ALLOW 'a plain git segment matching a rule' 'git -C sub status && git log -1'

echo "-- must DEFER: no -C, so the rules already decide --"
check DEFER 'plain git' 'git status'
check DEFER 'not git at all' 'npm test'

echo "-- must DEFER: the directory leaves the project or cannot be resolved --"
check DEFER 'parent of the project' 'git -C .. status'
check DEFER 'outside, absolute' "git -C $TMP/outside status"
check DEFER 'symlink that escapes' 'git -C link-out status'
check DEFER 'escape through a chain' 'git -C sub -C ../.. status'
check DEFER 'a sibling sharing the prefix' "git -C ${PROJ}x status"
check DEFER 'nonexistent directory' 'git -C missing status'
check DEFER '-C with no value' 'git -C'
check DEFER 'tilde is not expanded here' 'git -C ~ status'

echo "-- must DEFER: the rest matches no usable rule --"
check DEFER 'no rule for the subcommand' 'git -C sub reset --hard'
check DEFER 'exact rule, extra words' 'git -C sub push --force'
check DEFER 'a dangerous global option after -C' 'git -C sub -c core.fsmonitor=x status'
check DEFER 'project settings are not read' 'git -C sub reset --hard HEAD'
check DEFER 'wildcard -C rules are not honoured' 'git -C sub status' "$PROJ" "$TMP/home-wild"
check DEFER 'a quoted subcommand containing a space' 'git -C sub "log --output=x"'

echo "-- must DEFER: a segment that is not an approved git --"
check DEFER 'a non-git segment' 'git -C sub status; rm -rf x'
check DEFER 'a non-git segment, even an allowed one' 'git -C sub status && npm test'
check DEFER 'a wrapper' 'timeout 5 git -C sub status'
check DEFER 'a path-qualified git' '/usr/bin/git -C sub status'
check DEFER 'one segment outside the project' 'git -C sub status && git -C .. status'

echo "-- must DEFER: argv the scanner cannot know --"
# shellcheck disable=SC2016 # literal command text under test
check DEFER 'a substitution as the path' 'git -C "$(pwd)" status'
# shellcheck disable=SC2016 # literal command text under test
check DEFER 'a parameter as the path' 'git -C $D status'
check DEFER 'a redirection' 'git -C sub status > out'
check DEFER 'a subshell' '(git -C sub status)'
check DEFER 'an unterminated quote' 'git -C "sub status'

echo "-- must DEFER: no project to compare against --"
check DEFER 'CLAUDE_PROJECT_DIR unset' 'git -C sub status' "$PROJ" "$TMP/home" ''
check DEFER 'no user settings file' 'git -C sub status' "$PROJ" "$TMP/nohome"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
