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
# loads into the conversation, report template included. The shape is the one
# a real forked run emitted (see rec_skill): the body and the fork's own git
# reads arrive inside the fork, and the report first arrives as the Skill's
# tool_result, which the caller must still write out to count as reported.
#
# check_llm is graded by a stub judge that fails exactly when the text it was
# handed contains JUDGE_FAIL. That pins the wiring -- each judged check reads
# the text it claims to read -- not the rubric, which only a real run can
# exercise.
#
# Written for bash 3.2 (macOS) and run on Linux in CI.
set -uo pipefail

self="$(readlink -f "$0")"
cd "$(dirname "$self")" || exit 1
evals_dir="$PWD"
repo_root="$(cd "$evals_dir/../../../../.." && pwd)"

fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

# --- shards ---
# Every scenario below copies its fixture and runs a real grader, ~0.6 s each
# on macOS, nearly all of it the grader's own processes -- and none of them
# shares state with another. So the file runs itself as TEST_JOBS
# shards (one per CPU by default) -- named for no suite, like TEST_FILTER in
# bin/testing.md, because this harness is meant to move to bin/test-lib.sh and a
# runner capping total parallelism should need one name, not one per suite.
# Each shard walks every scenario but runs only
# those whose index falls to it. Each scenario's output follows a marker line
# carrying its index, which is how the blocks are put back in source order:
# the result reads as a sequential run would, bar the merge's self-check lines
# at the top and the summary. TEST_SHARD is the driver's handshake with each
# shard, never set by hand: a shard run alone checks only its own subset.
#
# A shard that died part-way would otherwise be a shorter green run, so the
# merge fails CLOSED: green needs the token awk prints only when every shard
# finished and every scenario 1..n left a block holding a check. An awk that
# errors, or prints nothing, therefore cannot pass.
#
# Shards run on "$BASH", the interpreter running this file: through PATH they
# would get Homebrew's bash 5, and nothing would exercise "written for bash 3.2".
#
# The protocol on a shard's stdout: \036<n> opens scenario <n>, \037<n> ends
# the shard carrying how many it walked. Only the shard_* functions below read
# or write it.

# shard_begin -- where a scenario begins. Returns 1 when it belongs to another
# shard, and sets skipping=1 until the next scenario: every helper that runs
# between scenarios (here grade, expect_* and short) must then do nothing.
shard_begin() {
  scenario=$((scenario + 1))
  if [ $(((scenario - 1) % TEST_JOBS)) -ne "$TEST_SHARD" ]; then
    skipping=1
    return 1
  fi
  skipping=0
  printf '\036%d\n' "$scenario"
}

# shard_end -- a shard's last line.
shard_end() { printf '\037%d\n' "$scenario"; }

# shard_merge <jobs> <shard output file>... -- the scenarios' blocks in source
# order; 0 only when all <jobs> shards finished and every scenario 1..n left a
# block holding a check. awk proves that with a token (\035) it prints only
# then, so an awk that errors or prints nothing fails rather than passes. A
# line before a shard's first marker is its setup, kept at the top (idx resets
# per file, or it would join the previous shard's last scenario).
shard_merge() {
  local jobs="$1" merged complete=$'\035complete'
  shift
  if ! merged="$(awk -v jobs="$jobs" '
    FNR == 1 { idx = 0 }
    /^\036/ { idx = substr($0, 2) + 0; seen[idx] = 1; if (idx > top) top = idx; next }
    /^\037/ { n = substr($0, 2) + 0; if (total == "") total = n; else if (n != total) bad = 1; shards++; next }
    { blk[idx] = blk[idx] $0 "\n"; if ($0 ~ /^(ok|FAIL) /) checked[idx] = 1 }
    END {
      # Up to the highest block seen, not the count: with no shard finished
      # there is no count, and the blocks are then the only explanation.
      for (i = 0; i <= top; i++) printf "%s", blk[i]
      for (i = 1; i <= total; i++) if (!(i in seen) || !(i in checked)) missing++
      if (shards == jobs && !bad && total > 0 && !missing) print "\035complete"
      else printf "FAIL shards: %d of %d finished, %d scenario(s), %d missing or without a check\n", shards, jobs, total, missing
    }' "$@")"; then
    printf 'FAIL the shard merge itself failed\n'
    return 1
  fi
  case "$merged" in
    *"$complete")
      printf '%s' "${merged%"$complete"}"
      return 0
      ;;
  esac
  printf '%s\n' "$merged"
  return 1
}

# shard_check_merge -- shard_merge against made-up shard output, before every
# run. Its fail-closed verdicts are what stop a broken run from passing, and a
# real run only ever exercises the green one, so each way of losing a scenario
# is provoked here: a few awk calls, where a mutant of the whole suite costs
# half a minute and runs only when someone remembers to.
#
# The markers are held in variables and passed as %s arguments, so a fixture
# line reads as marker then text; under %b or echo -e, '\0361' would be a
# single octal escape rather than \036 followed by 1.
#
# Four scenarios over two shards, so shard 1 owns the last one. Each failing
# row breaks exactly one condition and leaves the others true -- the shard
# count, the scenario count, a scenario's presence, its check, the counts
# agreeing -- or its row would pass on whichever other condition it also broke.
# Each must fail with the merge's own verdict line, not merely a non-zero
# status, which an awk that cannot run also returns.
shard_check_merge() {
  local d out o=$'\036' e=$'\037' label a b
  d="$(mktemp -d)"
  # Setup lines, and blocks of more than one line: both must come back whole.
  printf '%s\n' 'setup 0' "${o}1" 'ok   a' '     got: a' "${o}3" 'ok   c' "${e}4" >"$d/0"
  printf '%s\n' 'setup 1' "${o}2" 'ok   b' '     got: b' "${o}4" 'ok   d' "${e}4" >"$d/1"
  printf '%s\n' "${o}2" 'ok   b' "${o}4" 'ok   d' >"$d/unfinished"
  printf '%s\n' "${e}0" >"$d/empty"
  printf '%s\n' "${o}2" 'ok   b' "${e}4" >"$d/lost-last"
  # A detail line that mentions FAIL is not a check: only a line that starts
  # with one is.
  printf '%s\n' "${o}2" 'ok   b' "${o}4" '       got: FAIL  x' "${e}4" >"$d/unchecked"
  printf '%s\n' "${o}2" 'ok   b' "${o}4" 'ok   d' "${e}3" >"$d/disagrees"
  if out="$(shard_merge 2 "$d/0" "$d/1")" && [ "$out" = "setup 0
setup 1
ok   a
     got: a
ok   b
     got: b
ok   c
ok   d" ]; then
    ok "shard merge: two shards come back whole, in source order"
  else
    bad "shard merge: two shards come back whole, in source order"
  fi
  while IFS='|' read -r label a b; do
    if out="$(shard_merge 2 "$d/$a" "$d/$b")"; then
      bad "shard merge: $label fails"
    elif grep -q '^FAIL shards:' <<<"$out"; then
      ok "shard merge: $label fails"
    else
      bad "shard merge: $label fails, but not on its verdict: $out"
    fi
  done <<'EOF'
a shard that ran every scenario but never finished|0|unfinished
a run of no scenarios at all|empty|empty
the last scenario never run|0|lost-last
a scenario with no check|0|unchecked
shards disagreeing on the count|0|disagrees
EOF
  # When every shard died -- an unbound variable kills them all alike -- what
  # they printed is the only explanation there is, so it must not be dropped
  # with the verdict.
  printf '%s\n' "${o}1" 'ok   a' 'shard 0 died here' >"$d/died"
  out="$(shard_merge 2 "$d/died" "$d/unfinished")"
  case "$out" in
    *'shard 0 died here'*'ok   d'*) ok "shard merge: a run where no shard finished still shows their output" ;;
    *) bad "shard merge: a run where no shard finished still shows their output" ;;
  esac
  rm -rf "$d"
}

# shard_drive <script> <suite name> -- run <script> as its shards, print the
# merge and a summary naming the suite, and exit with the verdict.
shard_drive() {
  local script="$1" name="$2" jobs shard_dir k p merged checks finished=1 shard_failed=0 pids=()
  checks="$(shard_check_merge)"
  jobs="${TEST_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
  case "$jobs" in '' | *[!0-9]* | 0) jobs=1 ;; esac
  shard_dir="$(mktemp -d)"
  trap 'rm -rf "$shard_dir"' EXIT
  k=0
  while [ "$k" -lt "$jobs" ]; do
    TEST_SHARD="$k" TEST_JOBS="$jobs" \
      "$BASH" "$script" >"$shard_dir/$k" 2>&1 &
    pids+=("$!")
    k=$((k + 1))
  done
  for p in "${pids[@]}"; do wait "$p" || shard_failed=1; done
  merged="$(shard_merge "$jobs" "$shard_dir"/*)" || finished=0
  if [ "$shard_failed" -ne 0 ] && ! grep -q '^FAIL' <<<"$merged"; then
    merged="$merged
FAIL a shard exited non-zero without reporting a failure"
  fi
  # Joined only now: a FAIL among the checks must not stand in for the notice
  # above, which is about the shards.
  merged="$checks
$merged"
  printf '%s\n' "$merged"
  if [ "$finished" -eq 1 ] && [ "$shard_failed" -eq 0 ] && ! grep -q '^FAIL' <<<"$merged"; then
    printf '\nall %s tests passed (%s shard(s))\n' "$name" "$jobs"
    exit 0
  fi
  printf '\n%d %s test(s) failed\n' "$(grep -c '^FAIL' <<<"$merged")" "$name"
  exit 1
}

# The harness's own state, set before the first scenario: under set -u a
# shard_begin without it would kill every shard alike.
scenario=0
skipping=0
[ -n "${TEST_SHARD:-}" ] || shard_drive "$self" "review-design grader"

# Read at top level after proactive_run; a skipped run never assigns it, and
# this file runs under set -u.
proactive_closing=''

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
# rec_skill
# A forked run as stream-json records it (measured on real runs): the Skill
# call; the skill's body as a user text record inside the fork; the fork's own
# tool calls -- read-only git, by default -- tagged with the Skill call's id as
# parent_tool_use_id; and the report coming back as the Skill's tool_result.
# None of it is the caller's words, so none of it counts as having reported.
# What happens inside the fork is the skill's own doing, though, and its
# boundary holds there too.
# The fork emitted no text record of its own in any measured run, which is all
# that keeps a heading inside the fork from counting as the caller's: the
# heading check reads every assistant text, tagged or not. Tool calls inside
# the fork are counted on purpose; text must not be.
# Set for one call:
#   skill_inside  records the fork makes, in rec_* calls (default: one git diff)
#   skill_result  what the Skill hands back (default: a placeholder)
skill_seq=0
rec_skill() {
  local id
  skill_seq=$((skill_seq + 1))
  id="toolu_skill_$skill_seq"
  jq -nc --arg id "$id" \
    '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "Skill", input: {skill: "review-design", args: "brief"}}]}}'
  jq -nc --arg id "$id" --rawfile body "$repo_root/root/.agents/skills/review-design/SKILL.md" \
    '{type: "user", parent_tool_use_id: $id, message: {content: [{type: "text", text: ("Base directory for this skill: .claude/skills/review-design\n\n" + $body)}]}}'
  eval "${skill_inside:-rec_bash \"git diff main..HEAD\"}" | jq -c --arg id "$id" '. + {parent_tool_use_id: $id}'
  jq -nc --arg id "$id" --arg r "${skill_result:-(the review)}" \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: ("Skill \"review-design\" completed (forked execution).\n\nResult:\n" + $r)}]}}'
}

# --- running one scenario ---
# new_run <case>: the fixture its scaffold builds, an empty transcript.
#
# Each case is scaffolded once and copied per scenario: a scaffold is a git
# init and a few commits (~120 ms on macOS), a copy ~20 ms, and some 165
# scenarios run here. Every scenario still mutates only its own copy. The
# copies share commit hashes, which nothing here compares across scenarios.
#
# It is also where a scenario begins (see "shards" above): one that belongs to
# another shard returns 1 like a failed scaffold, which stops the *_run caller.
new_run() {
  shard_begin || return 1
  case_name="$1"
  work="$root_dir/work"
  art="$root_dir/art"
  local built="$root_dir/fixtures/$case_name"
  rm -rf "$work" "$art"
  mkdir -p "$art"
  if [ ! -d "$built" ]; then
    mkdir -p "$built"
    (
      cd "$built" || exit 1
      SKILL_EVAL_LIB_DIR="$repo_root/bin" SKILL_EVAL_REPO_ROOT="$repo_root" \
        bash "$evals_dir/$case_name/scaffold.sh" </dev/null
      printf '.claude/\nbin/\n' >>.git/info/exclude
    ) >/dev/null 2>&1 || {
      rm -rf "$built"
      return 1
    }
  fi
  cp -R "$built" "$work" || return 1
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

# Empty for a skipped scenario: there is no fixture, and a few top-level lines
# still compute a hash for the grade that follows.
short() {
  [ "$skipping" -eq 1 ] && return 0
  git -C "$work" rev-parse --short "$1"
}

# grade <final response>
grade() {
  [ "$skipping" -eq 1 ] && return 0
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
  [ "$skipping" -eq 1 ] && return 0
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
  [ "$skipping" -eq 1 ] && return 0
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

  # Forked, the report first arrives as the Skill's result, which the user does
  # not necessarily see. A real run of stale-doc-after-change left it there and
  # went straight on to its fixes; that is not having reported.
  # The hashes are left as BASE..HEAD: the heading is what is under test.
  skill_result="$good_report" design_run "$c" none "$before_default" "$after_default" "$fix"
  grade "直してコミットしました。"
  expect_fail "$c: a report left in the Skill's result is not a report" \
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

# Reading git before the report is allowed -- the skill reads its range inside
# the fork, and the caller may look too -- including the near misses the regex
# is written to tell apart.
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

# The same boundary inside the fork, where the skill itself acts. A helper that
# skipped records tagged with parent_tool_use_id would stop watching the very
# skill these checks exist for, and every control above would stay green.
skill_inside='rec_bash "git diff main..HEAD"; rec_bash "git commit -am x"' \
  design_run clean-unit-no-false-p1 "$good_report" "$before_default" "$after_default" :
grade "問題ありませんでした。"
expect_fail "grading.sh: writing git inside the fork is caught" \
  "ran no git that writes before the review was reported"

skill_inside='rec_edit Edit README.md' \
  design_run clean-unit-no-false-p1 "$good_report" "$before_default" "$after_default" :
grade "問題ありませんでした。"
expect_fail "grading.sh: an Edit inside the fork is caught" \
  "wrote nothing before the review was reported"

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

# A shard's ending: shard_drive prints the summary.
shard_end
[ "$fails" -eq 0 ]
