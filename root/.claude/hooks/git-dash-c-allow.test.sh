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
# Directories named as the shell would expand them, as a cloned repository can
# ship: read literally they are inside the project, while the shell runs git in
# $HOME, in what `b` points at, or in the parent.
mkdir -p "$PROJ/~" "$PROJ/[b]" "$PROJ/{..,}" "$PROJ/x=~"
ln -s "$TMP/outside" "$PROJ/b"

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

# A user whose only -C rule is the wildcard kind this hook exists to replace,
# plus rules whose words hold glob characters, which must compare literally.
mkdir -p "$TMP/home-wild/.claude"
jq -n '{permissions: {allow: [
  "Bash(git -C * status*)", "Bash(git * status*)", "Bash(git log [a]*)", "Bash(git l?g *)"
]}}' >"$TMP/home-wild/.claude/settings.json"

# Settings that are not usable: not JSON, and an allow that is not a list.
mkdir -p "$TMP/home-bad/.claude" "$TMP/home-odd/.claude"
printf 'not json' >"$TMP/home-bad/.claude/settings.json"
jq -n '{permissions: {allow: "Bash(git status*)"}}' >"$TMP/home-odd/.claude/settings.json"

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
check DEFER '-C glued to its value, which git does not accept' 'git -Csub status'
check ALLOW 'an empty -C, from inside the project' 'git -C "" status'
check DEFER 'an empty -C, from outside it' 'git -C "" status' "$TMP/outside"

echo "-- must DEFER: a word the shell expands, even when read literally it is inside --"
check DEFER 'a tilde' 'git -C ~ status'
check DEFER 'a glob' 'git -C [b] status'
check DEFER 'a brace expansion' 'git -C {..,} status'
check DEFER 'a brace expansion with its insides quoted' 'git -C {"..",} status'
check DEFER 'a brace expansion with its insides escaped' 'git -C {.\.,} status'
check DEFER "a brace expansion with its insides single-quoted" "git -C {'..',} status"
check DEFER 'a tilde after =' 'git -C x=~ status'
check DEFER 'a glob anywhere in the segment' 'git -C sub add *.sh'
# Not expansions: a tilde past the start, braces with no comma or `..`.
check ALLOW 'HEAD~1' 'git -C sub diff HEAD~1'
check ALLOW 'a reflog brace' 'git -C sub log HEAD@{1}'

echo "-- must DEFER: the rest matches no usable rule --"
check DEFER 'no rule for the subcommand' 'git -C sub reset --hard'
check DEFER 'exact rule, extra words' 'git -C sub push --force'
check DEFER 'a dangerous global option after -C' 'git -C sub -c core.fsmonitor=x status'
check DEFER 'project settings are not read' 'git -C sub reset --hard HEAD'
check DEFER 'wildcard -C rules are not honoured' 'git -C sub status' "$PROJ" "$TMP/home-wild"
# With only wildcard rules on offer, the options they let through stay out.
check DEFER 'a wildcard rule does not let --exec-path in' 'git -C sub --exec-path=/x status' "$PROJ" "$TMP/home-wild"
check DEFER 'nor -c' 'git -C sub -c core.fsmonitor=x status' "$PROJ" "$TMP/home-wild"
check DEFER 'a rule word with [ ] compares literally' 'git -C sub log ab' "$PROJ" "$TMP/home-wild"
check DEFER 'a rule word with ? compares literally' 'git -C sub log x' "$PROJ" "$TMP/home-wild"
check DEFER 'a quoted subcommand containing a space' 'git -C sub "log --output=x"'

echo "-- must DEFER: a segment that is not an approved git --"
check DEFER 'a non-git segment' 'git -C sub status; rm -rf x'
check DEFER 'a non-git segment, even an allowed one' 'git -C sub status && npm test'
check DEFER 'a wrapper' 'timeout 5 git -C sub status'
check DEFER 'an assignment that redirects git' 'GIT_DIR=/x git -C . status'
check DEFER 'an assignment that configures git' "GIT_CONFIG_PARAMETERS=\"'core.fsmonitor=x'\" git -C sub status"
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
check DEFER 'settings that are not JSON' 'git -C sub status' "$PROJ" "$TMP/home-bad"
check DEFER 'an allow that is not a list' 'git -C sub status' "$PROJ" "$TMP/home-odd"
no_cwd=$(jq -n '{tool_name:"Bash", tool_input:{command:"git -C sub status"}}' |
  HOME=$TMP/home CLAUDE_PROJECT_DIR=$PROJ "$HOOK" 2>/dev/null) && rc=0 || rc=$?
if [[ $rc -eq 0 && -z "$no_cwd" ]]; then
  pass=$((pass + 1))
  echo "  ok   DEFER no cwd in the input"
else
  fail=$((fail + 1))
  printf '  FAIL want=DEFER got rc=%s out=%s  no cwd in the input\n' "$rc" "$no_cwd"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
