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

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

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
git status --porcelain >"$STUB_CLAUDE_OUT/status" 2>/dev/null || true
if [ -e ".claude/skills/$STUB_SKILL/evals" ]; then
  echo present >"$STUB_CLAUDE_OUT/evals"
else
  echo absent >"$STUB_CLAUDE_OUT/evals"
fi
cp bin/repo_root "$STUB_CLAUDE_OUT/repo_root" 2>/dev/null || echo none >"$STUB_CLAUDE_OUT/repo_root"
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
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
echo hello >tracked.txt
skill_eval_init_repo
echo changed >tracked.txt
mkdir -p bin
printf '%s\n' "$SKILL_EVAL_REPO_ROOT" >bin/repo_root
EOF
cat >"$skills_dir/$skill/evals/case-a/assert.sh" <<'EOF'
#!/bin/bash
set -eo pipefail
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
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
---
write something
EOF
cp "$skills_dir/$skill/evals/case-a/scaffold.sh" "$skills_dir/$skill/evals/case-c/scaffold.sh"
cp "$skills_dir/$skill/evals/case-a/assert.sh" "$skills_dir/$skill/evals/case-c/assert.sh"

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
contains "permission prompts are answered by refusing" "--permission-prompts" "$args"
contains "the caller's MCP servers stay out" "--strict-mcp-config" "$args"
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

# --- fixture isolation ---
t "the .claude/ and bin/ we brought in stay out of git status" " M tracked.txt" \
  "$(cat "$STUB_CLAUDE_OUT/status")"
t "evals/ is not carried into the working directory" "absent" "$(cat "$STUB_CLAUDE_OUT/evals")"
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
run_dir="$(find "$SKILL_EVAL_OUT_DIR/$skill/case-a" -type d -name 'run-1' | head -n 1)"
for artifact in transcript.jsonl result.json assert.log git-log.txt git-status.txt; do
  if [ -f "$run_dir/$artifact" ]; then
    printf 'ok   artifact %s is kept\n' "$artifact"
  else
    printf 'FAIL artifact %s is missing\n' "$artifact"
    fails=$((fails + 1))
  fi
done
contains "the grading log holds the PASS lines" "PASS  denials" "$(cat "$run_dir/assert.log")"

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
judge_args="$(cat "$STUB_CLAUDE_OUT/judge-args")"
contains "the judge runs without tools" "--tools" "$judge_args"
contains "the judge reads no settings" "--setting-sources" "$judge_args"
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
check_fails "no skill prints the usage" "usage:" $RUN
check_fails "--runs 0 says why" "--runs takes an integer" $RUN "$skill" case-a --runs 0
check_fails "an unknown skill says why" "no such skill" $RUN no-such-skill
check_fails "an incomplete case names the missing file" "case no-such-case has no prompt.md" \
  $RUN "$skill" no-such-case

if [ "$fails" -eq 0 ]; then
  printf '\nall skill-eval tests passed\n'
  exit 0
fi
printf '\n%d skill-eval test(s) failed\n' "$fails"
exit 1
