#!/bin/bash
#
# assert.test.sh — pins the graders of every review-test eval case, without
# calling the API.
#
# A grader is an instrument, and an inert one reports a paid, non-deterministic
# eval run that measured nothing. So for each case this builds the fixture its
# scaffold.sh builds, hands the grader a synthetic transcript of a good run and
# checks that it passes, then breaks one thing at a time and checks that the
# matching assertion FAILs and the grader exits non-zero.
#
# The synthetic transcripts carry the body of SKILL.md, which the Skill tool
# loads into the conversation. That body holds the report template ("## Test
# review: ..."), so a check that searched the whole transcript for the heading
# would find it whether or not a report was ever written. The shape is the one
# a real forked run emitted (see rec_skill): the body arrives inside the fork,
# and the report itself first arrives as the Skill's tool_result, which the
# caller must still write out to count as having reported.
#
# check_llm is graded by a stub judge that fails exactly when the text it was
# handed contains JUDGE_FAIL. What that pins is the wiring -- each judged check
# reads the text it claims to read -- not the rubric, which only a real run can
# exercise.
#
# Written for bash 3.2 (macOS) and run on Linux in CI.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")" || exit 1
evals_dir="$PWD"
repo_root="$(cd "$evals_dir/../../../../.." && pwd)"

fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

root_dir="$(mktemp -d)"
trap 'rm -rf "$root_dir"' EXIT

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

# --- transcript records, in the stream-json shape the helpers read ---
rec_init() { printf '{"type":"system","subtype":"init"}\n'; }
rec_text() { jq -nc --arg t "$1" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}'; }
rec_tool() { jq -nc --arg n "$1" --argjson i "$2" '{type: "assistant", message: {content: [{type: "tool_use", name: $n, input: $i}]}}'; }
rec_bash() { rec_tool Bash "$(jq -nc --arg c "$1" '{command: $c}')"; }
rec_edit() { rec_tool "$1" "$(jq -nc --arg p "$2" '{file_path: $p}')"; }
# rec_skill
# A forked run as stream-json records it: the Skill call; the skill's body,
# report template included, as a user text record inside the fork; the fork's
# own tool calls, tagged with the Skill call's id as parent_tool_use_id; and
# the report coming back as the Skill's tool_result. The shape was measured on
# real forked runs of review-design and of review-test (proactive-with-claude-md);
# the Read inside the fork is a stand-in.
# The fork emitted no text record of its own in any of them, which is all that
# keeps a heading inside the fork from counting as the caller's: the heading
# check reads every assistant text, tagged or not. Tool calls inside the fork
# are counted on purpose -- they are the skill's own -- text must not be.
# None of it is the caller's words, so none of it counts as having reported --
# the caller still has to write the report out. What happens inside the fork is
# the skill's own doing, though, and its boundary holds there too.
# Set for one call:
#   skill_inside  records the fork makes, in rec_* calls (default: one Read)
#   skill_result  what the Skill hands back (default: a placeholder)
#   skill_args    the brief it is started with (default: "brief")
skill_seq=0
rec_skill() {
  local id
  skill_seq=$((skill_seq + 1))
  id="toolu_skill_$skill_seq"
  jq -nc --arg id "$id" --arg args "${skill_args:-brief}" \
    '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "Skill", input: {skill: "review-test", args: $args}}]}}'
  jq -nc --arg id "$id" --rawfile body "$repo_root/root/.agents/skills/review-test/SKILL.md" \
    '{type: "user", parent_tool_use_id: $id, message: {content: [{type: "text", text: ("Base directory for this skill: .claude/skills/review-test\n\n" + $body)}]}}'
  eval "${skill_inside:-rec_edit Read lib/quantity.test.sh}" | jq -c --arg id "$id" '. + {parent_tool_use_id: $id}'
  jq -nc --arg id "$id" --arg r "${skill_result:-(the review)}" \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: ("Skill \"review-test\" completed (forked execution).\n\nResult:\n" + $r)}]}}'
}

report='## テストレビュー: lib/quantity.test.sh

### P1 (Critical)
- parse_quantity の拒否（空・数値以外・負数で status 1、stderr のメッセージ）がテストされていない'

# --- running one scenario ---
# new_run <case>: the fixture its scaffold builds, an empty transcript.
new_run() {
  case_name="$1"
  work="$root_dir/work"
  art="$root_dir/art"
  rm -rf "$work" "$art"
  mkdir -p "$work" "$art"
  (
    cd "$work" || exit 1
    SKILL_EVAL_LIB_DIR="$repo_root/bin" SKILL_EVAL_REPO_ROOT="$repo_root" \
      bash "$evals_dir/$case_name/scaffold.sh"
    printf '.claude/\nbin/\n' >>.git/info/exclude
  ) || return 1
  rec_init >"$art/transcript.jsonl"
}

# in_work <command>: change the fixture the way the run under test did.
in_work() {
  (
    cd "$work" || exit 1
    # shellcheck source=./lib.sh
    . "$evals_dir/lib.sh"
    eval "$1"
  ) >/dev/null 2>&1
}

# A suite that fails. An assertion is changed rather than an `exit 1` appended:
# the file already ends in `exit "$fails"`, so anything after it never runs.
# shellcheck disable=SC2016  # expanded later, inside in_work
break_a_test='sed "s/\"parses a plain number\" \"12.5\"/\"parses a plain number\" \"99\"/" lib/quantity.test.sh >lib/t.tmp; mv lib/t.tmp lib/quantity.test.sh'

# grade <final response>
grade() {
  jq -nc --arg r "$1" '{type: "result", result: $r, permission_denials: []}' >"$art/result.json"
  out="$(
    cd "$work" || exit 1
    SKILL_EVAL_LIB_DIR="$repo_root/bin" \
      SKILL_EVAL_REPO_ROOT="$repo_root" \
      SKILL_EVAL_TRANSCRIPT="$art/transcript.jsonl" \
      SKILL_EVAL_RESULT_FILE="$art/result.json" \
      SKILL_EVAL_CLAUDE_BIN="$judge" \
      bash "$evals_dir/$case_name/assert.sh" 2>&1
  )"
  status=$?
}

expect_pass() {
  if [ "$status" -eq 0 ] && ! grep -q '^FAIL' <<<"$out"; then
    ok "$1"
  else
    bad "$1"
    grep '^FAIL' <<<"$out" | sed 's/^/       /'
  fi
}

# expect_fail <label> <the assertion that must FAIL>
# Both halves: the FAIL line is for a human reading assert.log, the status is
# what the runner grades on.
expect_fail() {
  if grep -qF "FAIL  $2" <<<"$out"; then
    ok "$1"
  else
    bad "$1 (expected FAIL: $2)"
    grep '^FAIL' <<<"$out" | sed 's/^/       got: /'
  fi
  if [ "$status" -eq 0 ]; then
    bad "$1 — the grader exited 0"
  fi
}

# ============================================================
# gaps-in-error-contract
# ============================================================
# A good run: the skill loads, reads, reports the untested refusals; the
# caller fixes the tests, reviews again with a brief naming the fix, gets a
# clean round, and commits. The first round hands back $report unless the
# scenario sets skill_result.
#   gaps_run <records before the report> <report> <records after> <tree change>
gaps_run() {
  new_run gaps-in-error-contract || return 1
  {
    skill_result="${skill_result-$report}" rec_skill
    rec_edit Read lib/quantity.test.sh
    eval "$1"
    [ -z "$2" ] || rec_text "$2"
    eval "$3"
  } >>"$art/transcript.jsonl"
  in_work "$4"
}
# The two are read only by the record string below, once gaps_run evals it.
# shellcheck disable=SC2034
clean_report='## テストレビュー: lib/quantity.test.sh

P1・P2 に該当する指摘はありません。'
# shellcheck disable=SC2034
rerun_brief='前回の P1（拒否の未テスト）を直した。lib/quantity.test.sh を再レビューして。'
# shellcheck disable=SC2016  # expanded when eval'd, not here
gaps_rerun='skill_args="$rerun_brief" skill_result="$clean_report" rec_skill'
gaps_after='rec_edit Edit lib/quantity.test.sh; rec_bash ./run-tests.sh; '"$gaps_rerun"'; rec_bash "git add lib/quantity.test.sh"; rec_bash "git commit -m test"'
gaps_fix='review_test_write_thorough_test; git add -A; git commit -q -m "test: cover the refusals"'

gaps_run '' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_pass "gaps: a good run passes every assertion"

# The heading lives in the SKILL.md the Skill tool loaded. A run that never
# wrote a report must still fail.
gaps_run '' '' "$gaps_after" "$gaps_fix"
grade "テストを直しました。"
expect_fail "gaps: a heading only in the loaded SKILL.md is not a report" \
  "reports under a test-review heading"

# Forked, the report first arrives as the Skill's result, which the user does
# not necessarily see. A caller that went straight on to its fixes without
# writing it out did not report -- a real run of review-design did exactly that.
skill_result="$report" gaps_run '' '' "$gaps_after" "$gaps_fix"
grade "テストを直しました。"
expect_fail "gaps: a report left in the Skill's result is not a report" \
  "reports under a test-review heading"

# A sentence announcing the review is not the review. Counted as one, it moves
# the line "nothing written before the report" to before the write.
gaps_run 'rec_text "テストレビューを始めます。"; rec_edit Edit lib/quantity.test.sh' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: a preamble naming the review does not count as the report" \
  "wrote nothing before the review was reported"

gaps_run 'rec_edit Edit lib/quantity.test.sh' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: an Edit before the report is caught" \
  "wrote nothing before the review was reported"

gaps_run 'rec_edit Write lib/quantity.test.sh' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: a Write before the report is caught" \
  "wrote nothing before the review was reported"

gaps_run 'rec_bash "git log --oneline"' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: git before the report is caught" \
  "ran no git before the review was reported"

# The same boundary inside the fork, where the skill itself acts. A helper that
# skipped records tagged with parent_tool_use_id would stop watching the very
# skill these checks exist for, and every control above would stay green.
skill_inside='rec_edit Edit lib/quantity.test.sh' gaps_run '' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: an Edit inside the fork is caught" \
  "wrote nothing before the review was reported"

skill_inside='rec_bash "git diff"' gaps_run '' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: git inside the fork is caught" \
  "ran no git before the review was reported"

gaps_run '' "$report" '' ''
grade "P1 があります。"
expect_fail "gaps: a review that fixes nothing is caught" \
  "changed the test file"

gaps_run '' "$report" "$gaps_after" "$break_a_test"'; git add -A; git commit -q -m broken'
grade "P1 を直してコミットしました。"
expect_fail "gaps: a fix that breaks the suite is caught" \
  "the tests still pass afterwards"

gaps_run '' "$report" "$gaps_after" 'review_test_write_thorough_test'
grade "P1 を直しました。"
expect_fail "gaps: a fix left uncommitted is caught" \
  "committed the result"

gaps_run '' "$report" "$gaps_after" "$gaps_fix"' ; printf "# touched\n" >>lib/quantity.sh; git add -A; git commit -q -m impl'
grade "P1 を直してコミットしました。"
expect_fail "gaps: a changed implementation is caught" \
  "left the implementation untouched"

skill_result="$report
JUDGE_FAIL" gaps_run '' "$report" "$gaps_after" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: the P1 judge reads the first round's report" \
  "P1 names the untested error contract"

# ... and not the final response, which a looping run ends on a clean round.
gaps_run '' "$report" "$gaps_after" "$gaps_fix"
grade "JUDGE_FAIL"
expect_pass "gaps: the P1 judge does not read the final response"

gaps_run '' "$report" "$gaps_after" "$gaps_fix"'; printf "# JUDGE_FAIL\n" >>lib/quantity.test.sh; git add -A; git commit -q -m mark'
grade "P1 を直してコミットしました。"
expect_fail "gaps: the fixed-tests judge reads the test file" \
  "the fixed tests exercise the failure behaviour"

# --- the loop ("## After the review", steps 2-3) ---
gaps_commit='rec_bash "git add lib/quantity.test.sh"; rec_bash "git commit -m test"'
gaps_fix_edit='rec_edit Edit lib/quantity.test.sh; rec_bash ./run-tests.sh'

gaps_run '' "$report" "$gaps_fix_edit; $gaps_commit" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: fixing and stopping without a second review is caught" \
  "reviewed again after fixing (two rounds or more)"

# The re-run comes before the fix: the second round reviewed what the first did.
gaps_run '' "$report" "$gaps_rerun; $gaps_fix_edit; $gaps_commit" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: a re-run with nothing fixed before it is caught" \
  "fixed something before every re-run"

gaps_run '' "$report" "$gaps_fix_edit; skill_args=\"\$rerun_brief\" skill_result=\"\$report\" rec_skill; $gaps_commit" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: stopping on a round that still reports P1 is caught" \
  "the last round reports no P1 and no P2"

gaps_run '' "$report" "$gaps_after; $gaps_rerun" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: a third round after a clean one is caught" \
  "re-ran only after a round with P1 or P2"

gaps_run '' "$report" "$gaps_fix_edit; skill_args=JUDGE_FAIL skill_result=\"\$clean_report\" rec_skill; $gaps_commit" "$gaps_fix"
grade "P1 を直してコミットしました。"
expect_fail "gaps: the brief judge reads the re-run's brief" \
  "each re-run's brief says what the last round fixed"

# ============================================================
# well-tested-no-false-p1
# ============================================================
#   well_run <records before the report> <report> <tree change>
well_run() {
  new_run well-tested-no-false-p1 || return 1
  {
    rec_skill
    rec_edit Read lib/quantity.test.sh
    eval "$1"
    [ -z "$2" ] || rec_text "$2"
  } >>"$art/transcript.jsonl"
  in_work "$3"
}
well_report='## テストレビュー: lib/quantity.test.sh

P1 に該当する指摘はありません。'

well_run '' "$well_report" ''
grade "$well_report"
expect_pass "well-tested: a good run passes every assertion"

# The forms grading.sh accepts on purpose, because runs vary them. Each one
# dropped by a "simplified" regex fails a correct report in a paid run.
for heading in \
  '## Test review: lib/quantity.test.sh' \
  '**テストレビュー: lib/quantity.test.sh**' \
  '## テストレビュー：lib/quantity.test.sh' \
  'テストを読みました。

## テストレビュー: lib/quantity.test.sh'; do
  well_run '' "$heading" ''
  grade "$heading"
  expect_pass "well-tested: the report heading is found as: ${heading%%$'\n'*}"
done

well_run '' '' ''
grade "問題ありません。"
expect_fail "well-tested: a heading only in the loaded SKILL.md is not a report" \
  "reports under a test-review heading"

skill_result="$well_report" well_run '' '' ''
grade "問題ありません。"
expect_fail "well-tested: a report left in the Skill's result is not a report" \
  "reports under a test-review heading"

well_run 'rec_edit Write lib/extra.test.sh' "$well_report" ''
grade "$well_report"
expect_fail "well-tested: a Write before the report is caught" \
  "wrote nothing before the review was reported"

well_run '' "$well_report" 'printf "# touched\n" >>lib/quantity.sh'
grade "$well_report"
expect_fail "well-tested: a changed implementation is caught" \
  "left the implementation untouched"

well_run '' "$well_report" "$break_a_test"
grade "$well_report"
expect_fail "well-tested: a broken suite is caught" \
  "the tests still pass afterwards"

# The first round is clean, so starting it again is the waste being measured.
well_run 'rec_skill' "$well_report" ''
grade "$well_report"
expect_fail "well-tested: a second start after a clean round is caught" \
  "did not re-run after a round with no P1 or P2"

well_run '' "$well_report" ''
grade "JUDGE_FAIL"
expect_fail "well-tested: the no-P1 judge reads the final response" \
  "raises no P1 against tests that cover the contract"

# ============================================================
# proactive-after-writing-tests
# ============================================================
# A good run: the tests are written and pass, the skill starts on its own,
# reports, and the result is committed afterwards.
#   proactive_run <records before the report> <report> <tree change> [<skill starts>]
proactive_run() {
  local starts="${4:-1}" i
  new_run proactive-after-writing-tests || return 1
  {
    rec_edit Write lib/quantity.test.sh
    rec_bash ./run-tests.sh
    eval "$1"
    rec_bash "git add lib/quantity.test.sh"
    rec_bash "git commit -m test"
    for ((i = 0; i < starts; i++)); do rec_skill; done
    [ -z "$2" ] || rec_text "$2"
  } >>"$art/transcript.jsonl"
  in_work "$3"
}
proactive_write='review_test_write_thorough_test; git add -A; git commit -q -m "test: add quantity tests"'
proactive_final="テストを書き、レビューの P1・P2 はありませんでした。コミット済みです。"

proactive_run '' "$well_report" "$proactive_write"
grade "$proactive_final"
expect_pass "proactive: a good run passes every assertion"

proactive_run '' "$well_report" "$proactive_write" 0
grade "$proactive_final"
expect_fail "proactive: a run that never starts the skill is caught" \
  "started review-test without being asked"

proactive_run '' "$well_report" "$proactive_write"'; '"$break_a_test"'; git add -A; git commit -q -m broken'
grade "$proactive_final"
expect_fail "proactive: tests it wrote that fail are caught" \
  "the tests it wrote pass"

proactive_run '' '' "$proactive_write"
grade "$proactive_final"
expect_fail "proactive: a heading only in the loaded SKILL.md is not a report" \
  "reports under a test-review heading"

# Here above all: the case asks whether a review nobody requested reached the
# user, and a result only the caller saw did not.
skill_result="$well_report" proactive_run '' '' "$proactive_write"
grade "$proactive_final"
expect_fail "proactive: a report left in the Skill's result is not a report" \
  "reports under a test-review heading"

proactive_run '' "$well_report" ''
grade "$proactive_final"
expect_fail "proactive: a run that wrote no test file is caught" \
  "wrote a test file for lib/quantity.sh"

proactive_run '' "$well_report" 'review_test_write_thorough_test'
grade "$proactive_final"
expect_fail "proactive: tests left uncommitted are caught" \
  "committed the result"

# Another skill before the commit -- a real run called `commit`, which
# root/CLAUDE.md names -- is not review-test starting early.
proactive_run 'rec_tool Skill "{\"skill\":\"commit\"}"' "$well_report" "$proactive_write"
grade "$proactive_final"
expect_pass "proactive: another skill before the commit does not count as an early start"

# The loop checks this grader carries: a second start after a clean round, and
# a round that still reports a P1 left as the last.
proactive_run '' "$well_report" "$proactive_write" 2
grade "$proactive_final"
expect_fail "proactive: a second start after a clean round is caught" \
  "re-ran only after a round with P1 or P2"
expect_fail "proactive: ... with nothing fixed before it" \
  "fixed something before every re-run"

skill_result="$report" proactive_run '' "$well_report" "$proactive_write"
grade "$proactive_final"
expect_fail "proactive: stopping on a round that still reports P1 is caught" \
  "the last round reports no P1 and no P2"

proactive_run '' "$well_report" "$proactive_write"'; printf "# touched\n" >>lib/quantity.sh; git add -A; git commit -q -m impl'
grade "$proactive_final"
expect_fail "proactive: a changed implementation is caught" \
  "left the implementation untouched"

# A review in the middle of the unit, before its commit: the per-batch trigger.
proactive_run 'rec_skill' "$well_report" "$proactive_write" 0
grade "$proactive_final"
expect_fail "proactive: a review before the commit is caught" \
  "started it at the breakpoint: after the work was committed"

proactive_run '' "$well_report" "$proactive_write"
grade "JUDGE_FAIL"
expect_fail "proactive: the P1/P2 judge reads the final response" \
  "reaches a conclusion about P1 and P2"

# ============================================================
# proactive-with-claude-md
# ============================================================
# Its scaffold and grader are proactive-after-writing-tests's own, by exec. The
# prompt cannot be, so what keeps the pair a pair -- the same request under the
# same tools -- is checked here: edited on one side only, the difference
# between the two cases would no longer be the CLAUDE.md's.
pair_part() { # <case> body|allowed_tools
  awk -v part="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { inside = 0; next }
    inside { if (part == "allowed_tools" && index($0, "allowed_tools:") == 1) print; next }
    part == "body" { print }
  ' "$evals_dir/$1/prompt.md"
}
for part in body allowed_tools; do
  without="$(pair_part proactive-after-writing-tests "$part")"
  with="$(pair_part proactive-with-claude-md "$part")"
  if [ -n "$without" ] && [ "$without" = "$with" ]; then
    ok "the CLAUDE.md pair shares its prompt $part"
  else
    bad "the CLAUDE.md pair shares its prompt $part"
  fi
done

# ============================================================
# no-fire-test-typo
# ============================================================
#   typo_run <skill starts> <tree change>
typo_run() {
  local i
  new_run no-fire-test-typo || return 1
  {
    rec_edit Edit lib/quantity.test.sh
    rec_bash ./run-tests.sh
    rec_bash "git commit -am fix"
    for ((i = 0; i < $1; i++)); do rec_skill; done
  } >>"$art/transcript.jsonl"
  in_work "$2"
}
typo_fix='sed "s/\"pases a plain number\"/\"parses a plain number\"/" lib/quantity.test.sh >lib/t.tmp; mv lib/t.tmp lib/quantity.test.sh; git commit -qam "test: fix a typo"'

# The scaffold must plant the typo, or "fixed" holds before the run starts.
typo_run 0 :
grade "直しました。"
expect_fail "no-fire: the scaffold plants the typo" "the test name is fixed"

typo_run 0 "$typo_fix"
grade "直してコミットしました。"
expect_pass "no-fire: a good run passes every assertion"

typo_run 1 "$typo_fix"
grade "直してコミットしました。"
expect_fail "no-fire: a review started for a typo is caught" \
  "did not start review-test for a typo in a test name"

typo_run 0 "$typo_fix; $break_a_test; git commit -qam broken"
grade "直してコミットしました。"
expect_fail "no-fire: a failing suite is caught" "the tests pass"

typo_run 0 "${typo_fix%; git commit*}"
grade "直しました。"
expect_fail "no-fire: a fix left uncommitted is caught" "committed the fix"

if [ "$fails" -eq 0 ]; then
  printf '\nall review-test grader tests passed\n'
  exit 0
fi
printf '\n%d review-test grader test(s) failed\n' "$fails"
exit 1
