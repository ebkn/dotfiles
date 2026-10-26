#!/bin/bash
#
# assert.test.sh — pins the graders of session-summary's eval cases without
# calling the API.
#
# For each case: build the fixture its scaffold.sh builds, carry out a good
# run with a synthetic transcript beside it, and check the grader passes; then
# break one thing at a time and check the matching assertion FAILs and the
# grader exits non-zero. check_llm is graded by a stub judge that fails
# exactly when its input holds JUDGE_FAIL, which pins that each judged check
# reads the closing message. Whether a rubric is right is left to real runs.
#
# Written for bash 3.2 (macOS) and run on Linux in CI.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")" || exit 1
evals_dir="$PWD"
repo_root="$(cd "$evals_dir/../../../../.." && pwd)"
# shellcheck source=../../../../../bin/test-lib.sh
. "$repo_root/bin/test-lib.sh" || exit 2

test_tmpdir
root_dir="$TEST_TMPDIR"

judge="$root_dir/judge"
cat >"$judge" <<'JUDGE'
#!/bin/bash
input="$(cat)"
case "$input" in
  *JUDGE_FAIL*) pass=false ;;
  *) pass=true ;;
esac
printf '{"structured_output":{"pass":%s,"reason":"stub"},"total_cost_usd":0}\n' "$pass"
JUDGE
chmod +x "$judge"

# --- transcript records, in the stream-json shape the readers take ---
# The scenarios call these through eval, in act.
# shellcheck disable=SC2329
rec_tool() { jq -nc --arg n "$1" --argjson i "$2" '{type: "assistant", message: {content: [{type: "tool_use", name: $n, input: $i}]}}'; }
# shellcheck disable=SC2329
rec_bash() { rec_tool Bash "$(jq -nc --arg c "$1" '{command: $c}')"; }
# shellcheck disable=SC2329
rec_skill() {
  rec_tool Skill "$(jq -nc --arg s "$1" '{skill: $s}')"
  jq -nc --arg s "$1" '{type: "user", message: {content: [{type: "tool_result", content: ("Launching skill: " + $s)}]}}'
}

# new_run <case>: the fixture its scaffold builds, an empty transcript.
new_run() {
  case_dir="$evals_dir/$1"
  work="$root_dir/work"
  art="$root_dir/art"
  rm -rf "$work" "$art"
  mkdir -p "$work" "$art"
  (
    cd "$work" || exit 1
    SKILL_EVAL_LIB_DIR="$repo_root/bin" SKILL_EVAL_REPO_ROOT="$repo_root" bash "$case_dir/scaffold.sh"
    printf '.claude/\nbin/\n' >>.git/info/exclude
  ) >/dev/null 2>&1 || return 1
  printf '{"type":"system","subtype":"init"}\n' >"$art/transcript.jsonl"
}

# act <records> <tree change>
act() {
  eval "$1" >>"$art/transcript.jsonl"
  (
    cd "$work" || exit 1
    eval "$2"
  ) >/dev/null 2>&1
}

# grade <closing message>
grade() {
  jq -nc --arg r "$1" '{type: "result", result: $r, permission_denials: []}' >"$art/result.json"
  out="$(
    cd "$work" || exit 1
    SKILL_EVAL_LIB_DIR="$repo_root/bin" \
      SKILL_EVAL_REPO_ROOT="$repo_root" \
      SKILL_EVAL_TRANSCRIPT="$art/transcript.jsonl" \
      SKILL_EVAL_RESULT_FILE="$art/result.json" \
      SKILL_EVAL_CLAUDE_BIN="$judge" \
      bash "$case_dir/assert.sh" 2>&1
  )"
  status=$?
}

expect_pass() {
  if [ "$status" -eq 0 ] && ! grep -q '^FAIL' <<<"$out"; then
    assert_eq "$1" "" ""
  else
    assert_eq "$1" "" "$(grep '^FAIL' <<<"$out")"
  fi
}

# expect_fail <label> <the assertion that must FAIL>
expect_fail() {
  assert_contains "$1" "$out" "FAIL  $2"
  assert_eq "$1 — and the grader exits non-zero" "nonzero" "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
}

# ============================================================
# The fixture itself
# ============================================================
new_run reports-finished-branch
assert_eq "finished branch: three commits ahead of the merge-base" "3" \
  "$(git -C "$work" rev-list --count main...feat/json-output --right-only)"
assert_eq "finished branch: main moved on with CHANGELOG.md" "CHANGELOG.md" \
  "$(git -C "$work" diff --name-only feat/json-output...main)"
assert_contains "finished branch: a two-dot diff would show it, which is the trap" \
  "$(git -C "$work" diff --name-only main..feat/json-output)" "CHANGELOG.md"
assert_eq "finished branch: the --json test passes" "ok" "$(cd "$work" && ./run-tests.sh 2>&1)"
assert_status "finished branch: no file is a usage error" 2 bash -c "cd '$work' && ./tally.sh"
# Faults a careful summary would report as open, so they must not be there.
assert_status "finished branch: --json with no file is a usage error too" 2 bash -c "cd '$work' && ./tally.sh --json"
printf 'x\n' >"$root_dir/a\"b"
assert_eq "finished branch: a quote in a path still makes valid JSON" "a\"b" \
  "$(cd "$root_dir" && "$work/tally.sh" --json 'a"b' | jq -r '.files[0].path')"

# ============================================================
# reports-finished-branch
# ============================================================
# shellcheck disable=SC2016  # markdown backticks, not a command
summary_msg='### 依頼内容
tally.sh の結果を他のツールに渡すため JSON 出力を追加。途中でフラグを `--format=json` から `--json` に変更。
### 対応したこと
- `./tally.sh --json FILE...` が `{"files":[{"path":...,"lines":N}],"total":N}` を出す
### 依頼外の対応
- ファイル未指定で usage を出して終了 (以前は stdin 待ちで止まっていた)
### 残っていること
- コミットはローカル。PR はありません。'
reports_records='rec_skill session-summary; rec_bash "git log main..HEAD"; rec_bash "git diff --stat main...HEAD"; rec_bash "git status --short"'

report_run() {
  new_run reports-finished-branch || return 1
  act "$1" "$2"
  grade "$3"
}
report_run "$reports_records" ":" "$summary_msg"
expect_pass "reports-finished-branch: a good summary passes"
report_run "rec_bash \"git log main..HEAD\"" ":" "$summary_msg"
expect_fail "reports-finished-branch: written without the skill" "started session-summary once"
report_run "$reports_records; rec_skill session-summary" ":" "$summary_msg"
expect_fail "reports-finished-branch: started twice" "started session-summary once"
report_run "$reports_records; rec_tool Edit '{\"file_path\":\"README.md\"}'" "echo x >>README.md" "$summary_msg"
expect_fail "reports-finished-branch: an edit" "wrote no file"
expect_fail "reports-finished-branch: and the tree changed" "left the tree as it was"
report_run "$reports_records; rec_bash \"git commit --allow-empty -m x\"" "git commit -q --allow-empty -m x" "$summary_msg"
expect_fail "reports-finished-branch: a commit" "made no commit"
expect_fail "reports-finished-branch: through git that writes" "ran no git that writes"
report_run "$reports_records" ":" "$summary_msg
- CHANGELOG.md を削除"
expect_fail "reports-finished-branch: main's CHANGELOG.md reported as this branch's" \
  "reports nothing from main (CHANGELOG.md)"
report_run "$reports_records" ":" "${summary_msg//--json/-j}"
expect_fail "reports-finished-branch: the flag not named" "names the interface as written"
report_run "$reports_records" ":" "$summary_msg JUDGE_FAIL"
for label in "opens with the request, its goal and the change of direction" \
  "keeps the unrequested fix apart from the request" \
  "shows the interface a reviewer needs" \
  "says what is left and that there is no PR" \
  "keeps to what a reviewer needs"; do
  expect_fail "reports-finished-branch: the judge reads the closing message ($label)" "$label"
done

# ============================================================
# proactive-with-claude-md, proactive-at-finish (one grader)
# ============================================================
# shellcheck disable=SC2016  # expanded inside act
fix_readme='sed "s#make install#./install.sh#" README.md >R.tmp; mv R.tmp README.md; git commit -qam "docs: install with install.sh"'
proactive_msg='### 依頼内容
README の Install 節が make install のままなので install.sh に直す。
### 対応したこと
- Install 節を `./install.sh` に変更
### 残っていること
- コミットはローカルです。'
proactive_records='rec_tool Edit "{\"file_path\":\"README.md\"}"; rec_bash "git commit -m docs"; rec_skill session-summary'

for case_name in proactive-with-claude-md proactive-at-finish; do
  proactive_run() {
    new_run "$case_name" || return 1
    act "$1" "$2"
    grade "$3"
  }
  proactive_run "$proactive_records" "$fix_readme" "$proactive_msg"
  expect_pass "$case_name: a fix, a commit, then the summary passes"
  proactive_run "$proactive_records" ":" "$proactive_msg"
  expect_fail "$case_name: the README left as it was" "README installs with install.sh"
  expect_fail "$case_name: and nothing committed" "committed the work"
  proactive_run "$proactive_records" "$fix_readme; echo x >>README.md" "$proactive_msg"
  expect_fail "$case_name: an edit left uncommitted" "left nothing uncommitted"
  proactive_run 'rec_tool Edit "{\"file_path\":\"README.md\"}"; rec_bash "git commit -m docs"' "$fix_readme" "$proactive_msg"
  expect_fail "$case_name: no summary skill" "started session-summary once"
  proactive_run "$proactive_records; rec_skill session-summary" "$fix_readme" "$proactive_msg"
  expect_fail "$case_name: started twice" "started session-summary once"
  proactive_run 'rec_tool Edit "{\"file_path\":\"README.md\"}"; rec_skill session-summary; rec_bash "git commit -m docs"' "$fix_readme" "$proactive_msg"
  expect_fail "$case_name: summarized before the commit" "started it after the last commit"
  proactive_run "$proactive_records" "$fix_readme" "$proactive_msg JUDGE_FAIL"
  expect_fail "$case_name: the judge reads the closing message" \
    "the closing message restates the request before the work"
done

# ============================================================
# no-fire-question
# ============================================================
answer='引数がないと wc は標準入力を読むので、入力を待って止まります。'
question_run() {
  new_run no-fire-question || return 1
  act "$1" "$2"
  grade "$3"
}
question_run 'rec_tool Read "{\"file_path\":\"tally.sh\"}"' ":" "$answer"
expect_pass "no-fire-question: an answer and nothing else passes"
question_run 'rec_tool Read "{\"file_path\":\"tally.sh\"}"; rec_skill session-summary' ":" "$answer"
expect_fail "no-fire-question: a summary after an answer" \
  "did not start session-summary for an answered question"
question_run ':' ':' "tally.sh を確認しました。"
expect_fail "no-fire-question: no answer" "answers that wc reads standard input"
question_run ':' 'echo x >>README.md' "$answer"
expect_fail "no-fire-question: a change made" "changed nothing"
question_run ':' 'git commit -q --allow-empty -m x' "$answer"
expect_fail "no-fire-question: a commit made" "committed nothing"

test_summary
