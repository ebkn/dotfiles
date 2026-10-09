#!/bin/bash
#
# assert.test.sh — pins the graders of every review-design eval case, and the
# grading.sh they share, without calling the API.
#
# A grader is an instrument, and an inert one reports a paid, non-deterministic
# eval run that measured nothing. So for each case this builds the fixture its
# scaffold.sh builds, plays a good run onto it -- a synthetic transcript, and
# the fix a correct caller would commit -- and checks that every assertion
# passes. Then it breaks one thing at a time and checks that the matching
# assertion FAILs and the grader exits non-zero.
#
# The six cases that review a finished unit share most of their checks, through
# grading.sh but each with its own arguments (which tags, which test files), so
# those checks are provoked once per case rather than once per helper.
#
# The synthetic transcripts carry the body of SKILL.md, which the Skill tool
# loads into the conversation, report template included. The shape is taken
# from Claude Code's session log; whether stream-json emits that record is not
# verified, and the controls need only that it is not an assistant record.
#
# check_llm is graded by a stub judge that fails exactly when the text it was
# handed contains JUDGE_FAIL. That pins the wiring -- each judged check reads
# the text it claims to read -- not the rubric, which only a real run can
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

# shellcheck source=./lib.sh
. "$evals_dir/lib.sh"

# --- transcript records, in the stream-json shape the helpers read ---
rec_init() { printf '{"type":"system","subtype":"init"}\n'; }
rec_text() { jq -nc --arg t "$1" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}'; }
rec_tool() { jq -nc --arg n "$1" --argjson i "$2" '{type: "assistant", message: {content: [{type: "tool_use", name: $n, input: $i}]}}'; }
rec_bash() { rec_tool Bash "$(jq -nc --arg c "$1" '{command: $c}')"; }
rec_edit() { rec_tool "$1" "$(jq -nc --arg p "$2" '{file_path: $p}')"; }
rec_skill() {
  rec_tool Skill '{"skill":"review-design"}'
  jq -nc '{type: "user", message: {content: [{type: "tool_result", content: "Launching skill: review-design"}]}}'
  jq -nc --rawfile body "$repo_root/root/.agents/skills/review-design/SKILL.md" \
    '{type: "user", message: {content: [{type: "text", text: $body}]}}'
}

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
      bash "$evals_dir/$case_name/scaffold.sh" </dev/null
    printf '.claude/\nbin/\n' >>.git/info/exclude
  ) >/dev/null 2>&1 || return 1
  rec_init >"$art/transcript.jsonl"
}

# in_work <command>: change the fixture the way the run under test did. The
# fix_* functions below and lib.sh's helpers are visible here.
in_work() {
  (
    cd "$work" || exit 1
    eval "$1"
  ) </dev/null >/dev/null 2>&1
}

short() { git -C "$work" rev-parse --short "$1"; }

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
      bash "$evals_dir/$case_name/assert.sh" 2>&1 </dev/null
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

# --- what a correct caller commits after each review ---
# shellcheck disable=SC2329  # called through in_work's eval
commit_fix() {
  git add -A
  git commit -q -m "$1"
}

# shellcheck disable=SC2329
fix_stale() {
  # The docs catch up with the code; the code and tests stay as the unit left them.
  review_design_unit_skip_with_docs
  commit_fix "docs: describe skipping unreadable weights"
}

# shellcheck disable=SC2329,SC2016  # the strings are quantity.sh's own lines
fix_hidden() {
  # Introduce Parameter, with the clock as its default.
  _review_design_replace_line_raw lib/quantity.sh \
    '  printf '\''%st on %s\n'\'' "$1" "$(date +%F)"' \
    '  printf '\''%st on %s\n'\'' "$1" "${2:-$(date +%F)}"'
  commit_fix "refactor: let a caller hand stamp_total the date"
}

# shellcheck disable=SC2329,SC2016  # the strings are the scripts' own lines
fix_next() {
  # The unit is written in one place both scripts call.
  cat >>lib/quantity.sh <<'PART'

# format_total <total>
# Print <total> with its unit, as in "15.5t".
format_total() {
  printf '%st\n' "$1"
}
PART
  _review_design_replace_line_raw total.sh 'printf '\''%st\n'\'' "$total"' 'format_total "$total"'
  _review_design_replace_line_raw delivery.sh 'printf '\''%st\n'\'' "$total"' 'format_total "$total"'
  # The line helpers rewrite through mv, which drops the execute bit.
  chmod +x total.sh delivery.sh
  commit_fix "refactor: format a total with its unit in one place"
}

# shellcheck disable=SC2329,SC2016  # the strings are delivery.sh's own lines
fix_pass() {
  # Inline Function: the forwarder goes, its one caller calls through.
  _review_design_replace_line_raw lib/delivery.sh '  delivery_sum "${weights[@]}"' '  sum_quantities "${weights[@]}"'
  sed '/^# delivery_sum <input>/,/^}/d' lib/delivery.sh >lib/delivery.sh.new
  mv lib/delivery.sh.new lib/delivery.sh
  commit_fix "refactor: inline delivery_sum"
}

# shellcheck disable=SC2329
fix_nofire() {
  # Undo the planted bug: the unit is dropped in either case again.
  awk '{ i = index($0, "s/t$//"); if (i) $0 = substr($0, 1, i - 1) "s/[tT]$//" substr($0, i + 6) } 1' \
    lib/quantity.sh >lib/quantity.sh.new
  mv lib/quantity.sh.new lib/quantity.sh
  commit_fix "fix: read an upper-case unit"
}

# shellcheck disable=SC2329,SC2016  # total.sh's and the test's own lines
fix_kg() { # [<the line of total.sh that totals>]
  # The feature the proactive case asks for: --kg, with a test, committed.
  # next-change-scattered's total.sh totals on a different line, hence the
  # anchor.
  _review_design_insert_before total.sh "${1:-sum_quantities \"\$@\"}" \
    'if [ "${1:-}" = "--kg" ]; then\n  shift\n  total="$(sum_quantities "$@")"\n  awk -v t="$total" '\''BEGIN { print t * 1000 }'\''\n  exit 0\nfi'
  _review_design_insert_before total.test.sh 'exit "$fails"' \
    't "prints kilograms with --kg" "3000" "$(./total.sh --kg 1t 2t)"'
  chmod +x total.sh
  commit_fix "feat: print the total in kilograms with --kg"
}

# Mutations a negative control applies on top of a good run.
# shellcheck disable=SC2329
drop_a_test() {
  awk 'index($0, "t \"--help exits 0\"") != 1' total.test.sh >total.test.sh.new
  mv total.test.sh.new total.test.sh
  commit_fix "test: drop one"
}
# shellcheck disable=SC2329,SC2016
add_a_passing_test() {
  _review_design_insert_before total.test.sh 'exit "$fails"' 't "--help prints the usage" "0" "$(./total.sh --help >/dev/null; printf '\''%s'\'' "$?")"'
  commit_fix "test: add one"
}
# shellcheck disable=SC2329,SC2016
add_a_failing_test() {
  _review_design_insert_before total.test.sh 'exit "$fails"' 't "fails on purpose" "a" "b"'
  commit_fix "test: add a failing one"
}

# ============================================================
# The six cases that review a finished unit
# ============================================================
# design_run <case> <report> <records before the report> <records after> <tree change> [<skill starts>]
# <report> is "none" for no report, or text in which BASE and HEAD stand for
# the abbreviated hashes of eval-base and unit-done.
good_report='## 設計レビュー: BASE..HEAD

### P1
- 指摘

Reviewed: BASE..HEAD'
before_default='rec_bash "git log --oneline main..HEAD"; rec_bash "git diff --stat main...HEAD"'
after_default='rec_edit Edit README.md; rec_bash ./run-tests.sh; rec_bash "git add -A"; rec_bash "git commit -m fix"'

design_run() {
  local report="$2" starts="${6:-1}" base head i
  new_run "$1" || return 1
  base="$(short eval-base)"
  head="$(short unit-done)"
  report="${report//BASE/$base}"
  report="${report//HEAD/$head}"
  {
    for ((i = 0; i < starts; i++)); do rec_skill; done
    eval "$3"
    [ "$report" = none ] || rec_text "$report"
    eval "$4"
  } >>"$art/transcript.jsonl"
  in_work "$5"
}

# case name | its fix
review_cases='stale-doc-after-change fix_stale
clean-unit-no-false-p1 :
hidden-clock-no-seam fix_hidden
intended-layer-asks :
next-change-scattered fix_next
pass-through-layer fix_pass'

while read -r c fix; do
  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_pass "$c: a good run passes every assertion"

  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix" 0
  grade "直してコミットしました。"
  expect_fail "$c: a run that never starts the skill is caught" "started review-design"

  design_run "$c" none "$before_default" "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_fail "$c: a heading only in the loaded SKILL.md is not a report" \
    "reported under a design-review heading"

  # The range must be the unit's: right shape, wrong hashes -- at either end.
  design_run "$c" "${good_report//..HEAD/..BASE}" "$before_default" "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_fail "$c: a Reviewed line ending at the wrong commit is caught" \
    "names the range it reviewed: eval-base..unit-done"

  design_run "$c" "${good_report//BASE../HEAD..}" "$before_default" "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_fail "$c: a Reviewed line starting at the wrong commit is caught" \
    "names the range it reviewed: eval-base..unit-done"

  design_run "$c" "$good_report" "$before_default"'; rec_edit Edit README.md' "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_fail "$c: an Edit before the report is caught" \
    "wrote nothing before the review was reported"

  design_run "$c" "$good_report" "$before_default"'; rec_edit Write NOTES.md' "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_fail "$c: a Write before the report is caught" \
    "wrote nothing before the review was reported"

  design_run "$c" "$good_report" "$before_default"'; rec_bash "git commit -m early"' "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_fail "$c: git that writes before the report is caught" \
    "ran no git that writes before the review was reported"

  # One review plus three re-reviews is the cap itself, not past it.
  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix" 4
  grade "直してコミットしました。"
  expect_pass "$c: a review loop of exactly four passes"

  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix" 5
  grade "直してコミットしました。"
  expect_fail "$c: a review loop past its cap is caught" \
    "kept the review loop within its cap of four"

  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix; printf 'x\n' >stray.txt"
  grade "直してコミットしました。"
  expect_fail "$c: something left uncommitted is caught" "left nothing uncommitted"

  design_run "$c" "$good_report" "$before_default" "$after_default" "git commit -q --amend -m amended; $fix"
  grade "直してコミットしました。"
  expect_fail "$c: an amended unit commit is caught" "kept the unit's commit as it was"

  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix; drop_a_test"
  grade "直してコミットしました。"
  expect_fail "$c: a removed test line is caught" "changed none of the"

  # A new test beside the kept ones changes nothing they expect: deliberately
  # allowed, since a fix may add one for a function it extracted.
  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix; add_a_passing_test"
  grade "直してコミットしました。"
  expect_pass "$c: a test added beside the kept ones passes"

  design_run "$c" "$good_report" "$before_default" "$after_default" "$fix; add_a_failing_test"
  grade "直してコミットしました。"
  expect_fail "$c: a failing suite is caught" "the tests still pass afterwards"
done <<<"$review_cases"

# --- the report heading and the git boundary (grading.sh) ---
# The forms REVIEW_DESIGN_REPORT_HEADING accepts on purpose, because runs vary
# them. Each one dropped by a "simplified" regex fails a correct report in a
# paid run.
for form in \
  '## Design review: BASE..HEAD' \
  '**設計レビュー: BASE..HEAD**' \
  '## 設計レビュー：BASE..HEAD' \
  'レビューしました。

## 設計レビュー: BASE..HEAD'; do
  design_run clean-unit-no-false-p1 "$form

Reviewed: BASE..HEAD" "$before_default" "$after_default" :
  grade "問題ありませんでした。"
  expect_pass "grading.sh: the report heading is found as: ${form%%$'\n'*}"
done

# A sentence announcing the review is not the review: counted as one, it moves
# "nothing written before the report" to before the write.
design_run clean-unit-no-false-p1 "$good_report" \
  "$before_default"'; rec_text "設計レビューを始めます。"; rec_edit Edit README.md' "$after_default" :
grade "問題ありませんでした。"
expect_fail "grading.sh: a preamble naming the review does not count as the report" \
  "wrote nothing before the review was reported"

# The skill runs git to read its range, so reading git before the report is
# allowed -- including the near misses the regex is written to tell apart.
design_run clean-unit-no-false-p1 "$good_report" \
  'rec_bash "git merge-base main HEAD"; rec_bash "git -C . log --oneline"; rec_bash "git diff main -- add.sh"; rec_bash "git --no-pager show HEAD"' \
  "$after_default" :
grade "問題ありませんでした。"
expect_pass "grading.sh: reading git before the report is allowed"

# Each way a command line can lead into git: after whitespace, after a shell
# operator with no space, inside a subshell.
for cmd in 'git -C . commit -m x' 'git diff --output=x.patch' 'echo hi && git add .' 'git -c user.name=x stash' \
  'echo hi;git commit -m x' '(git add .)' 'true&&git rm -q README.md'; do
  design_run clean-unit-no-false-p1 "$good_report" "rec_bash \"$cmd\"" "$after_default" :
  grade "問題ありませんでした。"
  expect_fail "grading.sh: writing git before the report is caught: $cmd" \
    "ran no git that writes before the review was reported"
done

# --- per-case assertions ---
# stale-doc-after-change
judged_report="$good_report
JUDGE_FAIL"
design_run stale-doc-after-change "$judged_report" "$before_default" "$after_default" fix_stale
grade "直してコミットしました。"
expect_fail "stale-doc: the interface-list judge reads the report" \
  "lists the changed interface with its caller outside the range"
expect_fail "stale-doc: the P1 judge reads the report" \
  "P1 names a doc that still describes the refusal"

# Each stale sentence left in place, one doc at a time.
for doc in lib/quantity.sh total.sh README.md; do
  design_run stale-doc-after-change "$good_report" "$before_default" "$after_default" \
    "fix_stale; git show unit-done:$doc >$doc; commit_fix 'revert one doc'"
  grade "直してコミットしました。"
  case "$doc" in
    lib/quantity.sh) needle="sum_quantities' comment no longer promises no partial sum" ;;
    total.sh) needle="total.sh's usage text no longer promises to print nothing" ;;
    README.md) needle="the README no longer says an unreadable weight fails the total" ;;
  esac
  expect_fail "stale-doc: $doc left describing the refusal is caught" "$needle"
done

# The judge is handed all three docs; each must reach it.
for doc in lib/quantity.sh total.sh README.md; do
  design_run stale-doc-after-change "$good_report" "$before_default" "$after_default" \
    "fix_stale; printf '# JUDGE_FAIL\n' >>$doc; commit_fix mark"
  grade "直してコミットしました。"
  expect_fail "stale-doc: the skipping-docs judge reads $doc" "all three docs now describe skipping"
done

# "Fixing" the drift by turning the code back to match the docs.
design_run stale-doc-after-change "$good_report" "$before_default" "$after_default" \
  "git show eval-base:lib/quantity.sh >lib/quantity.sh; commit_fix 'revert the code'"
grade "直してコミットしました。"
expect_fail "stale-doc: code turned back to refusing is caught" \
  "left what an all-unreadable total does as the unit made it"

design_run stale-doc-after-change "$good_report" "$before_default" "$after_default" :
grade "P1 を報告しました。"
expect_fail "stale-doc: a review with no fix commit is caught" "committed the fix on its own"

# clean-unit-no-false-p1
design_run clean-unit-no-false-p1 "$judged_report" "$before_default" "$after_default" :
grade "問題ありませんでした。"
expect_fail "clean-unit: the no-P1 judge reads the report" \
  "raises no P1 against a unit whose docs moved with its code"
expect_fail "clean-unit: the checked-list judge reads the report" \
  "says what it checked, having found nothing to fix"

design_run clean-unit-no-false-p1 "$good_report" "$before_default" "$after_default" \
  "printf '# JUDGE_FAIL\n' >>total.sh; commit_fix mark"
grade "問題ありませんでした。"
expect_fail "clean-unit: the skipping-docs judge reads the docs" "the docs still describe skipping"

design_run clean-unit-no-false-p1 "$good_report" "$before_default" "$after_default" \
  "git show eval-base:lib/quantity.sh >lib/quantity.sh; commit_fix 'revert the code'"
grade "問題ありませんでした。"
expect_fail "clean-unit: code turned back to refusing is caught" \
  "left what an all-unreadable total does as the unit made it"

# hidden-clock-no-seam
design_run hidden-clock-no-seam "$judged_report" "$before_default" "$after_default" fix_hidden
grade "直してコミットしました。"
expect_fail "hidden-clock: the seam-finding judge reads the report" \
  "a P1 or P2 finding names the clock read with no seam"

for f in lib/quantity.sh total.sh; do
  design_run hidden-clock-no-seam "$good_report" "$before_default" "$after_default" \
    "fix_hidden; printf '# JUDGE_FAIL\n' >>$f; commit_fix mark"
  grade "直してコミットしました。"
  expect_fail "hidden-clock: the seam judge reads $f" \
    "the date can now be supplied from outside stamp_total"
done

design_run hidden-clock-no-seam "$good_report" "$before_default" "$after_default" \
  "fix_hidden; printf '# JUDGE_FAIL\n' >>lib/quantity.test.sh; commit_fix mark"
grade "直してコミットしました。"
expect_fail "hidden-clock: the test-diff judge reads the module's test diff" \
  "the module's tests changed, if at all, only to use the seam"

# shellcheck disable=SC2016  # quantity.sh's own line
design_run hidden-clock-no-seam "$good_report" "$before_default" "$after_default" \
  'fix_hidden; _review_design_replace_line_raw lib/quantity.sh "  printf '\''%st on %s\n'\'' \"\$1\" \"\${2:-\$(date +%F)}\"" "  printf '\''%st, %s\n'\'' \"\$1\" \"\${2:-\$(date +%F)}\""; commit_fix reword'
grade "直してコミットしました。"
expect_fail "hidden-clock: a changed stamped output is caught" "today's stamped total is unchanged"

design_run hidden-clock-no-seam "$good_report" "$before_default" "$after_default" :
grade "P1 を報告しました。"
expect_fail "hidden-clock: a review with no fix commit is caught" "committed the fix on its own"

# intended-layer-asks
design_run intended-layer-asks "$judged_report" "$before_default" "$after_default" :
grade "層を残すか決めてください。"
expect_fail "intended-layer: the shallow-layer judge reads the report" \
  "a P1 or P2 finding names the ticket layer as shallow"

design_run intended-layer-asks "$good_report" "$before_default" "$after_default" :
grade "JUDGE_FAIL"
expect_fail "intended-layer: the decision judge reads the closing message" \
  "puts removing the layer to the user as a decision"

# ... and the report, the other half of what it is handed.
design_run intended-layer-asks "$judged_report" "$before_default" "$after_default" :
grade "層を残すか決めてください。"
expect_fail "intended-layer: the decision judge reads the report" \
  "puts removing the layer to the user as a decision"

# Removing the layer anyway: total.sh back on quantity.sh, ticket.sh gone.
design_run intended-layer-asks "$good_report" "$before_default" "$after_default" \
  "git show eval-base:total.sh >total.sh; git rm -q lib/ticket.sh; commit_fix 'refactor: remove the ticket layer'"
grade "層を削除しました。"
expect_fail "intended-layer: total.sh taken off the layer is caught" \
  "left the layer in place: total.sh still goes through ticket_total"
expect_fail "intended-layer: a deleted layer is caught" \
  "left the layer in place: lib/ticket.sh still defines ticket_total"

design_run intended-layer-asks "$good_report" "$before_default" "$after_default" \
  "printf '# A negative weight is refused.\n' >>lib/ticket.sh; commit_fix 'docs: restate the contract'"
grade "層を残すか決めてください。"
expect_fail "intended-layer: quantity.sh's contract copied into the layer is caught" \
  "did not copy quantity.sh's contract phrases into the layer"

design_run intended-layer-asks "$good_report" "$before_default" "$after_default" \
  "printf '# JUDGE_FAIL\n' >>lib/ticket.sh; commit_fix mark"
grade "層を残すか決めてください。"
expect_fail "intended-layer: the restated-contract judge reads the layer" \
  "the layer's comments do not restate quantity.sh's contract"

# next-change-scattered
design_run next-change-scattered "$judged_report" "$before_default" "$after_default" fix_next
grade "直してコミットしました。"
expect_fail "next-change: the change-cost judge reads the report" \
  "P1 ties the scattered unit formatting to the planned kg output"

# Only one of the two scripts moved onto the shared formatter.
# shellcheck disable=SC2016  # delivery.sh's own line
design_run next-change-scattered "$good_report" "$before_default" "$after_default" \
  'fix_next; _review_design_replace_line_raw delivery.sh "format_total \"\$total\"" "printf '\''%st\n'\'' \"\$total\""; chmod +x delivery.sh; commit_fix "half back"'
grade "直してコミットしました。"
expect_fail "next-change: a script still writing the unit itself is caught" \
  "neither script writes the unit itself any more"

for f in lib/quantity.sh total.sh delivery.sh; do
  design_run next-change-scattered "$good_report" "$before_default" "$after_default" \
    "fix_next; printf '# JUDGE_FAIL\n' >>$f; commit_fix mark"
  grade "直してコミットしました。"
  expect_fail "next-change: the one-place judge reads $f" \
    "the unit is formatted in one place both scripts use"
done

# shellcheck disable=SC2016  # quantity.sh's own line
design_run next-change-scattered "$good_report" "$before_default" "$after_default" \
  'fix_next; _review_design_replace_line_raw lib/quantity.sh "  printf '\''%st\n'\'' \"\$1\"" "  printf '\''%s t\n'\'' \"\$1\""; commit_fix respace'
grade "直してコミットしました。"
expect_fail "next-change: a changed total output is caught" "total.sh still prints 15.5t"

# shellcheck disable=SC2016  # total.sh's own line
design_run next-change-scattered "$good_report" "$before_default" "$after_default" \
  'fix_next; fix_kg '\''total="$(sum_quantities "$@")"'\'''
grade "直してコミットしました。"
expect_fail "next-change: building the planned --kg itself is caught" \
  "did not make the planned change itself: --kg is still refused"

design_run next-change-scattered "$good_report" "$before_default" "$after_default" :
grade "P1 を報告しました。"
expect_fail "next-change: a review with no fix commit is caught" "committed the fix on its own"

# pass-through-layer
design_run pass-through-layer "$judged_report" "$before_default" "$after_default" fix_pass
grade "直してコミットしました。"
expect_fail "pass-through: the pass-through judge reads the report" \
  "a P1 or P2 finding names delivery_sum as a pass-through"

design_run pass-through-layer "$good_report" "$before_default" "$after_default" :
grade "P2 を報告しました。"
expect_fail "pass-through: a forwarder left in place is caught" "removed delivery_sum"
expect_fail "pass-through: ... and so is the missing fix commit" "committed the fix on its own"

# Renamed rather than removed: the name is gone, the forwarder is not.
design_run pass-through-layer "$good_report" "$before_default" "$after_default" \
  "sed 's/delivery_sum/add_up/g' lib/delivery.sh >lib/d.new; mv lib/d.new lib/delivery.sh; commit_fix rename"
grade "直してコミットしました。"
expect_fail "pass-through: a renamed forwarder is caught" "delivery_total calls sum_quantities itself"

# ============================================================
# no-fire-small-fix
# ============================================================
nofire_run() { # <skill starts> <tree change>
  local i
  new_run no-fire-small-fix || return 1
  {
    rec_edit Edit lib/quantity.sh
    rec_bash ./run-tests.sh
    rec_bash "git add lib/quantity.sh"
    rec_bash "git commit -m fix"
    for ((i = 0; i < $1; i++)); do rec_skill; done
  } >>"$art/transcript.jsonl"
  in_work "$2"
}

nofire_run 0 fix_nofire
grade "直してコミットしました。"
expect_pass "no-fire: a good run passes every assertion"

nofire_run 1 fix_nofire
grade "直してコミットしました。"
expect_fail "no-fire: starting the skill for a small fix is caught" \
  "did not start review-design for a small fix"

nofire_run 0 :
grade "直しました。"
expect_fail "no-fire: the bug left in place is caught" "an upper-case unit is read"

nofire_run 0 'fix_nofire; git reset -q --soft HEAD~1'
grade "直しました。"
expect_fail "no-fire: a fix left uncommitted is caught" "committed the fix"
expect_fail "no-fire: ... and so is the dirty tree" "left nothing uncommitted"

nofire_run 0 'fix_nofire; add_a_failing_test'
grade "直してコミットしました。"
expect_fail "no-fire: a failing suite is caught" "the tests pass"

# ============================================================
# proactive-at-breakpoint
# ============================================================
# proactive_run <records> <closing message> <tree change> [<skill starts>]
# The closing message is written after the tree, since it names the range: in
# it BASE is eval-base and HEAD the commit the unit ended on.
proactive_run() {
  local closing="$2" starts="${4:-1}" i
  new_run proactive-at-breakpoint || return 1
  in_work "$3"
  closing="${closing//BASE/$(short eval-base)}"
  closing="${closing//HEAD/$(short HEAD)}"
  {
    eval "$1"
    for ((i = 0; i < starts; i++)); do rec_skill; done
    rec_bash "git diff --stat main...HEAD"
  } >>"$art/transcript.jsonl"
  proactive_closing="$closing"
}
work_records='rec_edit Edit total.sh; rec_bash ./run-tests.sh; rec_bash "git add -A"; rec_bash "git commit -m feat"'
closing_ok='## 設計レビュー: BASE..HEAD
- 指摘なし。--kg の分岐と usage を確認しました。
Reviewed: BASE..HEAD

total.sh に --kg を追加しました。'

proactive_run "$work_records" "$closing_ok" fix_kg
grade "$proactive_closing"
expect_pass "proactive: a good run passes every assertion"

proactive_run "$work_records" "$closing_ok" fix_kg 0
grade "$proactive_closing"
expect_fail "proactive: a run that never starts the skill is caught" \
  "started review-design without being asked"

proactive_run "$work_records" "$closing_ok" fix_kg 5
grade "$proactive_closing"
expect_fail "proactive: a review loop past its cap is caught" \
  "kept the review loop within its cap of four"

# A review in the middle of the unit, before its commit.
proactive_run 'rec_skill; rec_edit Edit total.sh; rec_bash "git commit -m feat"' "$closing_ok" fix_kg 0
grade "$proactive_closing"
expect_fail "proactive: a review started before the commit is caught" \
  "started it at the breakpoint: after the work was committed"

# Three lines leave room for a sentence of preamble; the fourth is too late.
proactive_run "$work_records" '作業が終わりました。
設計レビューの結果です。
## 設計レビュー: BASE..HEAD
Reviewed: BASE..HEAD' fix_kg
grade "$proactive_closing"
expect_pass "proactive: a heading on the third line still opens the message"

proactive_run "$work_records" '総括です。
--kg を追加しました。
テストも書きました。
## 設計レビュー: BASE..HEAD
Reviewed: BASE..HEAD' fix_kg
grade "$proactive_closing"
expect_fail "proactive: a report buried below the summary is caught" \
  "opens the closing message with the review report"

proactive_run "$work_records" "${closing_ok//..HEAD/..BASE}" fix_kg
grade "$proactive_closing"
expect_fail "proactive: a range that ends where it starts is caught" \
  "names the range it reviewed, from eval-base to a commit on the branch"

proactive_run "$work_records" "${closing_ok//BASE../HEAD..}" fix_kg
grade "$proactive_closing"
expect_fail "proactive: a range that does not start at the merge-base is caught" \
  "names the range it reviewed, from eval-base to a commit on the branch"

# A head off the branch: a commit on main made after the branch was cut.
proactive_run "$work_records" "$closing_ok" \
  'fix_kg; git checkout -q main; git commit -q --allow-empty -m later; git tag off-branch; git checkout -q -'
proactive_closing="${proactive_closing//$(short HEAD)/$(short off-branch)}"
grade "$proactive_closing"
expect_fail "proactive: a range ending off the branch is caught" \
  "names the range it reviewed, from eval-base to a commit on the branch"

proactive_run "$work_records" "$closing_ok" :
grade "$proactive_closing"
expect_fail "proactive: a run that never built --kg is caught" \
  "total.sh --kg prints the total in kilograms"
expect_fail "proactive: ... and so is the missing commit" "committed the work"

proactive_run "$work_records" "$closing_ok" 'fix_kg; add_a_failing_test'
grade "$proactive_closing"
expect_fail "proactive: a failing suite is caught" "the tests pass"

proactive_run "$work_records" "$closing_ok" "fix_kg; printf 'x\n' >stray.txt"
grade "$proactive_closing"
expect_fail "proactive: something left uncommitted is caught" "left nothing uncommitted"

if [ "$fails" -eq 0 ]; then
  printf '\nall review-design grader tests passed\n'
  exit 0
fi
printf '\n%d review-design grader test(s) failed\n' "$fails"
exit 1
