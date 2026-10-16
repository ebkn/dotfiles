#!/bin/bash
#
# assert.test.sh — pins the graders of create-pr's and update-pr's eval cases
# without calling the API. They share grading.sh and lib.sh, so one suite
# covers both skills' cases.
#
# For each case: build the fixture its scaffold.sh builds, carry out a good
# run against the fake GitHub (bin/skill-eval-github.sh) with a synthetic
# transcript beside it, and check the grader passes; then break one thing at a
# time and check the matching assertion FAILs and the grader exits non-zero.
# check_llm is graded by a stub judge that fails exactly when its input holds
# JUDGE_FAIL, which pins that the judged check reads the closing message.
#
# Written for bash 3.2 (macOS) and run on Linux in CI.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")" || exit 1
evals_dir="$PWD"
repo_root="$(cd "$evals_dir/../../../../.." && pwd)"
skills_dir="$repo_root/root/.agents/skills"
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
rec_text() { jq -nc --arg t "$1" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}'; }
rec_tool() { jq -nc --arg n "$1" --argjson i "$2" '{type: "assistant", message: {content: [{type: "tool_use", name: $n, input: $i}]}}'; }
rec_bash() { rec_tool Bash "$(jq -nc --arg c "$1" '{command: $c}')"; }
# rec_skill <name>: a skill that runs inline, as create-pr, update-pr and
# commit do -- the call, then its result; its commands follow as the caller's.
rec_skill() {
  rec_tool Skill "$(jq -nc --arg s "$1" '{skill: $s}')"
  jq -nc --arg s "$1" '{type: "user", message: {content: [{type: "tool_result", content: ("Launching skill: " + $s)}]}}'
}

# new_run <skill> <case>: the fixture its scaffold builds, an empty transcript.
new_run() {
  case_dir="$skills_dir/$1/evals/$2"
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

# act <records> <tree change>: the run, as transcript records and as what it
# did to the fixture and the fake GitHub (with the gh stub first on PATH).
act() {
  eval "$1" >>"$art/transcript.jsonl"
  (
    cd "$work" || exit 1
    PATH="$work/bin:$PATH"
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

done_msg='完了しました。PR を更新し、ready for review にしました: https://github.com/example/fixture/pull/1'

# The tree changes the requests ask for.
# shellcheck disable=SC2016  # expanded inside act
fix_readme='sed "s#make install#./install.sh#" README.md >R.tmp; mv R.tmp README.md; git commit -qam "docs: install with install.sh"'
# shellcheck disable=SC2016
add_contributing='printf "# Contributing\n\nUse Conventional Commits.\n" >CONTRIBUTING.md; git add CONTRIBUTING.md; git commit -qm "docs: add CONTRIBUTING"'
body_both='gh pr edit --title "docs: install steps and CONTRIBUTING" --body "README install steps; CONTRIBUTING with the commit rule"'

# ============================================================
# draft-at-first-commit
# ============================================================
# draft_run <records> <tree change> <closing>
draft_run() {
  new_run create-pr draft-at-first-commit || return 1
  act "$1" "$2"
  grade "$3"
}
draft_records='rec_bash "git commit -qam a"; rec_skill create-pr; rec_bash "gh pr create --draft --title t --body b"; rec_bash "git commit -qm b"; rec_skill update-pr; rec_bash "gh pr edit --body x"; rec_bash "gh pr ready"'
draft_tree="$fix_readme; git push -q -u origin HEAD; gh pr create --draft --title \"docs: install steps\" --body \"README install steps\"; $add_contributing; git push -q; $body_both; gh pr ready"

draft_run "$draft_records" "$draft_tree" "$done_msg"
expect_pass "draft-at-first-commit: a good run passes"

draft_run 'rec_bash "git commit -qam a"; rec_bash "git commit -qm b"; rec_skill create-pr; rec_bash "gh pr create --title t --body b"' \
  "$fix_readme; $add_contributing; git push -q -u origin HEAD; gh pr create --title \"docs: both\" --body \"CONTRIBUTING and README\"" "$done_msg"
expect_fail "draft-at-first-commit: a PR opened only at the end" "opened the PR after the first commit and before the last"
expect_fail "draft-at-first-commit: and not as a draft" "opened it as a draft"
expect_fail "draft-at-first-commit: with no update-pr" "ran update-pr after the last commit"

draft_run "${draft_records//rec_skill create-pr; /}" "$draft_tree" "$done_msg"
expect_fail "draft-at-first-commit: gh run by hand, not through create-pr" "through create-pr"

draft_run "$draft_records" "${draft_tree//git push -q; /}" "$done_msg"
expect_fail "draft-at-first-commit: the last commit never pushed" "pushed every commit"

draft_run "$draft_records" "${draft_tree//; gh pr ready/}" "$done_msg"
expect_fail "draft-at-first-commit: left a draft" "marked it ready once the work was done"

draft_run "$draft_records" "${draft_tree//; $body_both/}" "$done_msg"
expect_fail "draft-at-first-commit: the body left as the first commit's" "the PR body covers the second request too"

# Both requests folded into the first commit by amending it.
draft_run "$draft_records" "${draft_tree//git commit -qm \"docs: add CONTRIBUTING\"/git commit -q --amend --no-edit}" "$done_msg"
expect_fail "draft-at-first-commit: one commit only" "committed each request on its own (two commits or more)"

draft_run "$draft_records" "$draft_tree" "完了しました。PR を ready for review にしますか？"
expect_fail "draft-at-first-commit: a closing question about the PR" \
  "the closing message asks nothing about pushing or a PR (known phrasings)"
draft_run "$draft_records" "$draft_tree" "Done. Would you like me to push the branch and open a pull request?"
expect_fail "draft-at-first-commit: the same question in English" \
  "the closing message asks nothing about pushing or a PR (known phrasings)"
draft_run "$draft_records" "$draft_tree" "完了しました。JUDGE_FAIL"
expect_fail "draft-at-first-commit: the judge reads the closing message" \
  "the closing message asks nothing about pushing or a PR (judged)"
draft_run "$draft_records; rec_tool AskUserQuestion '{\"questions\":[]}'" "$draft_tree" "$done_msg"
expect_fail "draft-at-first-commit: a question through the tool" "asked nothing through AskUserQuestion"

# ============================================================
# ready-in-one-commit
# ============================================================
ready_run() {
  new_run create-pr ready-in-one-commit || return 1
  act "$1" "$2"
  grade "$3"
}
ready_records='rec_bash "git commit -qam a"; rec_skill create-pr; rec_bash "gh pr create --title t --body b"'
ready_tree="$fix_readme; git push -q -u origin HEAD; gh pr create --title \"docs: install steps\" --body \"README\""

ready_run "$ready_records" "$ready_tree" "$done_msg"
expect_pass "ready-in-one-commit: a PR opened ready passes"
ready_run "$ready_records; rec_skill update-pr; rec_bash \"gh pr ready\"" \
  "${ready_tree//gh pr create/gh pr create --draft}; gh pr ready" "$done_msg"
expect_pass "ready-in-one-commit: so does a draft that update-pr then readies"
ready_run "$ready_records" "${ready_tree//gh pr create/gh pr create --draft}" "$done_msg"
expect_fail "ready-in-one-commit: a draft left as one" "the PR ends ready for review"
ready_run 'rec_skill create-pr; rec_bash "gh pr create --title t --body b"; rec_bash "git commit -qam a"' "$ready_tree" "$done_msg"
expect_fail "ready-in-one-commit: a PR opened before the commit" "opened the PR after committing"
ready_run "$ready_records" "$ready_tree; echo more >>README.md; git commit -qam more" "$done_msg"
expect_fail "ready-in-one-commit: a commit left unpushed" "pushed every commit"
ready_run "$ready_records" "$ready_tree" "$done_msg JUDGE_FAIL"
expect_fail "ready-in-one-commit: the judge reads the closing message" \
  "the closing message asks nothing about pushing or a PR (judged)"

# ============================================================
# no-pr-on-default-branch
# ============================================================
main_run() {
  new_run create-pr no-pr-on-default-branch || return 1
  act "$1" "$2"
  grade "$3"
}
main_msg='README を直してコミットしました。main 上の作業なので PR は作っていません(push もしていません)。'

main_run 'rec_bash "git commit -qam a"' "$fix_readme" "$main_msg"
expect_pass "no-pr-on-default-branch: a commit on main, reported, passes"
main_run 'rec_bash "git commit -qam a"; rec_bash "git push"' "$fix_readme; git push -q" "$main_msg"
expect_fail "no-pr-on-default-branch: pushing main" "pushed nothing"
main_run 'rec_bash "git commit -qam a"; rec_skill create-pr; rec_bash "gh pr create --draft"' \
  "$fix_readme; git switch -qc docs/install; git push -q -u origin HEAD; gh pr create --draft --title t --body b" "$main_msg"
expect_fail "no-pr-on-default-branch: a branch made to open a PR from" "stayed on main"
expect_fail "no-pr-on-default-branch: and it is still there" "created no branch to open a PR from"
expect_fail "no-pr-on-default-branch: gh pr create run" "never ran gh pr create"
expect_fail "no-pr-on-default-branch: create-pr started" "started neither PR skill"
main_run 'rec_bash "git commit -qam a"' "$fix_readme" "README を直してコミットしました。ブランチを切って PR を作成しますか？"
expect_fail "no-pr-on-default-branch: offering a PR instead" \
  "the closing message asks nothing about pushing or a PR (known phrasings)"

# ============================================================
# update-pr: ready-at-finish
# ============================================================
finish_run() {
  new_run update-pr ready-at-finish || return 1
  act "$1" "$2"
  grade "$3"
}
# shellcheck disable=SC2016
add_tests_section='printf "\n## Tests\n\nRun ./run-tests.sh.\n" >>CONTRIBUTING.md; git commit -qam "docs: say how to run the tests"'
finish_records='rec_bash "git commit -qam a"; rec_skill update-pr; rec_bash "git push"; rec_bash "gh pr edit --body x"; rec_bash "gh pr ready"'
finish_tree="$add_tests_section; git push -q; gh pr edit --body \"CONTRIBUTING: commit rule, and ./run-tests.sh\"; gh pr ready"

finish_run "$finish_records" "$finish_tree" "$done_msg"
expect_pass "ready-at-finish: a good run passes"
finish_run "$finish_records; rec_bash \"gh pr create --title t --body b\"" "$finish_tree" "$done_msg"
expect_fail "ready-at-finish: a second PR attempted" "opened no second PR"
finish_run 'rec_skill update-pr; rec_bash "gh pr edit --body x"; rec_bash "git commit -qam a"' "$finish_tree" "$done_msg"
expect_fail "ready-at-finish: update-pr before the commit" "ran update-pr after the last commit"
finish_run "$finish_records" "${finish_tree//git push -q; /}" "$done_msg"
expect_fail "ready-at-finish: the commit never pushed" "pushed every commit"
finish_run "$finish_records" "$add_tests_section; git push -q; gh pr ready" "$done_msg"
expect_fail "ready-at-finish: the PR never rewritten" "rewrote the PR"
expect_fail "ready-at-finish: so its body misses the new section" "the PR body covers the new section"
finish_run "$finish_records" "${finish_tree//; gh pr ready/}" "$done_msg"
expect_fail "ready-at-finish: left a draft" "marked it ready, since the request finished the work"
finish_run "$finish_records" "$finish_tree" "完了しました。PR を ready にしましょうか？"
expect_fail "ready-at-finish: asking before readying" \
  "the closing message asks nothing about pushing or a PR (known phrasings)"

# ============================================================
# update-pr: no-update-without-commits
# ============================================================
question_run() {
  new_run update-pr no-update-without-commits || return 1
  act "$1" "$2"
  grade "$3"
}
answer='Usage 節には `./tally.sh FILE...` と書かれています。'

question_run 'rec_tool Read "{\"file_path\":\"README.md\"}"' ":" "$answer"
expect_pass "no-update-without-commits: an answer and nothing else passes"
question_run 'rec_skill update-pr; rec_bash "gh pr edit --body x"; rec_bash "gh pr ready"' \
  'gh pr edit --body x; gh pr ready' "$answer"
expect_fail "no-update-without-commits: update-pr on a question" "started neither PR skill"
expect_fail "no-update-without-commits: and the PR touched" "left the PR as it was"
question_run ':' 'echo x >>README.md; git commit -qam x; git push -q' "$answer"
expect_fail "no-update-without-commits: a commit made" "committed nothing"
expect_fail "no-update-without-commits: and pushed" "pushed nothing"
question_run ':' ':' "Usage 節を確認しました。"
expect_fail "no-update-without-commits: no answer" "answered with the command the README gives"
question_run ':' ':' "$answer PR を ready にしますか？"
expect_fail "no-update-without-commits: asking about the PR anyway" \
  "the closing message asks nothing about pushing or a PR (known phrasings)"

test_summary
