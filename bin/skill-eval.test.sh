#!/bin/bash
#
# skill-eval.test.sh
#
# Pins the runner, because the runner is the only instrument for "did that
# SKILL.md edit help", and every way it breaks produces a green run that
# measured nothing:
#   - drop allowed-tools on the way to `claude -p` and the skill runs with the
#     session's own permissions, so every "it did not write" assertion passes
#     for the wrong reason
#   - carry evals/ into the fixture and the model can read the grader it is
#     being graded by
#   - leave the .claude/ and bin/ we brought in visible to git and the fixture's
#     status is no longer the fixture's
#   - swallow an assertion FAIL, or a non-zero `claude -p`, and a broken case
#     reports PASS
#   - let an unreachable check_llm judge count as a pass and an LLM-graded case
#     asserts nothing at all
#
# `claude` is replaced with a stub on PATH, so this needs no credentials, makes
# no API call and costs nothing. Written for bash 3.2 (macOS): no mapfile, no
# associative arrays.

set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

RUN=bin/skill-eval
fails=0

t() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

contains() {
  case "$3" in
    *"$2"*) printf 'ok   %s\n' "$1" ;;
    *)
      printf 'FAIL %s\n       missing: %s\n       in:      %s\n' "$1" "$2" "$3"
      fails=$((fails + 1))
      ;;
  esac
}

absent() {
  case "$3" in
    *"$2"*)
      printf 'FAIL %s\n       unexpected: %s\n' "$1" "$2"
      fails=$((fails + 1))
      ;;
    *) printf 'ok   %s\n' "$1" ;;
  esac
}

# The argument following <flag> in a stub's argv file (one argument per line),
# or <absent>. Values are what decide a boundary -- `--permission-mode
# bypassPermissions` carries the same flag name as `acceptEdits` -- and an
# empty value (the judge's `--tools ""`) must stay distinguishable from no flag.
flag_value() { # <argv file> <flag>
  awk -v f="$2" 'found { print; exit } $0 == f { found = 1 } END { if (!found) print "<absent>" }' "$1"
}

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

# --- the grading library, on its own ------------------------------------------
# Every eval case grades through bin/skill-eval-assert.sh, and the runner cases
# below only reach the helpers one stub case happens to call. The ordering
# helpers are the read-only boundary checks of review-test and review-design,
# and their graders read an EMPTY index as "never happened" -- so a helper that
# always returned empty would pass every one of those checks vacuously. Each is
# run here against a transcript whose indices are known.
lib="$DIR/lib"
mkdir -p "$lib"
cat >"$lib/transcript.jsonl" <<'EOF'
{"type":"system","subtype":"init"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"a.sh"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"## Test review: a.sh"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"bash a.test.sh"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.sh","old_string":"## Test review","new_string":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m fix\nbody"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"review-test"}}]}}
{"type":"result","result":"all done","permission_denials":[{"tool_name":"Write"},{"tool_name":"Edit"}]}
EOF
tail -n 1 "$lib/transcript.jsonl" >"$lib/result.json"
# lib_eval <snippet> -- run it with the library sourced against that transcript.
lib_eval() {
  SKILL_EVAL_TRANSCRIPT="$lib/transcript.jsonl" SKILL_EVAL_RESULT_FILE="$lib/result.json" \
    bash -c '. bin/skill-eval-assert.sh; '"$1" 2>&1
}
t "transcript_first_tool_index finds the first call" "1" "$(lib_eval 'transcript_first_tool_index Read')"
t "and the first of several" "3" "$(lib_eval 'transcript_first_tool_index Bash')"
t "and is empty for a tool never called" "" "$(lib_eval 'transcript_first_tool_index Write')"
t "transcript_first_text_index matches text blocks" "2" "$(lib_eval 'transcript_first_text_index "^## Test review"')"
# Only index 4 -- a tool call's input -- holds the bare heading, which must not
# count as having reported it.
t "and ignores the same words inside a tool input" "" "$(lib_eval 'transcript_first_text_index "^## Test review$"')"
t "transcript_first_command_index matches one kind of command" "5" "$(lib_eval 'transcript_first_command_index "^git commit"')"
t "and is empty when no command matches" "" "$(lib_eval 'transcript_first_command_index "^git push"')"
t "transcript_tool_uses_precede: Edit at 4 precedes 4" "yes" "$(lib_eval 'transcript_tool_uses_precede Edit 4 && echo yes || echo no')"
t "but not 3" "no" "$(lib_eval 'transcript_tool_uses_precede Edit 3 && echo yes || echo no')"
t "and a tool never called precedes nothing" "no" "$(lib_eval 'transcript_tool_uses_precede Write 99 && echo yes || echo no')"
t "transcript_tool_uses counts calls" "2" "$(lib_eval 'transcript_tool_uses Bash')"
t "transcript_commands folds newlines, one call per line" 'bash a.test.sh
git commit -m fix\nbody' "$(lib_eval 'transcript_commands')"
t "transcript_skill_uses counts the Skill tool" "1" "$(lib_eval 'transcript_skill_uses review-test')"
# The Skill tool's input key has changed between versions and the name can come
# as "/<name>", so the reader matches any string value either way. Every other
# fixture uses {skill: ...}, which a "simplified" `.input.skill == $name` also
# passes -- while reading every other shape as 0 uses, which grades a skill that
# fired as one that did not. A Skill call for another skill, and the name in a
# different tool's input, must not count.
cat >"$lib/skill-uses.jsonl" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"review-test"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"command":"review-test","args":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"/review-test"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"commit"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"review-test"}}]}}
EOF
t "transcript_skill_uses counts any input key, and the /<name> form" "3" \
  "$(SKILL_EVAL_TRANSCRIPT="$lib/skill-uses.jsonl" bash -c '. bin/skill-eval-assert.sh; transcript_skill_uses review-test' 2>&1)"
t "transcript_denials counts refusals" "2" "$(lib_eval 'transcript_denials')"
t "transcript_result_text is the final response" "all done" "$(lib_eval 'transcript_result_text')"

# Each check in both directions, and the flag that skill_eval_finish turns into
# the exit status: a check that printed FAIL but forgot to set it would let the
# case pass.
for c in 'check l true' 'check_eq l a a' 'check_match l "^a" abc' 'check_not_match l "^z" abc'; do
  t "$c passes and leaves the case passing" "PASS  l|0" \
    "$(lib_eval "$c; printf '|'; (skill_eval_finish); echo \$?" | tr -d '\n')"
done
for c in 'check l false' 'check_eq l a b' 'check_match l "^z" abc' 'check_not_match l "^a" abc'; do
  out=$(lib_eval "$c; (skill_eval_finish); echo \"|\$?\"" | tr -d '\n')
  case "$out" in
    FAIL\ \ l*"|1") printf 'ok   %s fails and fails the case\n' "$c" ;;
    *)
      printf 'FAIL %s fails and fails the case\n       got: %s\n' "$c" "$out"
      fails=$((fails + 1))
      ;;
  esac
done

# The claude stub records the arguments and the state of the fixture it was
# called in, optionally acts on the fixture ($STUB_CLAUDE_ACTION), and returns
# the smallest stream-json the runner will accept.
cat >"$DIR/claude" <<'STUB'
#!/bin/bash
set -eo pipefail
mkdir -p "$STUB_CLAUDE_OUT"
# Called as the check_llm judge (--json-schema): record the prompt it was given
# and answer with a fixed verdict, switchable via $STUB_JUDGE_PASS. An empty
# $STUB_JUDGE_PASS stands for a judge that produced nothing.
for arg in "$@"; do
  if [ "$arg" = "--json-schema" ]; then
    printf '%s\n' "$@" >"$STUB_CLAUDE_OUT/judge-args"
    cat >"$STUB_CLAUDE_OUT/judge-stdin"
    if [ -z "${STUB_JUDGE_PASS-true}" ]; then
      printf '\n'
      exit 0
    fi
    printf '{"type":"result","subtype":"success","structured_output":{"pass":%s,"reason":"stub reason"},"total_cost_usd":0.01}\n' "${STUB_JUDGE_PASS-true}"
    exit 0
  fi
done
printf '%s\n' "$@" >"$STUB_CLAUDE_OUT/args"
pwd >"$STUB_CLAUDE_OUT/cwd"
printf '%s\n' "${PATH%%:*}" >"$STUB_CLAUDE_OUT/path_head"
git status --porcelain >"$STUB_CLAUDE_OUT/status" 2>/dev/null || true
git ls-files >"$STUB_CLAUDE_OUT/tracked" 2>/dev/null || true
if [ -e ".claude/skills/$STUB_SKILL/evals" ]; then
  echo present >"$STUB_CLAUDE_OUT/evals"
else
  echo absent >"$STUB_CLAUDE_OUT/evals"
fi
# What the model is given to evaluate: the skill itself, as a real copy, with
# the files beside SKILL.md that it refers to (init-project reads references/).
if [ -f ".claude/skills/$STUB_SKILL/SKILL.md" ] && [ -f ".claude/skills/$STUB_SKILL/references/note.md" ] &&
  [ ! -L ".claude/skills/$STUB_SKILL" ]; then
  echo copied >"$STUB_CLAUDE_OUT/skill"
else
  echo missing >"$STUB_CLAUDE_OUT/skill"
fi
find .claude -name evals >"$STUB_CLAUDE_OUT/evals_anywhere" 2>/dev/null || true
cp bin/repo_root "$STUB_CLAUDE_OUT/repo_root" 2>/dev/null || echo none >"$STUB_CLAUDE_OUT/repo_root"
if [ -f CLAUDE.md ]; then
  head -n 1 CLAUDE.md >"$STUB_CLAUDE_OUT/claude_md"
else
  echo absent >"$STUB_CLAUDE_OUT/claude_md"
fi
if [ -n "${STUB_CLAUDE_ACTION:-}" ]; then
  bash -c "$STUB_CLAUDE_ACTION"
fi
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}]}}\n'
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"stub-skill"}}]}}\n'
printf '{"type":"result","subtype":"success","result":"done","total_cost_usd":0.25,"duration_ms":1500,"permission_denials":[]}\n'
if [ -n "${STUB_CLAUDE_EXIT:-}" ]; then
  exit "$STUB_CLAUDE_EXIT"
fi
STUB
chmod +x "$DIR/claude"

# A stub skill whose allowed-tools contains an entry with spaces in it, so the
# `, ` split is exercised rather than assumed.
skills_dir="$DIR/skills"
skill="stub-skill"
mkdir -p "$skills_dir/$skill/evals/case-a" "$skills_dir/$skill/evals/case-b" "$skills_dir/$skill/evals/case-c"
mkdir -p "$skills_dir/$skill/references"
printf 'supporting file\n' >"$skills_dir/$skill/references/note.md"
cat >"$skills_dir/$skill/SKILL.md" <<'EOF'
---
name: stub-skill
description: test
allowed-tools: Bash(git status *), Bash(git commit *), Read
---

body
EOF
cat >"$skills_dir/$skill/evals/case-a/prompt.md" <<'EOF'
---
name: case-a
---
/stub-skill do it
EOF
cat >"$skills_dir/$skill/evals/case-a/scaffold.sh" <<'EOF'
#!/bin/bash
set -eo pipefail
[ -z "${STUB_SCAFFOLD_CWD:-}" ] || pwd -P >"$STUB_SCAFFOLD_CWD"
[ -z "${STUB_SCAFFOLD_FAIL:-}" ] || exit 4
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
echo hello >tracked.txt
skill_eval_init_repo
echo changed >tracked.txt
mkdir -p bin
printf '%s\n' "$SKILL_EVAL_REPO_ROOT" >bin/repo_root
# Succeeds, but leaves .git/info a plain file: the runner's own append to
# .git/info/exclude then fails under set -e -- a mid-case exit that is not
# the scaffold's.
[ -z "${STUB_SCAFFOLD_BREAK_GIT_INFO:-}" ] || { rm -rf .git/info; : >.git/info; }
EOF
cat >"$skills_dir/$skill/evals/case-a/assert.sh" <<'EOF'
#!/bin/bash
set -eo pipefail
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
[ -z "${STUB_ASSERT_CRASH:-}" ] || exit 3
check_eq "denials" 0 "$(transcript_denials)"
check_match "commands" 'git status' "$(transcript_commands)"
check_eq "skill uses" 1 "$(transcript_skill_uses stub-skill)"
check_eq "other skill uses" 0 "$(transcript_skill_uses some-other-skill)"
if [ -n "${STUB_ASSERT_FAIL:-}" ]; then
  check "forced failure" false
fi
if [ -n "${STUB_USE_JUDGE:-}" ]; then
  check_llm "judged" "the rubric"
fi
[ -z "${STUB_NO_FINISH:-}" ] || exit 0
skill_eval_finish
EOF
cp "$skills_dir/$skill/evals/case-a/prompt.md" "$skills_dir/$skill/evals/case-b/prompt.md"
cp "$skills_dir/$skill/evals/case-a/scaffold.sh" "$skills_dir/$skill/evals/case-b/scaffold.sh"
cp "$skills_dir/$skill/evals/case-a/assert.sh" "$skills_dir/$skill/evals/case-b/assert.sh"

# case-c adds tools through prompt.md's frontmatter, the way a case that
# measures self-starting has to.
cat >"$skills_dir/$skill/evals/case-c/prompt.md" <<'EOF'
---
name: case-c
allowed_tools: Skill, Write
max_turns: 123
budget_usd: 4.5
---
write something
EOF
cp "$skills_dir/$skill/evals/case-a/scaffold.sh" "$skills_dir/$skill/evals/case-c/scaffold.sh"
cp "$skills_dir/$skill/evals/case-a/assert.sh" "$skills_dir/$skill/evals/case-c/assert.sh"

# The fallback assertions below name the built-in defaults, so the caller's own
# environment must not be in play: exported here, these would silently become
# the expected values and the test would pass while asserting nothing about the
# defaults it claims to pin.
unset SKILL_EVAL_MAX_TURNS SKILL_EVAL_BUDGET_USD

export SKILL_EVAL_CLAUDE_BIN="$DIR/claude"
export SKILL_EVAL_SKILLS_DIR="$skills_dir"
export SKILL_EVAL_OUT_DIR="$DIR/out"
export STUB_SKILL="$skill"
export STUB_CLAUDE_OUT="$DIR/stub"

# --- argument passing: allowed-tools arrive as separate arguments, the prompt
#     arrives without its frontmatter ---
rm -rf "$STUB_CLAUDE_OUT"
output="$($RUN "$skill" case-a --model haiku)"
args="$(cat "$STUB_CLAUDE_OUT/args")"
contains "allowed-tools entry 1 is passed" "Bash(git status *)" "$args"
contains "allowed-tools entry 2 is passed" "Bash(git commit *)" "$args"
contains "allowed-tools entry 3 is passed" "Read" "$args"
t "allowed-tools arrive as three separate arguments" "3" \
  "$(grep -c -e '^Bash(git' -e '^Read$' "$STUB_CLAUDE_OUT/args")"
contains "--model is passed through" "haiku" "$args"
contains "the prompt body is passed" "/stub-skill do it" "$args"
absent "prompt.md frontmatter stays out of the prompt" "name: case-a" "$args"
t "permission prompts are answered by refusing" "none" \
  "$(flag_value "$STUB_CLAUDE_OUT/args" --permission-prompts)"
t "edits are approved by acceptEdits, never by bypassing permissions" "acceptEdits" \
  "$(flag_value "$STUB_CLAUDE_OUT/args" --permission-mode)"
# Without it the caller's user settings load: hooks that emit "allow", and the
# root/CLAUDE.md rules skill-eval.md relies on staying out of the fixture.
t "only the fixture's project settings load" "project" \
  "$(flag_value "$STUB_CLAUDE_OUT/args" --setting-sources)"
t "the caller's MCP servers stay out" "1" \
  "$(grep -cxF -- --strict-mcp-config "$STUB_CLAUDE_OUT/args")"
# A scaffold puts its stubs (gh, a fake test runner) in bin/; they only stand in
# for the real tools if they come first.
t "the fixture's bin/ is first on PATH" "$(cat "$STUB_CLAUDE_OUT/cwd")/bin" \
  "$(cat "$STUB_CLAUDE_OUT/path_head")"
t "the working directory is removed after the run" "gone" \
  "$([ -e "$(cat "$STUB_CLAUDE_OUT/cwd")" ] && echo kept || echo gone)"
contains "the run is reported" "[PASS] $skill/case-a run-1" "$output"

# --- prompt.md's allowed_tools are added to the skill's own ---
rm -rf "$STUB_CLAUDE_OUT"
$RUN "$skill" case-c >/dev/null
args_c="$(cat "$STUB_CLAUDE_OUT/args")"
contains "a tool added by the case is passed" "Skill" "$args_c"
contains "a second tool added by the case is passed" "Write" "$args_c"
contains "the skill's own allowed-tools survive" "Bash(git status *)" "$args_c"
t "three from the skill plus two from the case, as five arguments" "5" \
  "$(grep -c -e '^Bash(git' -e '^Read$' -e '^Skill$' -e '^Write$' "$STUB_CLAUDE_OUT/args")"
absent "the allowed_tools line stays out of the prompt" "allowed_tools: Skill, Write" "$args_c"

# --- a case's own ceilings reach `claude -p` ---
# A case too long for the defaults is unrunnable without these: claude stops at
# --max-turns and exits non-zero, which the runner grades as FAIL. Asserted on
# the arguments, because a value that never leaves the runner changes nothing.
t "the case's max_turns is passed" "123" \
  "$(grep -A1 -e '^--max-turns$' "$STUB_CLAUDE_OUT/args" | tail -n 1)"
t "the case's budget_usd is passed" "4.5" \
  "$(grep -A1 -e '^--max-budget-usd$' "$STUB_CLAUDE_OUT/args" | tail -n 1)"
absent "the max_turns line stays out of the prompt" "max_turns: 123" "$args_c"

# A case that declares neither still gets the defaults, so adding the keys did
# not quietly make every other case unbounded.
rm -rf "$STUB_CLAUDE_OUT"
$RUN "$skill" case-a >/dev/null
t "a case with no max_turns falls back to the default" "40" \
  "$(grep -A1 -e '^--max-turns$' "$STUB_CLAUDE_OUT/args" | tail -n 1)"
t "a case with no budget_usd falls back to the default" "1" \
  "$(grep -A1 -e '^--max-budget-usd$' "$STUB_CLAUDE_OUT/args" | tail -n 1)"

# --- fixture isolation ---
# Its own run, rather than the recordings the defaults case left behind.
rm -rf "$STUB_CLAUDE_OUT"
$RUN "$skill" case-a >/dev/null
t "the .claude/ and bin/ we brought in stay out of git status" " M tracked.txt" \
  "$(cat "$STUB_CLAUDE_OUT/status")"
# A clean status alone cannot see this: the skill is copied in *before* the
# scaffold runs, so the scaffold's own first `git add -A` would commit it, and a
# tracked, unchanged file never shows in status. The skill under evaluation then
# sits in the fixture's history as if it were the user's code -- which a skill
# that reviews the repository's docs reads as its subject.
t "the fixture's first commit tracks nothing the runner carried in" "tracked.txt" \
  "$(cat "$STUB_CLAUDE_OUT/tracked")"
t "evals/ is not carried into the working directory" "absent" "$(cat "$STUB_CLAUDE_OUT/evals")"
# The absence above is also what no copy at all looks like, and a copy of the
# skill's contents lands its evals/ beside the skills, not inside one.
t "the skill under evaluation is copied in, SKILL.md and what is beside it" "copied" "$(cat "$STUB_CLAUDE_OUT/skill")"
t "and no evals/ is carried in anywhere" "" "$(cat "$STUB_CLAUDE_OUT/evals_anywhere")"
t "the scaffold can reach this repo through SKILL_EVAL_REPO_ROOT" "$PWD" \
  "$(cat "$STUB_CLAUDE_OUT/repo_root")"
cwd="$(cat "$STUB_CLAUDE_OUT/cwd")"
case "$cwd" in
  "$PWD"/*)
    printf 'FAIL the working directory was created inside the repo: %s\n' "$cwd"
    fails=$((fails + 1))
    ;;
  *) printf 'ok   the working directory is outside the repo\n' ;;
esac

# `git add -A` inside the fixture must not reach them either: exclude, not just
# an untracked listing that happens to look clean.
rm -rf "$STUB_CLAUDE_OUT"
# shellcheck disable=SC2016  # expanded by the stub's own shell, not this one
STUB_CLAUDE_ACTION='git add -A && git commit -q -m "feat: all" && git show --format= --name-only HEAD >"$STUB_CLAUDE_OUT/committed"' \
  $RUN "$skill" case-a >/dev/null
t "git add -A in the fixture commits neither .claude/ nor bin/" "tracked.txt" \
  "$(cat "$STUB_CLAUDE_OUT/committed")"

# --- artifacts ---
# A fresh output dir and one run, so the run dir is this run's and not whichever
# `find | head` reached first among the runs above. The skill commits, so the
# log can show what eval-base..HEAD holds: without the scaffold's eval-base tag
# that range fails and the file is empty, which an existence check accepts.
rm -rf "$STUB_CLAUDE_OUT" "$SKILL_EVAL_OUT_DIR"
# shellcheck disable=SC2016  # expanded by the stub's own shell, not this one
STUB_CLAUDE_ACTION='echo more >tracked.txt && git commit -qam "fix: by the skill"' \
  $RUN "$skill" case-a >/dev/null
run_dir="$(find "$SKILL_EVAL_OUT_DIR/$skill/case-a" -type d -name 'run-1')"
for artifact in transcript.jsonl result.json assert.log git-log.txt git-status.txt rounds.jsonl; do
  if [ -f "$run_dir/$artifact" ]; then
    printf 'ok   artifact %s is kept\n' "$artifact"
  else
    printf 'FAIL artifact %s is missing\n' "$artifact"
    fails=$((fails + 1))
  fi
done
contains "the grading log holds the PASS lines" "PASS  denials" "$(cat "$run_dir/assert.log")"
contains "git-log.txt holds the skill's own commit" "fix: by the skill" "$(cat "$run_dir/git-log.txt")"
absent "and not the scaffold's commit before eval-base" "chore: initial" "$(cat "$run_dir/git-log.txt")"
# The stub calls the skill once, with no result: one round, nothing recorded
# for time or tokens -- null, not 0, so "not measured" never reads as "free".
t "rounds.jsonl holds one round per call of the skill under evaluation" '[{"open":0,"tool_calls":0,"duration_ms":null,"tokens":null}]' \
  "$(jq -sc 'map({open, tool_calls, duration_ms, tokens})' "$run_dir/rounds.jsonl")"
absent "and leaves the report text in the transcript" '"report"' "$(cat "$run_dir/rounds.jsonl")"

# --- --keep leaves the working directory for inspection ---
rm -rf "$STUB_CLAUDE_OUT"
output="$($RUN "$skill" case-a --keep)"
kept="$(cat "$STUB_CLAUDE_OUT/cwd")"
contains "--keep names the working directory" "work: $kept" "$output"
t "and leaves it in place" "kept" "$([ -d "$kept" ] && echo kept || echo gone)"
rm -rf "$kept"

# --- a failed assertion reaches the exit status ---
rm -rf "$STUB_CLAUDE_OUT"
if output="$(STUB_ASSERT_FAIL=1 $RUN "$skill" case-a 2>&1)"; then
  printf 'FAIL a failed assertion still exited 0\n'
  fails=$((fails + 1))
else
  printf 'ok   a failed assertion exits non-zero\n'
fi
contains "the failing run is named" "[FAIL] $skill/case-a run-1" "$output"
contains "the failing assertion is named" "FAIL  forced failure" "$output"
contains "the summary counts it as 0/1" "0/1" "$output"

# --- a failed `claude -p` fails the case even when the assertions hold ---
rm -rf "$STUB_CLAUDE_OUT"
if output="$(STUB_CLAUDE_EXIT=3 $RUN "$skill" case-a 2>&1)"; then
  printf 'FAIL a non-zero claude -p still exited 0\n'
  fails=$((fails + 1))
else
  printf 'ok   a non-zero claude -p exits non-zero\n'
fi
contains "the claude failure is reported as a FAIL line" "FAIL  claude -p exited 3" "$output"

# --- case selection and --runs ---
rm -rf "$STUB_CLAUDE_OUT" "$SKILL_EVAL_OUT_DIR"
output="$($RUN "$skill" case-b --runs 2)"
contains "the named case runs twice" "[PASS] $skill/case-b run-2" "$output"
absent "a case that was not named does not run" "case-a" "$output"
contains "the summary counts 2/2" "2/2" "$output"
contains "cost is summed over the runs" "0.500" "$output"
contains "each run prints its rounds, with '-' for what was not recorded" "round: open=0 calls=0 ms=- tokens=-" "$output"
# Per run, never averaged: a case that usually takes 2 rounds and once took 6
# is the finding, and a mean would hide it.
contains "the summary lists the rounds of every run" "1,1" "$output"

rm -rf "$STUB_CLAUDE_OUT" "$SKILL_EVAL_OUT_DIR"
output="$($RUN "$skill")"
contains "with no case named, case-a runs" "[PASS] $skill/case-a run-1" "$output"
contains "with no case named, case-b runs" "[PASS] $skill/case-b run-1" "$output"

# --- check_llm ---
rm -rf "$STUB_CLAUDE_OUT" "$SKILL_EVAL_OUT_DIR"
output="$(STUB_USE_JUDGE=1 $RUN "$skill" case-a)"
judge_stdin="$(cat "$STUB_CLAUDE_OUT/judge-stdin")"
contains "the judge is given the rubric" "the rubric" "$judge_stdin"
contains "the judge is given the final response" "done" "$judge_stdin"
t "the judge runs without tools" "" "$(flag_value "$STUB_CLAUDE_OUT/judge-args" --tools)"
t "the judge reads no settings" "" "$(flag_value "$STUB_CLAUDE_OUT/judge-args" --setting-sources)"
contains "the judge's verdict carries its reason" "PASS  judged (judge: stub reason)" \
  "$(cat "$(find "$SKILL_EVAL_OUT_DIR/$skill/case-a" -name assert.log)")"
contains "the judge's cost is added to the case" "0.260" "$output"

rm -rf "$STUB_CLAUDE_OUT"
if output="$(STUB_USE_JUDGE=1 STUB_JUDGE_PASS=false $RUN "$skill" case-a 2>&1)"; then
  printf 'FAIL a judge verdict of false still exited 0\n'
  fails=$((fails + 1))
else
  printf 'ok   a judge verdict of false exits non-zero\n'
fi
contains "the judge's FAIL carries its reason" "FAIL  judged (judge: stub reason)" "$output"

# A judge that answers nothing is the quiet one: counting it as a pass makes an
# LLM-graded case green while it grades nothing.
rm -rf "$STUB_CLAUDE_OUT"
if output="$(STUB_USE_JUDGE=1 STUB_JUDGE_PASS='' $RUN "$skill" case-a 2>&1)"; then
  printf 'FAIL an unavailable judge still exited 0\n'
  fails=$((fails + 1))
else
  printf 'ok   an unavailable judge exits non-zero\n'
fi
contains "an unavailable judge is reported as such" "FAIL  judged (judge unavailable)" "$output"

# --- input validation ---
check_fails() {
  local label="$1" needle="$2"
  shift 2
  local out
  if out="$("$@" 2>&1)"; then
    printf 'FAIL %s (exited 0)\n' "$label"
    fails=$((fails + 1))
    return
  fi
  contains "$label" "$needle" "$out"
}
# The malformed cases live in a skill of their own. In stub-skill they would
# join every "with no case named" run and fail it, which used to make where in
# this file they were created load-bearing.
bad="stub-skill-bad"
mkdir -p "$skills_dir/$bad/evals/case-d" "$skills_dir/$bad/evals/case-e"
cp "$skills_dir/$skill/SKILL.md" "$skills_dir/$bad/SKILL.md"
cat >"$skills_dir/$bad/evals/case-d/prompt.md" <<'EOF'
---
name: case-d
max_turns: soon
---
do it
EOF
# case-e is the same check on the other key. Two validations exist, so two are
# tested: one of them could be deleted and the other would keep the suite green.
cat >"$skills_dir/$bad/evals/case-e/prompt.md" <<'EOF'
---
name: case-e
budget_usd: plenty
---
do it
EOF
for c in case-d case-e; do
  cp "$skills_dir/$skill/evals/case-a/scaffold.sh" "$skills_dir/$skill/evals/case-a/assert.sh" \
    "$skills_dir/$bad/evals/$c/"
done
# A valid case ahead of the bad ones, so "refused before case-a runs" below can
# be asked of this skill too: without it the run stops at "no prompt.md" and
# never reaches the frontmatter check it is meant to pin.
cp -R "$skills_dir/$skill/evals/case-a" "$skills_dir/$bad/evals/case-a"

check_fails "no skill prints the usage" "usage:" $RUN
check_fails "--runs 0 says why" "--runs takes an integer" $RUN "$skill" case-a --runs 0
check_fails "an unknown skill says why" "no such skill" $RUN no-such-skill
check_fails "an incomplete case names the missing file" "case no-such-case has no prompt.md" \
  $RUN "$skill" no-such-case
# Passing a non-numeric ceiling straight through would make `claude -p` fail
# with its own message, and the runner would grade that failed run as a FAIL of
# the skill. Refusing before the API call is what keeps the two apart.
check_fails "an unparsable max_turns says why, before spending anything" \
  "case case-d: max_turns takes an integer" $RUN "$bad" case-d
check_fails "an unparsable budget_usd says why, before spending anything" \
  "case case-e: budget_usd takes a number" $RUN "$bad" case-e
# An option given no value used to die on `shift 2` under set -e: exit 1 and
# not a word about why.
check_fails "--runs with no value says why" "--runs needs a value" $RUN "$skill" case-a --runs
check_fails "--model with no value says why" "--model needs a value" $RUN "$skill" case-a --model

# --- an assert.sh that never calls skill_eval_finish ---
# Its FAIL lines are in the log while the script exits 0, and the runner used
# to grade on the exit status alone: [PASS], with the failures visible only to
# someone who opened assert.log.
rm -rf "$STUB_CLAUDE_OUT"
if output="$(STUB_ASSERT_FAIL=1 STUB_NO_FINISH=1 $RUN "$skill" case-a 2>&1)"; then
  printf 'FAIL a FAIL line without skill_eval_finish still exited 0\n'
  fails=$((fails + 1))
else
  printf 'ok   a FAIL line fails the run even without skill_eval_finish\n'
fi
contains "and the run is reported as FAIL" "[FAIL] $skill/case-a run-1" "$output"

# --- an assert.sh that dies before its first check ---
# The other half of the rule above: no FAIL line at all, only the exit status.
# A grader whose `source` failed, say, has measured nothing, and must not PASS.
rm -rf "$STUB_CLAUDE_OUT"
if output="$(STUB_ASSERT_CRASH=1 $RUN "$skill" case-a 2>&1)"; then
  printf 'FAIL a grader that exited 3 before any check still exited 0\n'
  fails=$((fails + 1))
else
  printf 'ok   a grader that exits non-zero before any check fails the run\n'
fi
contains "and the run is reported as FAIL" "[FAIL] $skill/case-a run-1" "$output"
contains "and counted as 0/1" "0/1" "$output"

# --- a scaffold that fails ---
# It used to abort the whole run under set -e, naming no case and leaving the
# working directory behind.
rm -rf "$STUB_CLAUDE_OUT"
check_fails "a failing scaffold names the case" "case case-a: scaffold.sh exited 4" \
  env STUB_SCAFFOLD_FAIL=1 $RUN "$skill" case-a
t "and claude is never called" "absent" "$([ -e "$STUB_CLAUDE_OUT/args" ] && echo present || echo absent)"
# The scaffold says where it ran (into a file kept outside TMPDIR), which is
# the positive control for the emptiness check below: it proves the failing
# branch ran AND that the run's temp files were placed in this TMPDIR, so an
# empty directory means cleaned up, not never written to. The per-case cost
# file used to outlive this exit.
mkdir -p "$DIR/scaffold-tmp"
TMPDIR="$DIR/scaffold-tmp" STUB_SCAFFOLD_FAIL=1 STUB_SCAFFOLD_CWD="$DIR/scaffold-cwd" \
  $RUN "$skill" case-a >/dev/null 2>&1
scaffold_cwd=$(cat "$DIR/scaffold-cwd" 2>/dev/null)
scaffold_tmp=$(cd "$DIR/scaffold-tmp" && pwd -P)
case "$scaffold_cwd" in
  "$scaffold_tmp"/?*) under_tmp=yes ;;
  *) under_tmp=no ;;
esac
t "the failing scaffold ran in a working directory under TMPDIR" "yes" "$under_tmp"
t "and that directory is removed" "gone" "$([ -e "$scaffold_cwd" ] && echo kept || echo gone)"
t "and nothing the run made is left in TMPDIR" "" "$(ls -Ap "$DIR/scaffold-tmp" 2>&1)"

# A run of several cases that finishes leaves nothing either. The trap knows
# only the case in progress, so each finished case must remove its own cost
# file; a single-case run would not notice if one stopped doing so.
rm -rf "$STUB_CLAUDE_OUT" "$SKILL_EVAL_OUT_DIR"
mkdir -p "$DIR/multi-tmp"
multi_rc=0
TMPDIR="$DIR/multi-tmp" $RUN "$skill" >"$DIR/multi-out" 2>&1 || multi_rc=$?
contains "a run of every case reaches case-b" "[PASS] $skill/case-b run-1" "$(cat "$DIR/multi-out")"
# Every other check of the exit status looks for non-zero. Under set -e the
# EXIT trap's return value replaces a clean `exit 0`, so a cleanup that ended
# on a false test would turn every passing run red -- with nothing else noticing.
t "a run where every case passes exits 0" "0" "$multi_rc"
t "and leaves nothing in TMPDIR" "" "$(ls -Ap "$DIR/multi-tmp" 2>&1)"

# A mid-case exit that is not the scaffold's -- here the runner's own write
# into .git/info failing under set -e -- removes the working directory too:
# without --keep, a run leaves nothing whichever way it ends.
# Each run below records its cwd in a file of its own, so no case can pass on
# a path a previous one left behind.
#
# run_failing <name> <args...> -- run the runner with TMPDIR=$DIR/<name>-tmp and
# STUB_SCAFFOLD_CWD=$DIR/<name>-cwd; sets out, rc, cwd (the scaffold's pwd -P)
# and named (the `work:` path the runner printed, resolved with pwd -P).
run_failing() {
  local name=$1
  shift
  mkdir -p "$DIR/$name-tmp"
  rc=0
  out=$(env TMPDIR="$DIR/$name-tmp" STUB_SCAFFOLD_CWD="$DIR/$name-cwd" "$@" 2>&1) || rc=$?
  cwd=$(cat "$DIR/$name-cwd" 2>/dev/null)
  named=$(printf '%s\n' "$out" | sed -n 's/^ *work: //p')
  [ -z "$named" ] || named=$(cd "$named" 2>/dev/null && pwd -P)
}

rm -rf "$STUB_CLAUDE_OUT"
run_failing midcase STUB_SCAFFOLD_BREAK_GIT_INFO=1 $RUN "$skill" case-a
t "a runner step failing mid-case exits non-zero" "nonzero" "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)"
# Not the scaffold's failure dressed up as one: the scaffold returned 0, and
# the run stopped at the runner's own write.
absent "and the scaffold itself did not fail" "scaffold.sh exited" "$out"
contains "it stopped at the runner's write into .git/info" ".git/info/exclude" "$out"
t "the working directory is removed" "gone" "$([ -n "$cwd" ] && [ ! -e "$cwd" ] && echo gone || echo kept)"
t "and nothing is left in TMPDIR" "" "$(ls -Ap "$DIR/midcase-tmp" 2>&1)"

# --keep is for investigating a failure, and a broken scaffold is one: its
# half-built fixture is kept and named, while the runner's own files go, and
# the run still fails as a broken harness.
rm -rf "$STUB_CLAUDE_OUT"
run_failing keepfail STUB_SCAFFOLD_FAIL=1 $RUN "$skill" case-a --keep
t "--keep still fails a broken scaffold" "nonzero" "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)"
contains "and still names the failing case" "case case-a: scaffold.sh exited 4" "$out"
t "and keeps its working directory" "kept" "$([ -n "$cwd" ] && [ -d "$cwd" ] && echo kept || echo gone)"
t "and names it" "$cwd" "$named"
t "and it is the only thing left in TMPDIR" "$(basename "$cwd")/" "$(ls -Ap "$DIR/keepfail-tmp" 2>&1)"

# The same for any other mid-case exit: a run cut short under --keep names the
# directory it kept, or it is an unnamed skill-eval.XXXXXX among the others.
rm -rf "$STUB_CLAUDE_OUT"
run_failing keepmid STUB_SCAFFOLD_BREAK_GIT_INFO=1 $RUN "$skill" case-a --keep
t "--keep keeps a run cut short mid-case" "kept" "$([ -n "$cwd" ] && [ -d "$cwd" ] && echo kept || echo gone)"
t "and names it" "$cwd" "$named"

# --- allowed-tools is read from the frontmatter only ---
# A body line that happens to start with the key -- an example in the skill's
# own documentation, say -- must not widen what the run may do.
printf '\nallowed-tools: Write, Edit\n' >>"$skills_dir/$skill/SKILL.md"
rm -rf "$STUB_CLAUDE_OUT"
$RUN "$skill" case-a >/dev/null
absent "a body line is not read as allowed-tools" "Write" "$(cat "$STUB_CLAUDE_OUT/args")"
contains "while the frontmatter's still is" "Bash(git status *)" "$(cat "$STUB_CLAUDE_OUT/args")"

# --- claude_md: a case that measures a CLAUDE.md rule opts in to one ---
# By default no CLAUDE.md reaches the fixture, so a case measures what SKILL.md
# does on its own. A rule that lives only in CLAUDE.md -- review-test's
# auto-start -- is measurable only by a case that names the file it comes from.
rm -rf "$STUB_CLAUDE_OUT"
$RUN "$skill" case-a >/dev/null
t "a case without claude_md gets no CLAUDE.md" "absent" "$(cat "$STUB_CLAUDE_OUT/claude_md")"

# Excluded only when brought in. Excluding it always would hide a CLAUDE.md the
# skill writes itself -- init-project's -- from `git add -A`, and its eval's
# clean-tree check would pass all the same, since an excluded file is not in
# status either.
rm -rf "$STUB_CLAUDE_OUT"
# shellcheck disable=SC2016  # expanded by the stub's own shell, not this one
STUB_CLAUDE_ACTION='echo mine >CLAUDE.md && git status --porcelain >"$STUB_CLAUDE_OUT/status_after"' \
  $RUN "$skill" case-a >/dev/null
contains "a CLAUDE.md the skill writes itself stays visible to git status" "?? CLAUDE.md" \
  "$(cat "$STUB_CLAUDE_OUT/status_after")"

mkdir -p "$skills_dir/$skill/evals/case-f" "$skills_dir/$skill/evals/case-g"
cat >"$skills_dir/$skill/evals/case-f/prompt.md" <<'EOF'
---
name: case-f
claude_md: root/CLAUDE.md
---
do it
EOF
cp "$skills_dir/$skill/evals/case-a/scaffold.sh" "$skills_dir/$skill/evals/case-f/scaffold.sh"
cp "$skills_dir/$skill/evals/case-a/assert.sh" "$skills_dir/$skill/evals/case-f/assert.sh"
rm -rf "$STUB_CLAUDE_OUT"
$RUN "$skill" case-f >/dev/null
t "claude_md is copied in as the fixture's CLAUDE.md" "$(head -n 1 root/CLAUDE.md)" \
  "$(cat "$STUB_CLAUDE_OUT/claude_md")"
# Untracked, it is the user's work to a skill reading git status; committed by
# the scaffold, it is the user's code.
t "the CLAUDE.md we brought in stays out of git status" " M tracked.txt" \
  "$(cat "$STUB_CLAUDE_OUT/status")"
t "the fixture's first commit does not track the CLAUDE.md" "tracked.txt" \
  "$(cat "$STUB_CLAUDE_OUT/tracked")"
absent "the claude_md line stays out of the prompt" "claude_md:" "$(cat "$STUB_CLAUDE_OUT/args")"

cat >"$skills_dir/$skill/evals/case-g/prompt.md" <<'EOF'
---
name: case-g
claude_md: no/such/CLAUDE.md
---
do it
EOF
cp "$skills_dir/$skill/evals/case-a/scaffold.sh" "$skills_dir/$skill/evals/case-g/scaffold.sh"
cp "$skills_dir/$skill/evals/case-a/assert.sh" "$skills_dir/$skill/evals/case-g/assert.sh"
# A typo would otherwise run the case with no CLAUDE.md at all, and measure
# SKILL.md alone while claiming to measure the rule.
check_fails "a claude_md that does not exist says why, before spending anything" \
  "case case-g: claude_md not found: no/such/CLAUDE.md" $RUN "$skill" case-g

# "Before spending anything" means before any case runs, not before this one:
# run as a whole skill, a bad case further down the list would otherwise be
# reached only after the ones before it were paid for. One check per key, since
# each is validated on its own. The message is checked as well as the absence
# of a run: absence alone also holds when the run stops on something unrelated,
# which is how two of these three once passed while pinning nothing.
for row in "$bad case-d max_turns takes an integer" \
  "$bad case-e budget_usd takes a number" \
  "$skill case-g claude_md not found"; do
  read -r owner bad_case reason <<<"$row"
  rm -rf "$STUB_CLAUDE_OUT"
  check_fails "a bad $bad_case is refused for the right reason" \
    "case $bad_case: $reason" $RUN "$owner" case-a "$bad_case"
  t "a bad $bad_case is refused before case-a runs" "absent" \
    "$(if [ -e "$STUB_CLAUDE_OUT/args" ]; then echo present; else echo absent; fi)"
done

# --- the transcript readers, against a fixture transcript ---
#
# The review skills' read-only boundary is graded by ORDER: "nothing written
# before the report" (see transcript_first_tool_index). An off-by-one, or a
# heading quoted inside a tool's input counted as the report, moves that line
# and grades a write-before-report run as clean. The runner cases above only
# reach the count readers, through a two-record stub, so the ordering ones are
# pinned here directly. The record index is the line number from 0, counting
# every record, not just the assistant's.
cat >"$DIR/transcript.jsonl" <<'EOF'
{"type":"system","subtype":"init"}
{"type":"user","message":{"content":"review the tests"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Let me look."},{"type":"tool_use","name":"Read","input":{"file_path":"a.test.sh"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"## Test review"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"notes.md","content":"## Test review draft"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status\n--short"}}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"## Test review\nP1: none"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"a.test.sh"}},{"type":"tool_use","name":"Read","input":{"file_path":"b.test.sh"}},{"type":"tool_use","name":"Bash","input":{"command":"git commit -m fix"}}]}}
{"type":"result","subtype":"success","result":"done","permission_denials":[{"tool_name":"Write"},{"tool_name":"Bash"}]}
EOF
tail -1 "$DIR/transcript.jsonl" >"$DIR/result.json"
# reader <function> [args] -- one reader's output against the fixture, in a
# subshell so the sourced library leaves this shell alone.
reader() {
  (
    SKILL_EVAL_TRANSCRIPT="$DIR/transcript.jsonl"
    SKILL_EVAL_RESULT_FILE="$DIR/result.json"
    # shellcheck source=bin/skill-eval-assert.sh
    . bin/skill-eval-assert.sh
    "$@"
  )
}
# precedes <tool> <index> -- the predicate's sense, as a word.
precedes() { if reader transcript_tool_uses_precede "$1" "$2"; then echo yes; else echo no; fi; }

t "first_tool_index: the FIRST call, counting every record, not just the assistant's" "2" "$(reader transcript_first_tool_index Read)"
t "first_tool_index: finds a call that is not the record's first block" "7" "$(reader transcript_first_tool_index Edit)"
t "first_tool_index: empty for a tool never called" "" "$(reader transcript_first_tool_index Skill)"
t "first_text_index: a heading inside a tool's input or result is not the report" "6" \
  "$(reader transcript_first_text_index 'Test review')"
t "first_text_index: empty when no text matches" "" "$(reader transcript_first_text_index 'no such heading')"
t "first_command_index: the first Bash call whose command matches" "7" "$(reader transcript_first_command_index 'git commit')"
t "first_command_index: another tool's input is not a command" "" "$(reader transcript_first_command_index 'notes\.md')"
t "tool_uses_precede: a call before the index" "yes" "$(precedes Write 6)"
t "tool_uses_precede: a call at the index counts as preceding" "yes" "$(precedes Write 4)"
t "tool_uses_precede: a call only after the index" "no" "$(precedes Edit 6)"
t "tool_uses_precede: a tool never called" "no" "$(precedes Skill 100)"
t "tool_uses: every call, across records" "2" "$(reader transcript_tool_uses Bash)"
t "commands: one call per line, newlines folded" $'git status\\n--short\ngit commit -m fix' "$(reader transcript_commands)"
t "result_text: the final response" "done" "$(reader transcript_result_text)"
t "denials: every refused call" "2" "$(reader transcript_denials)"

# --- review rounds, against a fixture transcript ---
#
# The review loop is graded per round: what each round reported, and whether
# the caller fixed something before the next. A reader that matched a result
# to the wrong call, counted the caller's own calls as the fork's, or read an
# empty priority section as a finding would grade a loop that never ended as
# clean, or a clean one as running forever. Two rounds of review-test: the
# first reports a P1 as a string result, the second only "なし" under P2, as
# an array result; an unrelated skill and an Edit inside the fork sit between.
# Indices: 1 Skill#1, 2 fork Read, 3 fork Edit, 4 result#1, 5 caller Edit,
# 6 commit Skill, 7 Skill#2, 8 result#2.
cat >"$DIR/rounds.jsonl" <<'EOF'
{"type":"system","subtype":"init"}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"s1","name":"Skill","input":{"skill":"review-test","args":"first brief"}}]}}
{"type":"assistant","parent_tool_use_id":"s1","message":{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"a.test.sh"}},{"type":"tool_use","id":"r2","name":"Grep","input":{"pattern":"x"}}]}}
{"type":"assistant","parent_tool_use_id":"s1","message":{"content":[{"type":"tool_use","id":"r3","name":"Edit","input":{"file_path":"a.test.sh"}}]}}
{"type":"user","tool_use_result":{"totalDurationMs":4200,"totalTokens":900},"message":{"content":[{"type":"tool_result","tool_use_id":"s1","content":"## Test review: a\n\n### P1 (Critical)\n- the refusal is untested\n- [ ] stderr unchecked\n\n### P3 (Nice to have)\n- naming"}]}}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"a.test.sh"}}]}}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"c1","name":"Skill","input":{"skill":"commit"}}]}}
{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"s2","name":"Skill","input":{"skill":"review-test","args":"second brief: fixed the refusal"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"s2","content":[{"type":"text","text":"## Test review: a\n\n### P2 (Important)\n- なし\n\n### P3\n- naming"}]}]}}
{"type":"result","result":"done"}
EOF
rounds_of() { # <jq filter over the rounds array>
  (
    SKILL_EVAL_TRANSCRIPT="$DIR/rounds.jsonl"
    . bin/skill-eval-assert.sh
    transcript_skill_rounds review-test
  ) | jq -sc "$1"
}
t "skill_rounds: one round per call of that skill, not of another" "2" "$(rounds_of 'length')"
t "skill_rounds: each call's own index and result index" "[[1,4],[7,8]]" "$(rounds_of '[.[] | [.index, .result_index]]')"
t "skill_rounds: the brief is the args, not the skill's name" '["first brief","second brief: fixed the refusal"]' "$(rounds_of '[.[].brief]')"
t "skill_rounds: a string result and an array result both read as the report" "[true,true]" \
  "$(rounds_of '[.[].report | startswith("## Test review: a")]')"
# P3 items are not open, a checkbox item is, and "なし" under P2 is nothing.
t "skill_rounds: open counts P1/P2 items only, and not an item saying none" "[2,0]" "$(rounds_of '[.[].open]')"
t "skill_rounds: tool_calls counts the fork's calls, every block, none of the caller's" "[3,0]" "$(rounds_of '[.[].tool_calls]')"
t "skill_rounds: duration and tokens when recorded, null when not" "[[4200,900],[null,null]]" \
  "$(rounds_of '[.[] | [.duration_ms, .tokens]]')"

# loop <predicate> [<transcript>] -- the predicate's sense, as a word.
loop() {
  if (
    SKILL_EVAL_TRANSCRIPT="${2:-$DIR/rounds.jsonl}"
    . bin/skill-eval-assert.sh
    "$1" review-test
  ); then echo yes; else echo no; fi
}
t "caller_writes_between: the caller's Edit, not the fork's" "1" \
  "$(SKILL_EVAL_TRANSCRIPT="$DIR/rounds.jsonl" bash -c '. bin/skill-eval-assert.sh; transcript_caller_writes_between 1 7')"
t "caller_writes_between: bounds are exclusive" "0" \
  "$(SKILL_EVAL_TRANSCRIPT="$DIR/rounds.jsonl" bash -c '. bin/skill-eval-assert.sh; transcript_caller_writes_between 5 7')"
t "loop: the fixture re-ran only after findings" "yes" "$(loop review_loop_reran_only_after_findings)"
t "loop: the fixture fixed before re-running" "yes" "$(loop review_loop_fixed_before_each_rerun)"
t "loop: the fixture ended clean" "yes" "$(loop review_loop_ended_clean)"

# Each predicate broken by one change to the fixture.
sed '6d' "$DIR/rounds.jsonl" >"$DIR/rounds-nofix.jsonl"
t "loop: a re-run with no caller write between is caught" "no" "$(loop review_loop_fixed_before_each_rerun "$DIR/rounds-nofix.jsonl")"
# The same Edit made inside a fork must not stand in for the caller's fix.
sed '6s/"parent_tool_use_id":null/"parent_tool_use_id":"s1"/' "$DIR/rounds.jsonl" >"$DIR/rounds-forkfix.jsonl"
t "loop: an Edit inside the fork does not count as the fix" "no" "$(loop review_loop_fixed_before_each_rerun "$DIR/rounds-forkfix.jsonl")"
sed 's/- the refusal is untested/- なし/; s/- \[ \] stderr unchecked/- None/' "$DIR/rounds.jsonl" >"$DIR/rounds-clean-first.jsonl"
t "loop: a re-run after a clean round is caught" "no" "$(loop review_loop_reran_only_after_findings "$DIR/rounds-clean-first.jsonl")"
sed 's/### P2 (Important)\\n- なし/### P2 (Important)\\n- still open/' "$DIR/rounds.jsonl" >"$DIR/rounds-dirty-last.jsonl"
t "loop: a last round with a P2 left is caught" "no" "$(loop review_loop_ended_clean "$DIR/rounds-dirty-last.jsonl")"
head -n 1 "$DIR/rounds.jsonl" >"$DIR/rounds-none.jsonl"
t "loop: no round at all is not a clean end" "no" "$(loop review_loop_ended_clean "$DIR/rounds-none.jsonl")"
t "loop: but re-ran nothing, so the other two hold" "yes yes" \
  "$(loop review_loop_reran_only_after_findings "$DIR/rounds-none.jsonl") $(loop review_loop_fixed_before_each_rerun "$DIR/rounds-none.jsonl")"

if [ "$fails" -eq 0 ]; then
  printf '\nall skill-eval tests passed\n'
  exit 0
fi
printf '\n%d skill-eval test(s) failed\n' "$fails"
exit 1
