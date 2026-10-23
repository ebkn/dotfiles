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
new_run clean-doc-no-false-p1 '' && cp "$work/$doc" "$root_dir/clean.md"
new_run clean-doc-no-false-p1-en '' && cp "$work/$doc" "$root_dir/clean-en.md"
for c in strawman-alternatives negated-non-goals missing-rollback unsupported-claims \
  hidden-uncertainty dependency-unconfirmed implementation-manual missing-rollback-en; do
  new_run "$c" '' || continue
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

  new_run "$c" ''
  grade "$(report "$doc" '見つけた問題' '' '細かい言い回し')"
  expect_pass "$c: a good run passes every assertion"

  # Found under P2 is found: the priority is the skill's call.
  new_run "$c" ''
  grade "$(report "$doc" '' '見つけた問題')"
  expect_pass "$c: a finding under P2 counts"

  new_run "$c" ''
  grade "$(report "$doc" '' '' '見つけた問題')"
  expect_fail "$c: a finding under P3 only is caught" "$judged"

  new_run "$c" ''
  grade "$(report "$doc" 'なし' '' '見つけた問題')"
  expect_fail "$c: a P1 section saying none is not a finding" "$judged"

  new_run "$c" ''
  grade "$(report "$doc" 'JUDGE_FAIL')"
  expect_fail "$c: the judge reads the P1 section" "$judged"

  new_run "$c" ''
  grade "$(report "$doc" '' 'JUDGE_FAIL')"
  expect_fail "$c: the judge reads the P2 section" "$judged"

  # A P3 item is not shown to the judge.
  new_run "$c" ''
  grade "$(report "$doc" '見つけた問題' '' 'JUDGE_FAIL')"
  expect_pass "$c: the judge does not read P3"

  new_run "$c" ''
  grade "$(report "$doc" '見つけた問題' | sed '1s/^.*$/設計ドキュメントをレビューしました。/')"
  expect_fail "$c: a report without the heading is caught" \
    "reported under the review heading, naming the doc"

  new_run "$c" ''
  grade "$(report docs/design/other.md '見つけた問題')"
  expect_fail "$c: a heading naming another doc is caught" \
    "reported under the review heading, naming the doc"

  new_run "$c" "rec_edit Edit $doc"
  grade "$(report "$doc" '見つけた問題')"
  expect_fail "$c: an Edit is caught" "used neither Edit nor Write"

  new_run "$c" '' "printf 'x\n' >>$doc"
  grade "$(report "$doc" '見つけた問題')"
  expect_fail "$c: a changed tree is caught" "left the tree as it was"

  new_run "$c" '' 'git commit -q --allow-empty -m x'
  grade "$(report "$doc" '見つけた問題')"
  expect_fail "$c: a commit is caught" "committed nothing"

  new_run "$c" ''
  grade "$(report "$doc" '見つけた問題')" 1
  expect_fail "$c: a refused command is caught" "no command was refused"
done

# The heading's other spellings. The backticks are literal, not a command.
# shellcheck disable=SC2016
for heading in '**Design doc review:** docs/design/webhook-retry.md' \
  '# 設計書レビュー：docs/design/webhook-retry.md' \
  '## Design Document Review: `docs/design/webhook-retry.md`'; do
  new_run strawman-alternatives ''
  grade "$(report "$doc" '見つけた問題' | sed "1s|^.*\$|$heading|")"
  expect_pass "heading: $heading"
done

# ============================================================
# dependency-unconfirmed: judged on the whole report
# ============================================================
new_run dependency-unconfirmed ''
grade "$(report "$doc" '' '' '細かい言い回し')
### 著者への質問
- 基盤チームは増強に合意していますか"
expect_pass "dependency: a question outside P1/P2 passes"

new_run dependency-unconfirmed ''
grade "$(report "$doc" '' '' '細かい言い回し')
### 著者への質問
- JUDGE_FAIL"
expect_fail "dependency: the judge reads the whole report" \
  "raises whether the platform team agreed to enlarge the database"

new_run dependency-unconfirmed "rec_edit Write $doc"
grade "$(report "$doc" '基盤チームの合意が書かれていない')"
expect_fail "dependency: a Write is caught" "used neither Edit nor Write"

# ============================================================
# clean-doc-no-false-p1 (and -en)
# ============================================================
new_run clean-doc-no-false-p1 ''
grade "$(report "$doc" '' '補足があるとよい' '言い回し')"
expect_pass "clean: a P2 and a P3 pass"

new_run clean-doc-no-false-p1 ''
grade "$(report "$doc" 'なし')"
expect_pass "clean: a kept P1 heading saying none passes"

new_run clean-doc-no-false-p1 ''
grade "$(report "$doc" '誤検知')"
expect_fail "clean: a P1 is caught" "raised no P1"

new_run clean-doc-no-false-p1 ''
grade "$(printf '## 設計ドキュメントレビュー: %s\n\n### P1\n1. 誤検知\n' "$doc")"
expect_fail "clean: a numbered P1 is caught" "raised no P1"

new_run clean-doc-no-false-p1 "rec_edit Edit $doc"
grade "$(report "$doc")"
expect_fail "clean: an Edit is caught" "used neither Edit nor Write"

en_report="## Design doc review: $doc

The approach is sound.

### P2
- The dashboard could say who acts on a dead letter."

new_run clean-doc-no-false-p1-en ''
grade "$en_report"
expect_pass "clean-en: a good run passes every assertion"

new_run clean-doc-no-false-p1-en ''
grade "$en_report
- 冪等キーの説明"
expect_fail "clean-en: Japanese in the report is caught" "wrote no Japanese into an English review"

new_run clean-doc-no-false-p1-en ''
grade "$en_report

### P1
- a false alarm"
expect_fail "clean-en: a P1 is caught" "raised no P1"

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

# ============================================================
# mini-doc-no-template-demands
# ============================================================
mini=docs/design/cache-ttl.md

new_run mini-doc-no-template-demands ''
grade "$(report "$mini" '' '' '言い回し')"
expect_pass "mini: nothing under P1 or P2 passes without a judge"

new_run mini-doc-no-template-demands ''
grade "$(report "$mini" '' 'パージ失敗の検知方法')"
expect_pass "mini: a P2 about the change passes"

new_run mini-doc-no-template-demands ''
grade "$(report "$mini" '' 'JUDGE_FAIL')"
expect_fail "mini: the judge reads P2" "asked for no section the change does not need"

new_run mini-doc-no-template-demands ''
grade "$(report "$mini" 'セキュリティの節がない')"
expect_fail "mini: a P1 is caught" "raised no P1"

new_run mini-doc-no-template-demands ''
grade "$(report "$doc" '' '' '言い回し')"
expect_fail "mini: a heading naming the webhook doc is caught" \
  "reported under the review heading, naming the doc"

# ============================================================
# fires-on-phrase
# ============================================================
new_run fires-on-phrase 'rec_skill'
grade "$(report "$doc" '代替案が藁人形')"
expect_pass "fires: a good run passes every assertion"

new_run fires-on-phrase ''
grade "$(report "$doc" '代替案が藁人形')"
expect_fail "fires: reviewing without the skill is caught" \
  "started review-design-doc without being named"

new_run fires-on-phrase "rec_skill; rec_edit Edit $doc" "printf 'x\n' >>$doc"
grade "$(report "$doc" '代替案が藁人形')"
expect_fail "fires: rewriting the doc unasked is caught" \
  "used neither Edit nor Write" "left the tree as it was"

# ============================================================
# proactive-after-writing-doc
# ============================================================
write_doc="mkdir -p docs/design; printf '# Webhook 配信の自動リトライ\n\n再送する。\n' >$doc"
pro_good="rec_edit Write $doc; rec_skill"

new_run proactive-after-writing-doc "$pro_good" "$write_doc"
grade "$(report "$doc" '' 'ロールバックの節がない')"
expect_pass "proactive: a good run passes every assertion"

# Real runs record absolute paths.
# shellcheck disable=SC2016 # $work is expanded when new_run evals the records
new_run proactive-after-writing-doc 'rec_edit Write "$work/docs/design/webhook-retry.md"; rec_skill' "$write_doc"
grade "$(report "$doc" '' 'ロールバックの節がない')"
expect_pass "proactive: an absolute file_path is the breakpoint"

new_run proactive-after-writing-doc "rec_edit Write $doc" "$write_doc"
grade "書きました。"
expect_fail "proactive: not starting the skill is caught" \
  "started review-design-doc on the doc it wrote" "started it after writing the doc" \
  "did not edit the doc after the review" "closed with the review, naming the doc"

new_run proactive-after-writing-doc "rec_skill; rec_edit Write $doc" "$write_doc"
grade "$(report "$doc" '' 'ロールバックの節がない')"
expect_fail "proactive: starting before writing is caught" \
  "started it after writing the doc" "did not edit the doc after the review"

# Another file written first is not the breakpoint.
new_run proactive-after-writing-doc "rec_edit Write docs/notes/x.md; rec_skill; rec_edit Write $doc" "$write_doc"
grade "$(report "$doc" '' 'ロールバックの節がない')"
expect_fail "proactive: a Write of another file is not the breakpoint" \
  "started it after writing the doc" "did not edit the doc after the review"

new_run proactive-after-writing-doc "$pro_good; rec_edit Edit $doc" "$write_doc"
grade "$(report "$doc" '' 'ロールバックの節がない')"
expect_fail "proactive: filling in the doc after the review is caught" \
  "did not edit the doc after the review"

new_run proactive-after-writing-doc "$pro_good" "$write_doc"
grade "書いてレビューしました。"
expect_fail "proactive: closing without the report is caught" \
  "closed with the review, naming the doc"

new_run proactive-after-writing-doc "$pro_good" \
  "mkdir -p docs/design; printf '# Retries\n\nWe retry.\n' >$doc"
grade "$(report "$doc" '' 'ロールバックの節がない')"
expect_fail "proactive: an English doc is caught" "wrote it in Japanese"

new_run proactive-after-writing-doc "$pro_good" "$write_doc; printf 'x\n' >>docs/notes/webhook-retry.md"
grade "$(report "$doc" '' 'ロールバックの節がない')"
expect_fail "proactive: touching the notes is caught" "changed nothing but the doc"

new_run proactive-after-writing-doc "rec_skill" ''
grade "$(report "$doc" '' 'ロールバックの節がない')"
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
