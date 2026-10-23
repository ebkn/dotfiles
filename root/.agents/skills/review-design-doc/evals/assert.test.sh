#!/bin/bash
#
# assert.test.sh — pins the graders of every review-design-doc eval case,
# without calling the API.
#
# A grader is an instrument, and an inert one reports a paid, non-deterministic
# eval run that measured nothing. So for each case this builds the fixture its
# scaffold.sh builds, hands the grader a synthetic transcript of a good run and
# checks that it passes, then breaks one thing at a time and checks that the
# matching assertion FAILs and the grader exits non-zero.
#
# check_llm is graded by a stub judge that fails exactly when the text it was
# handed contains JUDGE_FAIL. That pins the wiring -- each judged check reads
# the text it claims to (P1 and P2 only, or the whole report) -- not whether
# its rubric is right, which only real runs can tell.
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
# Scenarios name them inside strings that new_run evals, which shellcheck
# cannot follow.
rec_init() { printf '{"type":"system","subtype":"init"}\n'; }
# shellcheck disable=SC2329
rec_tool() { jq -nc --arg n "$1" --argjson i "$2" '{type: "assistant", message: {content: [{type: "tool_use", name: $n, input: $i}]}}'; }
# shellcheck disable=SC2329
rec_edit() { rec_tool "$1" "$(jq -nc --arg p "$2" '{file_path: $p}')"; }
# shellcheck disable=SC2329
rec_skill() { rec_tool Skill "$(jq -nc --arg s "${1:-review-design-doc}" '{skill: $s}')"; }
# lint-docs started, as every Japanese case expects after the review.
lint='rec_skill lint-docs'
# rec_round <report>
# One round of the forked review: the Skill call, with an id, and the report
# coming back as its tool_result -- what the loop checks and the per-round
# language check read. rec_skill alone has no result, which is enough where
# only the start is graded.
round_seq=0
# shellcheck disable=SC2329
rec_round() {
  local id
  round_seq=$((round_seq + 1))
  id="toolu_round_$round_seq"
  jq -nc --arg id "$id" \
    '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "Skill", input: {skill: "review-design-doc", args: "brief"}}]}}'
  jq -nc --arg id "$id" --arg r "$1" \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: ("Skill \"review-design-doc\" completed (forked execution).\n\nResult:\n" + $r)}]}}'
}

# new_run <case> <records> [<tree change>]
# The fixture the case's scaffold builds, the records as its transcript, and
# the tree changed the way the run under test did.
new_run() {
  case_name="$1"
  work="$root_dir/work"
  art="$root_dir/art"
  rm -rf "$work" "$art"
  mkdir -p "$work" "$art"
  if ! (
    cd "$work" || exit 1
    SKILL_EVAL_LIB_DIR="$repo_root/bin" SKILL_EVAL_REPO_ROOT="$repo_root" \
      bash "$evals_dir/$case_name/scaffold.sh"
    printf '.claude/\nbin/\n' >>.git/info/exclude
  ) >/dev/null 2>&1; then
    bad "$case_name: scaffold.sh failed"
    return 1
  fi
  {
    rec_init
    eval "$2"
  } >"$art/transcript.jsonl"
  if [ -n "${3:-}" ]; then
    (cd "$work" && eval "$3") >/dev/null 2>&1
  fi
}

# grade <final response> [<denials>]
grade() {
  jq -nc --arg r "$1" --argjson d "${2:-0}" \
    '{type: "result", result: $r, permission_denials: [range($d) | {tool_name: "Bash"}]}' >"$art/result.json"
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

# expect_fail <label> <assertion> [<assertion> ...]
# Exactly these assertions FAIL: each one listed, and no other. A mutation
# that also tripped an unrelated check would otherwise hide a check that is
# fragile, or one that reads something it should not.
expect_fail() {
  local label="$1" want line matched missing=0 stray=0
  shift
  for want in "$@"; do
    grep -qF "FAIL  $want" <<<"$out" || missing=1
  done
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    matched=0
    for want in "$@"; do
      case "$line" in "FAIL  $want"*) matched=1 ;; esac
    done
    [ "$matched" -eq 1 ] || stray=1
  done <<<"$(grep '^FAIL' <<<"$out")"
  if [ "$missing" -eq 0 ] && [ "$stray" -eq 0 ]; then
    ok "$label"
  else
    bad "$label (expected FAIL: $*)"
    grep '^FAIL' <<<"$out" | sed 's/^/       got: /'
  fi
  if [ "$status" -eq 0 ]; then
    bad "$label — the grader exited 0"
  fi
}

# report <path> <P1 body> [<P2 body>] [<P3 body>]
# A report in the contract's shape. An empty body drops its section, as the
# skill does.
report() {
  printf '## 設計ドキュメントレビュー: %s\n\n方針は妥当。以下を直すと判断しやすくなる。\n' "$1"
  [ -z "${2:-}" ] || printf '\n### P1\n- %s\n' "$2"
  [ -z "${3:-}" ] || printf '\n### P2\n- %s\n' "$3"
  [ -z "${4:-}" ] || printf '\n### P3\n- %s\n' "$4"
}

# en_report <path>
# The same review in English, quoting the Japanese doc in 「」 and in code, as
# an English review of it would: kana are present, the review is not Japanese.
en_report() {
  # The backticks are Markdown code, not a command.
  # shellcheck disable=SC2016
  printf '## Design doc review: %s\n\nThe approach is sound, but the section 「検討した代替案」 needs work.\n\n### P1\n- The `何もしない` option is dismissed without its cost.\n' "$1"
}

doc=docs/design/webhook-retry.md

# ============================================================
# The fixture library
# ============================================================
# A typo in a variant name must not quietly write the clean doc under a
# defect case's name.
if (
  cd "$root_dir" || exit 1
  # shellcheck source=./lib.sh
  . "$evals_dir/lib.sh"
  ! rdd_write_doc ja x.md alternatives=nosuch 2>/dev/null &&
    ! rdd_write_doc ja x.md nosection=base 2>/dev/null
); then
  ok "lib: an unknown section or variant is refused"
else
  bad "lib: an unknown section or variant is refused"
fi

# Each defect scaffold must differ from the clean doc, or the override did
# nothing and the case grades a finding the doc does not have.
new_run clean-doc-no-false-p1 "$lint" && cp "$work/$doc" "$root_dir/clean.md"
new_run clean-doc-no-false-p1-en '' && cp "$work/$doc" "$root_dir/clean-en.md"
for c in strawman-alternatives negated-non-goals missing-rollback unsupported-claims \
  hidden-uncertainty dependency-unconfirmed implementation-manual missing-rollback-en; do
  new_run "$c" "$lint" || continue
  clean="$root_dir/clean.md"
  case "$c" in *-en) clean="$root_dir/clean-en.md" ;; esac
  if cmp -s "$work/$doc" "$clean"; then
    bad "$c: the doc is the clean one"
  else
    ok "$c: the doc differs from the clean one"
  fi
done

# ============================================================
# The judged defect cases, started by name
# ============================================================
for entry in \
  'strawman-alternatives|P1/P2: the alternatives are straw men' \
  'negated-non-goals|P1/P2: the non-goals only negate goals' \
  'missing-rollback|P1/P2: no staged rollout and no rollback' \
  'unsupported-claims|P1/P2: the problem and the cost are claimed without numbers' \
  'hidden-uncertainty|P1/P2: open decisions are buried while the doc claims none' \
  'implementation-manual|P1/P2: the doc records no decision'; do
  c="${entry%%|*}"
  judged="${entry#*|}"

  new_run "$c" "$lint"
  grade "$(report "$doc" '見つけた問題' '' '細かい言い回し')"
  expect_pass "$c: a good run passes every assertion"

  # Found under P2 is found: the priority is the skill's call.
  new_run "$c" "$lint"
  grade "$(report "$doc" '' '見つけた問題')"
  expect_pass "$c: a finding under P2 counts"

  new_run "$c" "$lint"
  grade "$(report "$doc" '' '' '見つけた問題')"
  expect_fail "$c: a finding under P3 only is caught" "$judged"

  new_run "$c" "$lint"
  grade "$(report "$doc" 'なし' '' '見つけた問題')"
  expect_fail "$c: a P1 section saying none is not a finding" "$judged"

  new_run "$c" "$lint"
  grade "$(report "$doc" '' 'None.' '見つけた問題')"
  expect_fail "$c: a P2 section saying none is not a finding" "$judged"

  new_run "$c" "$lint"
  grade "$(report "$doc" 'JUDGE_FAIL')"
  expect_fail "$c: the judge reads the P1 section" "$judged"

  new_run "$c" "$lint"
  grade "$(report "$doc" '' 'JUDGE_FAIL')"
  expect_fail "$c: the judge reads the P2 section" "$judged"

  # A P3 item is not shown to the judge.
  new_run "$c" "$lint"
  grade "$(report "$doc" '見つけた問題' '' 'JUDGE_FAIL')"
  expect_pass "$c: the judge does not read P3"

  new_run "$c" "$lint"
  grade "$(report "$doc" '見つけた問題' | sed '1s/^.*$/設計ドキュメントをレビューしました。/')"
  expect_fail "$c: a report without the heading is caught" \
    "reported under the review heading, naming the doc"

  new_run "$c" "$lint"
  grade "$(report docs/design/other.md '見つけた問題')"
  expect_fail "$c: a heading naming another doc is caught" \
    "reported under the review heading, naming the doc"

  new_run "$c" "$lint; rec_edit Edit $doc"
  grade "$(report "$doc" '見つけた問題')"
  expect_fail "$c: an Edit is caught" "used neither Edit nor Write"

  new_run "$c" "$lint" "printf 'x\n' >>$doc"
  grade "$(report "$doc" '見つけた問題')"
  expect_fail "$c: a changed tree is caught" "left the tree as it was"

  new_run "$c" "$lint" 'git commit -q --allow-empty -m x'
  grade "$(report "$doc" '見つけた問題')"
  expect_fail "$c: a commit is caught" "committed nothing"

  new_run "$c" "$lint"
  grade "$(report "$doc" '見つけた問題')" 1
  expect_fail "$c: a refused command is caught" "no command was refused"

  # Quoting the doc is not answering in its language.
  new_run "$c" "$lint"
  grade "$(en_report "$doc")"
  expect_fail "$c: an English report on a Japanese doc is caught" \
    "answered in Japanese, the doc's language"

  new_run "$c" ''
  grade "$(report "$doc" '見つけた問題')"
  expect_fail "$c: leaving lint-docs out is caught" \
    "handed Japanese readability to lint-docs, after the review"
done

# The heading's other spellings. The backticks are literal, not a command.
# shellcheck disable=SC2016
for heading in '**Design doc review:** docs/design/webhook-retry.md' \
  '# 設計書レビュー：docs/design/webhook-retry.md' \
  '## Design Document Review: `docs/design/webhook-retry.md`'; do
  new_run strawman-alternatives "$lint"
  grade "$(report "$doc" '見つけた問題' | sed "1s|^.*\$|$heading|")"
  expect_pass "heading: $heading"
done

# ============================================================
# dependency-unconfirmed: judged on the whole report
# ============================================================
new_run dependency-unconfirmed "$lint"
grade "$(report "$doc" '' '' '細かい言い回し')
### 著者への質問
- 基盤チームは増強に合意していますか"
expect_pass "dependency: a question outside P1/P2 passes"

new_run dependency-unconfirmed "$lint"
grade "$(report "$doc" '' '' '細かい言い回し')
### 著者への質問
- JUDGE_FAIL"
expect_fail "dependency: the judge reads the whole report" \
  "raises whether the platform team agreed to enlarge the database"

new_run dependency-unconfirmed "$lint; rec_edit Write $doc"
grade "$(report "$doc" '基盤チームの合意が書かれていない')"
expect_fail "dependency: a Write is caught" "used neither Edit nor Write"

# ============================================================
# clean-doc-no-false-p1 (and -en)
# ============================================================
new_run clean-doc-no-false-p1 "$lint"
grade "$(report "$doc" '' '補足があるとよい' '言い回し')"
expect_pass "clean: a P2 and a P3 pass"

new_run clean-doc-no-false-p1 "$lint"
grade "$(report "$doc" 'なし')"
expect_pass "clean: a kept P1 heading saying none passes"

new_run clean-doc-no-false-p1 "$lint"
grade "$(report "$doc" '誤検知')"
expect_fail "clean: a P1 is caught" "raised no P1"

new_run clean-doc-no-false-p1 "$lint"
grade "$(printf '## 設計ドキュメントレビュー: %s\n\n### P1\n1. 誤検知\n' "$doc")"
expect_fail "clean: a numbered P1 is caught" "raised no P1"

# Shapes a real P1 can take. "raised no P1" fails open if the parser misses
# one, so each must be counted.
for shape in '### 🔴 P1\n- 誤検知' '### 重大 (P1)\n- 誤検知' '### **P1**\n- 誤検知' \
  '**P1**\n- 誤検知' '**P1:**\n- 誤検知' '### P1\nロールバック手順が書かれていない。' \
  '### P1\n- なし。ただし、ロールバック手順が無い' '### P1\n- None of the non-goals are real.'; do
  new_run clean-doc-no-false-p1 "$lint"
  grade "$(printf "## 設計ドキュメントレビュー: %s\n\n$shape\n" "$doc")"
  expect_fail "clean: a P1 shaped '${shape%%\\n*} / ${shape#*\\n}' is caught" "raised no P1"
done

# And shapes that are not a P1.
for shape in '### P1\nなし' '### P1\n- None.' '### P12\n- 番号違い' '### P2\n- これは P1 ではない' \
  '**P1 のつもりの太字** を含む文\n- 本文'; do
  new_run clean-doc-no-false-p1 "$lint"
  grade "$(printf "## 設計ドキュメントレビュー: %s\n\n$shape\n" "$doc")"
  expect_pass "clean: not a P1: '${shape%%\\n*} / ${shape#*\\n}'"
done

# A finding ranked inline is one rdd_section cannot see, so the report fails
# the contract instead of grading as clean.
for shape in '### Findings\n- **P1**: ロールバックが無い' '### Findings\n- [P1] ロールバックが無い' \
  '### 指摘\n1. P1 ロールバックが無い' '| 優先度 | 指摘 |\n|---|---|\n| P1 | ロールバックが無い |'; do
  new_run clean-doc-no-false-p1 "$lint"
  grade "$(printf "## 設計ドキュメントレビュー: %s\n\n$shape\n" "$doc")"
  expect_fail "clean: a finding ranked inline is caught: '${shape%%\\n*} / ${shape#*\\n}'" \
    "ranks findings under priority headings, not inline"
done

# Prose that mentions a priority is not a ranking.
new_run clean-doc-no-false-p1 "$lint"
grade "$(report "$doc" '' '補足があるとよい')

P1 に当たる問題はありません。"
expect_pass "clean: prose mentioning P1 passes"

new_run clean-doc-no-false-p1 "$lint; rec_edit Edit $doc"
grade "$(report "$doc")"
expect_fail "clean: an Edit is caught" "used neither Edit nor Write"

clean_en="## Design doc review: $doc

The approach is sound.

### P2
- The dashboard could say who acts on a dead letter."

new_run clean-doc-no-false-p1-en ''
grade "$clean_en"
expect_pass "clean-en: a good run passes every assertion"

new_run clean-doc-no-false-p1-en ''
grade "$clean_en
- 冪等キーの説明"
expect_fail "clean-en: Japanese in the report is caught" "wrote no Japanese into an English review"

new_run clean-doc-no-false-p1-en ''
grade "$clean_en

### P1
- a false alarm"
expect_fail "clean-en: a P1 is caught" "raised no P1"

# lint-docs' rules are for Japanese; on an English doc they are noise.
new_run clean-doc-no-false-p1-en "$lint"
grade "$clean_en"
expect_fail "clean-en: lint-docs on an English doc is caught" "left lint-docs out of an English doc"

# ============================================================
# missing-rollback-en: by phrase, in English
# ============================================================
mr_en="## Design doc review: $doc

### P1
- No rollback."

new_run missing-rollback-en 'rec_skill'
grade "$mr_en"
expect_pass "rollback-en: a good run passes every assertion"

new_run missing-rollback-en ''
grade "$mr_en"
expect_fail "rollback-en: not starting the skill is caught" \
  "started review-design-doc without being named"

new_run missing-rollback-en 'rec_skill review-design'
grade "$mr_en"
expect_fail "rollback-en: another skill does not count" \
  "started review-design-doc without being named"

new_run missing-rollback-en 'rec_skill'
grade "$mr_en (ロールバック)"
expect_fail "rollback-en: Japanese in the report is caught" \
  "wrote no Japanese into an English review"

new_run missing-rollback-en 'rec_skill'
grade "${mr_en/No rollback./JUDGE_FAIL}"
expect_fail "rollback-en: the judge reads P1" "P1/P2: no staged rollout and no rollback"

new_run missing-rollback-en "rec_skill; $lint"
grade "$mr_en"
expect_fail "rollback-en: lint-docs on an English doc is caught" "left lint-docs out of an English doc"

# ============================================================
# answers-in-doc-language: an English request, a Japanese doc
# ============================================================
new_run answers-in-doc-language "rec_skill; $lint"
grade "$(report "$doc" 'ロールバックの手段が無い')"
expect_pass "doc-language: a Japanese report passes every assertion"

new_run answers-in-doc-language "rec_skill; $lint"
grade "$(en_report "$doc")"
expect_fail "doc-language: answering in the request's language is caught" \
  "answered in Japanese, the doc's language"

new_run answers-in-doc-language "$lint"
grade "$(report "$doc" 'ロールバックの手段が無い')"
expect_fail "doc-language: not starting the skill is caught" \
  "started review-design-doc without being named"

# Started by phrase, the review has a Skill call to order lint-docs against.
new_run answers-in-doc-language "$lint; rec_skill"
grade "$(report "$doc" 'ロールバックの手段が無い')"
expect_fail "doc-language: lint-docs before the review is caught" \
  "handed Japanese readability to lint-docs, after the review"

new_run answers-in-doc-language "rec_skill; $lint"
grade "$(report "$doc" 'JUDGE_FAIL')"
expect_fail "doc-language: the judge reads P1" "P1/P2: no staged rollout and no rollback"

# The language rule itself, on the shapes a report takes. The backticks in
# these are Markdown code, not commands.
# shellcheck disable=SC2016
for text in '## 設計ドキュメントレビュー: docs/design/webhook-retry.md\n\n### P1\n- `crosscutting` の節に切り戻しが無い。Webhook の再送を全顧客へ一度に出している' \
  'ロールバック手順が無い (see docs/design/webhook-retry.md:42, P1)'; do
  if (. "$evals_dir/grading.sh" && rdd_is_japanese "$(printf %b "$text")"); then
    ok "is_japanese: '${text%%\\n*}' is Japanese"
  else
    bad "is_japanese: '${text%%\\n*}' is Japanese"
  fi
done
# shellcheck disable=SC2016
for text in 'The 「検討した代替案」 section and `何もしない` are thin.' \
  '> 何もしない: 請求イベントで会計がずれる\n\nThis rejection gives no cost.' \
  'The doc says "全顧客に一度に出す" with no rollback.' ''; do
  if (. "$evals_dir/grading.sh" && rdd_is_japanese "$(printf %b "$text")"); then
    bad "is_japanese: '${text%%\\n*}' is not Japanese"
  else
    ok "is_japanese: '${text%%\\n*}' is not Japanese"
  fi
done

# ============================================================
# mini-doc-no-template-demands
# ============================================================
mini=docs/design/cache-ttl.md

new_run mini-doc-no-template-demands "$lint"
grade "$(report "$mini" '' '' '言い回し')"
expect_pass "mini: nothing under P1 or P2 passes without a judge"

new_run mini-doc-no-template-demands "$lint"
grade "$(report "$mini" '' 'パージ失敗の検知方法')"
expect_pass "mini: a P2 about the change passes"

new_run mini-doc-no-template-demands "$lint"
grade "$(report "$mini" '' 'JUDGE_FAIL')"
expect_fail "mini: the judge reads P2" "asked for no section the change does not need"

new_run mini-doc-no-template-demands "$lint"
grade "$(report "$mini" 'セキュリティの節がない')"
expect_fail "mini: a P1 is caught" "raised no P1"

new_run mini-doc-no-template-demands "$lint"
grade "$(report "$doc" '' '' '言い回し')"
expect_fail "mini: a heading naming the webhook doc is caught" \
  "reported under the review heading, naming the doc"

# ============================================================
# fires-on-phrase
# ============================================================
new_run fires-on-phrase "rec_skill; $lint"
grade "$(report "$doc" '代替案が藁人形')"
expect_pass "fires: a good run passes every assertion"

new_run fires-on-phrase "$lint"
grade "$(report "$doc" '代替案が藁人形')"
expect_fail "fires: reviewing without the skill is caught" \
  "started review-design-doc without being named"

new_run fires-on-phrase "rec_skill; $lint; rec_edit Edit $doc" "printf 'x\n' >>$doc"
grade "$(report "$doc" '代替案が藁人形')"
expect_fail "fires: rewriting the doc unasked is caught" \
  "used neither Edit nor Write" "left the tree as it was"

# ============================================================
# proactive-after-writing-doc (and proactive-with-claude-md, which runs it)
# ============================================================
# A good run: write the doc, a round that finds the missing release plan, a
# fix, a clean round, then lint-docs; the doc names the release plan as open.
write_doc="mkdir -p docs/design; printf '# Webhook 配信の自動リトライ\n\n再送する。\n\n## 未解決の問題\n\n- リリースと切り戻しの方法は未決\n' >$doc"
# The round reports are read by name inside records new_run evals.
# shellcheck disable=SC2034
found="$(report "$doc" '' 'リリースと切り戻しの方法が書かれていない')"
clean="$(report "$doc" '' '' '言い回し')"
# shellcheck disable=SC2034
clean_en_round="## Design doc review: $doc

The approach is sound, and nothing is left to raise."
pro_done='書き上げました。レビューの P2（リリースと切り戻しが無い）は未解決の問題として書き、2 回目のレビューで P1・P2 はなくなりました。リリースと切り戻しの方法はまだ決まっていないので、決めてください。'
# Records name the reports by variable; new_run evals them.
# shellcheck disable=SC2016
pro_rounds='rec_round "$found"; rec_edit Edit docs/design/webhook-retry.md; rec_round "$clean"'
pro_good="rec_edit Write $doc; $pro_rounds; $lint"

new_run proactive-after-writing-doc "$pro_good" "$write_doc"
grade "$pro_done"
expect_pass "proactive: a good run passes every assertion"

# Real runs record absolute paths.
# shellcheck disable=SC2016 # $work is expanded when new_run evals the records
new_run proactive-after-writing-doc "rec_edit Write \"\$work/$doc\"; $pro_rounds; $lint" "$write_doc"
grade "$pro_done"
expect_pass "proactive: an absolute file_path is the breakpoint"

# One clean round is a finished loop: whether the first round finds anything
# depends on the doc the run wrote.
# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write $doc; rec_round \"\$clean\"; $lint" "$write_doc"
grade "$pro_done"
expect_pass "proactive: a single clean round passes"

# proactive-with-claude-md brings in a CLAUDE.md that commits.
new_run proactive-after-writing-doc "$pro_good" "$write_doc; git add docs; git commit -q -m doc"
grade "$pro_done"
expect_pass "proactive: the doc committed passes"

new_run proactive-after-writing-doc "rec_edit Write $doc; $lint" "$write_doc"
grade "書きました。"
expect_fail "proactive: not starting the skill is caught" \
  "started review-design-doc on the doc it wrote" "started it after writing the doc" \
  "the last round reports no P1 and no P2" "answered in Japanese, the doc's language, in every round"

# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_round \"\$clean\"; rec_edit Write $doc; $lint" "$write_doc"
grade "$pro_done"
expect_fail "proactive: starting before writing is caught" "started it after writing the doc"

# Another file written first is not the breakpoint.
# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write docs/notes/x.md; rec_round \"\$clean\"; rec_edit Write $doc; $lint" "$write_doc"
grade "$pro_done"
expect_fail "proactive: a Write of another file is not the breakpoint" "started it after writing the doc"

# --- the loop ---
# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write $doc; rec_round \"\$found\"; rec_round \"\$clean\"; $lint" "$write_doc"
grade "$pro_done"
expect_fail "proactive: a re-run with nothing fixed is caught" "fixed something before every re-run"

# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write $doc; rec_round \"\$found\"; $lint" "$write_doc"
grade "$pro_done"
expect_fail "proactive: stopping with a P2 open is caught" "the last round reports no P1 and no P2"

# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write $doc; rec_round \"\$clean\"; rec_edit Edit $doc; rec_round \"\$clean\"; $lint" "$write_doc"
grade "$pro_done"
expect_fail "proactive: a re-run after a clean round is caught" "re-ran only after a round with P1 or P2"

# --- what the fix may write ---
new_run proactive-after-writing-doc "$pro_good" \
  "mkdir -p docs/design; printf '# Webhook 配信の自動リトライ\n\nJUDGE_FAIL\n' >$doc"
grade "$pro_done"
expect_fail "proactive: the judge reads the doc" "kept the release plan an open decision in the doc"

new_run proactive-after-writing-doc "$pro_good" "$write_doc"
grade "JUDGE_FAIL"
expect_fail "proactive: the judges read the final response" \
  "reaches a conclusion about P1 and P2" "told the user the release plan is theirs to decide"

# --- language and lint-docs ---
# The review's own report decides, not the caller's summary.
# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write $doc; rec_round \"\$found\"; rec_edit Edit $doc; rec_round \"\$clean_en_round\"; $lint" "$write_doc"
grade "$pro_done"
expect_fail "proactive: an English review of the Japanese doc is caught" \
  "answered in Japanese, the doc's language, in every round"

# Every round, not only the last: an English first round is one the user may
# have been shown.
# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write $doc; rec_round \"\$(en_report $doc)\"; rec_edit Edit $doc; rec_round \"\$clean\"; $lint" "$write_doc"
grade "$pro_done"
expect_fail "proactive: an English first round is caught" \
  "answered in Japanese, the doc's language, in every round"

new_run proactive-after-writing-doc "rec_edit Write $doc; $pro_rounds" "$write_doc"
grade "$pro_done"
expect_fail "proactive: leaving lint-docs out is caught" \
  "handed Japanese readability to lint-docs, after the review"

new_run proactive-after-writing-doc "rec_edit Write $doc; $lint; $pro_rounds" "$write_doc"
grade "$pro_done"
expect_fail "proactive: lint-docs before the review is caught" \
  "handed Japanese readability to lint-docs, after the review"

# Between rounds is too early: the fix and round 2 still change the text.
# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_edit Write $doc; rec_round \"\$found\"; $lint; rec_edit Edit $doc; rec_round \"\$clean\"" "$write_doc"
grade "$pro_done"
expect_fail "proactive: lint-docs before the review's last round is caught" \
  "handed Japanese readability to lint-docs, after the review"

# The caller's own summary may be English (proactive-with-claude-md's
# CLAUDE.md asks for it); only the review's rounds decide the language.
new_run proactive-after-writing-doc "$pro_good" "$write_doc"
grade "Wrote the doc. The review's P2 (no release or rollback plan) is now an open question in it, and round 2 had no P1 or P2. How to release and roll back is still undecided: that is yours to decide."
expect_pass "proactive: an English summary over Japanese rounds passes"

# --- the request itself ---
new_run proactive-after-writing-doc "$pro_good" \
  "mkdir -p docs/design; printf '# Retries\n\nWe retry.\n' >$doc"
grade "$pro_done"
expect_fail "proactive: an English doc is caught" "wrote it in Japanese"

new_run proactive-after-writing-doc "$pro_good" "$write_doc; printf 'x\n' >>docs/notes/webhook-retry.md"
grade "$pro_done"
expect_fail "proactive: touching the notes is caught" "changed nothing but the doc"

# shellcheck disable=SC2016
new_run proactive-after-writing-doc "rec_round \"\$clean\"; $lint" ''
grade "$pro_done"
expect_fail "proactive: not writing the doc is caught" \
  "wrote docs/design/webhook-retry.md" "wrote it in Japanese" \
  "started it after writing the doc" "changed nothing but the doc"

# ============================================================
# no-fire-readme-edit
# ============================================================
add_install="printf '\n## インストール\n\n1. git clone する\n2. ./install.sh を実行する\n' >>README.md"

new_run no-fire-readme-edit 'rec_edit Edit README.md' "$add_install"
grade "節を足しました。"
expect_pass "no-fire-readme: a good run passes every assertion"

new_run no-fire-readme-edit 'rec_edit Edit README.md; rec_skill' "$add_install"
grade "節を足しました。"
expect_fail "no-fire-readme: starting the skill is caught" \
  "did not start review-design-doc for a README"

new_run no-fire-readme-edit '' ''
grade "できません。"
expect_fail "no-fire-readme: doing nothing is caught" \
  "added the install steps to README.md" "changed nothing but README.md"

new_run no-fire-readme-edit 'rec_edit Edit README.md' "$add_install; printf 'x\n' >>$doc"
grade "節を足しました。"
expect_fail "no-fire-readme: touching the design doc is caught" "changed nothing but README.md"

# ============================================================
# no-fire-code-design-request
# ============================================================
# The scaffold must leave a commit that adds code and touches no doc, or the
# request is not about code.
new_run no-fire-code-design-request ''
if [ "$(git -C "$work" show --name-only --format= HEAD)" = "lib/slug.sh" ]; then
  ok "no-fire-code: the last commit adds lib/slug.sh alone"
else
  bad "no-fire-code: the last commit adds lib/slug.sh alone"
fi

new_run no-fire-code-design-request 'rec_skill review-design'
grade "## 設計レビュー: abc1234..def5678"
expect_pass "no-fire-code: a good run passes every assertion"

new_run no-fire-code-design-request 'rec_skill review-design-doc'
grade "$(report "$doc")"
expect_fail "no-fire-code: reviewing the doc instead is caught" \
  "did not start review-design-doc for a code review" "started review-design instead"

new_run no-fire-code-design-request 'rec_skill review-design; rec_skill review-design-doc'
grade "## 設計レビュー: abc1234..def5678"
expect_fail "no-fire-code: reviewing the doc as well is caught" \
  "did not start review-design-doc for a code review"

new_run no-fire-code-design-request ''
grade "設計は問題ありません。"
expect_fail "no-fire-code: starting nothing is caught" "started review-design instead"

if [ "$fails" -eq 0 ]; then
  printf '\nall review-design-doc grader tests passed\n'
  exit 0
fi
printf '\n%d review-design-doc grader test(s) failed\n' "$fails"
exit 1
