#!/bin/bash
#
# assert.test.sh — pins the graders of every lint-docs eval case, without
# calling the API.
#
# A grader is an instrument, and an inert one reports a paid, non-deterministic
# eval run that measured nothing. So for each case this builds the fixture its
# scaffold.sh builds, hands the grader a synthetic transcript of a good run and
# checks that it passes, then breaks one thing at a time and checks that the
# matching assertion FAILs and the grader exits non-zero.
#
# What it does not pin is the fixture's claim that each planted finding is one
# the toolchain reports: that needs textlint installed, which CI does not have.
# evals/README.md records the run that confirmed it.
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

# --- transcript records, in the stream-json shape the helpers read ---
# Scenarios name them inside strings that new_run evals, which shellcheck
# cannot follow.
rec_init() { printf '{"type":"system","subtype":"init"}\n'; }
# shellcheck disable=SC2329
rec_tool() { jq -nc --arg n "$1" --argjson i "$2" '{type: "assistant", message: {content: [{type: "tool_use", name: $n, input: $i}]}}'; }
# shellcheck disable=SC2329
rec_bash() { rec_tool Bash "$(jq -nc --arg c "$1" '{command: $c}')"; }
# shellcheck disable=SC2329
rec_edit() { rec_tool "$1" "$(jq -nc --arg p "$2" '{file_path: $p}')"; }
# shellcheck disable=SC2329
rec_grep() { rec_tool Grep "$(jq -nc --arg p "$1" '{pattern: $p}')"; }
# shellcheck disable=SC2329
rec_skill() { rec_tool Skill '{"skill":"lint-docs"}'; }

# new_run <case> <records> [<tree change>]
# The fixture the case's scaffold builds, the records as its transcript, and
# the tree changed the way the run under test did.
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
  ) >/dev/null 2>&1 || return 1
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
# fragile, or one that reads something it should not. A mutation that breaks
# two contracts at once lists both.
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

# ============================================================
# detects-each-category
# ============================================================
# One report line per category, each matching its own check and no other, so
# dropping a line shows which check reads it.
detect_lines=(
  'docs/guide.md:3 サーバ → サーバー（実測 サーバー 3 : サーバ 1、辞書と一致）'
  'docs/guide.md:5 単一の真実のソース → Source of Truth'
  'docs/guide.md:7 再試行 → リトライ'
  'docs/guide.md:9 予め → あらかじめ'
  'docs/guide.md:11 大幅に（誇張）'
  'docs/guide.md:13 次を実行する: で終わる文'
  'docs/guide.md:15 リスト項目の ✅'
  'docs/guide.md:18 読み込むことができる → 読み込める'
)
detect_checks=(
  '表記ゆれ: サーバ (line 3)'
  '直訳新造語: 単一の真実のソース (line 5)'
  '過剰な漢語化: 再試行 (line 7)'
  'ひらき: 予め (line 9)'
  '誇張: 大幅に / 完全に (line 11)'
  '英語式コロン: 次を実行する: (line 13)'
  '装飾絵文字: ✅ (line 15)'
  '冗長表現: ことができる (line 18, beyond the tool)'
)
# detect_report [<index to drop>]
detect_report() {
  local i
  printf '## ドキュメント検査: docs/guide.md\n'
  for i in "${!detect_lines[@]}"; do
    [ "$i" = "${1:-}" ] || printf -- '- %s\n' "${detect_lines[$i]}"
  done
}
detect_good='rec_bash "textlint-docs docs/guide.md"; rec_bash "rg -oI サーバー -g *.md ."'

new_run detects-each-category "$detect_good"
grade "$(detect_report)"
expect_pass "detect: a good run passes every assertion"

for i in "${!detect_checks[@]}"; do
  new_run detects-each-category "$detect_good"
  grade "$(detect_report "$i")"
  # Line 3 also carries the count, so dropping it drops both.
  if [ "$i" -eq 0 ]; then
    expect_fail "detect: a report without line ${detect_lines[$i]%% *} is caught" "${detect_checks[$i]}" \
      "reports the count behind the サーバ finding"
  else
    expect_fail "detect: a report without line ${detect_lines[$i]%% *} is caught" "${detect_checks[$i]}"
  fi
done

# Step 4's count through the Grep tool is a measurement too.
new_run detects-each-category 'rec_bash "textlint-docs docs/guide.md"; rec_grep "サーバ(?!ー)"'
grade "$(detect_report)"
expect_pass "detect: a count through the Grep tool is a measurement"

new_run detects-each-category 'rec_bash "rg -oI サーバー -g *.md ."'
grade "$(detect_report)"
expect_fail "detect: a run that never called textlint-docs is caught" \
  "ran textlint-docs on docs/guide.md"

# A textlint-docs call names サーバ nowhere, and must not count as the count.
new_run detects-each-category 'rec_bash "textlint-docs docs/guide.md"'
grade "$(detect_report)"
expect_fail "detect: an adopted section B finding nobody counted is caught" \
  "counted サーバ across the project"

# Searches that look like a count and are not one of the project.
for search in \
  'rec_bash "textlint-docs docs/guide.md | grep サーバ"' \
  'rec_bash "rg -c サーバ docs/guide.md"' \
  'rec_tool Grep "{\"pattern\":\"サーバ\",\"path\":\"docs/guide.md\"}"'; do
  new_run detects-each-category "rec_bash 'textlint-docs docs/guide.md'; $search"
  grade "$(detect_report)"
  expect_fail "detect: not a project count: ${search#rec_* }" "counted サーバ across the project"
done

# The documented spellings of the count are counts.
for search in \
  "rec_bash \"rg -oI --pcre2 'サーバ(?!ー|レス)' -g '*.md' .\"" \
  'rec_bash "rg -oI --pcre2 \"サーバー\" -g \"*.md\" ."' \
  'rec_tool Grep "{\"pattern\":\"サーバー\",\"glob\":\"*.md\",\"output_mode\":\"count\"}"'; do
  new_run detects-each-category "rec_bash 'textlint-docs docs/guide.md'; $search"
  grade "$(detect_report)"
  expect_pass "detect: a project count: ${search#rec_* }"
done

# A line number is not a count, nor is textlint's own path:line:col.
new_run detects-each-category "$detect_good"
grade "$(detect_report | sed 's/（実測.*）//')"
expect_fail "detect: a サーバ finding reported without its count is caught" \
  "reports the count behind the サーバ finding"

# Numbers that are not counts: locations on either side of the word, list
# and heading numbering, and the shapes the rejected spellings leaked.
for location in \
  'docs/guide.md:3:8 サーバ → サーバー' \
  'サーバ 3 行目で検出' \
  'サーバ 3:5 で検出' \
  'サーバ（3 行目）' \
  '1. docs/guide.md:3:8 サーバ → サーバー' \
  '## 3. 表記ゆれ サーバ' \
  'docs/guide.md L3 サーバ' \
  'docs/guide.md line 3 サーバ' \
  'docs/guide.md:3-5 サーバ'; do
  new_run detects-each-category "$detect_good"
  grade "$(detect_report | sed "s|^- docs/guide.md:3 .*|- $location|")"
  expect_fail "detect: not a count: $location" \
    "reports the count behind the サーバ finding"
done

# The spellings real runs used for the count, a location beside them.
for spelling in \
  '（3 行目）: サーバー 3 : サーバ 1' \
  'docs/guide.md:3 「サーバー」が 3 件' \
  'サーバ: サーバー 0 : サーバ 7' \
  'サーバー 3：サーバ 1'; do
  new_run detects-each-category "$detect_good"
  grade "$(detect_report | sed "s|^- docs/guide.md:3 .*|- $spelling|")"
  expect_pass "detect: a count: $spelling"
done

new_run detects-each-category "$detect_good; rec_edit Edit docs/guide.md"
grade "$(detect_report)"
expect_fail "detect: an Edit is caught" "used neither Edit nor Write"

new_run detects-each-category "$detect_good" 'printf "x\n" >>docs/guide.md'
grade "$(detect_report)"
expect_fail "detect: a changed tree is caught" "left the tree as it was"

new_run detects-each-category "$detect_good" 'git commit -q --allow-empty -m x'
grade "$(detect_report)"
expect_fail "detect: a commit is caught" "committed nothing"

new_run detects-each-category "$detect_good"
grade "$(detect_report)" 1
expect_fail "detect: a refused command is caught" "no command was refused"

# ============================================================
# excludes-english-docs
# ============================================================
excl_report='## ドキュメント検査: 未コミットの Markdown
- 対象: docs/guide-ja.md（日本語 1 ファイル）
- 対象外: 2 ファイル（英語文書 2）
- docs/guide-ja.md:5 予め → あらかじめ'
excl_density='rg -c 。 docs/guide-ja.md README.md skills/deploy/SKILL.md'
excl_good="rec_bash 'git status --porcelain'; rec_bash '$excl_density'; rec_bash 'textlint-docs docs/guide-ja.md'"

new_run excludes-english-docs "$excl_good"
grade "$excl_report"
expect_pass "exclude: a good run passes every assertion"

# The scaffold leaves three changes uncommitted; without them step 1 has no
# candidates and the case measures nothing.
if [ "$(git -C "$work" status --porcelain | wc -l | tr -d ' ')" = "3" ]; then
  ok "exclude: the scaffold leaves three uncommitted candidates"
else
  bad "exclude: the scaffold leaves three uncommitted candidates"
fi

new_run excludes-english-docs "rec_bash 'textlint-docs docs/guide-ja.md README.md'"
grade "$excl_report"
expect_fail "exclude: linting the English README is caught" "did not lint the English README"

new_run excludes-english-docs "$excl_good; rec_bash 'textlint-docs skills/deploy/SKILL.md'"
grade "$excl_report"
expect_fail "exclude: linting the hiragana-trap SKILL.md is caught" \
  "did not lint the English SKILL.md with Japanese triggers"

new_run excludes-english-docs "$excl_good; rec_bash 'textlint-docs \"**/*.md\"'"
grade "$excl_report"
expect_fail "exclude: a whole-repo glob is caught" "did not lint the whole repository by glob"

new_run excludes-english-docs "rec_bash '$excl_density'"
grade "$excl_report"
expect_fail "exclude: a run that never linted the Japanese doc is caught" \
  "ran textlint-docs on docs/guide-ja.md"

new_run excludes-english-docs "$excl_good"
grade "${excl_report/対象外: 2/対象外: 0}"
expect_fail "exclude: a report that does not count what it left out is caught" \
  "reports how many files it left out (対象外: 2)"

new_run excludes-english-docs "$excl_good"
grade "${excl_report%- docs/guide-ja.md:5*}"
expect_fail "exclude: a report without the Japanese finding is caught" \
  "reports the finding in docs/guide-ja.md (予め)"

new_run excludes-english-docs "$excl_good" 'printf "x\n" >>README.md'
grade "$excl_report"
expect_fail "exclude: touching an uncommitted change is caught" \
  "left the uncommitted changes as they were"

# ============================================================
# prh-direction-reversed
# ============================================================
prh_report='## ドキュメント検査: docs/new.md
- docs/new.md:5 予め → あらかじめ（修正済み）

### 表記ゆれ（実測つき）
- サーバ: サーバー 0 : サーバ 7。辞書の方向が対象プロジェクトと逆なので修正しない'
prh_good="rec_bash 'textlint-docs docs/new.md'; rec_bash 'rg -oI サーバー -g *.md .'; rec_edit Edit docs/new.md; rec_bash 'git diff'"
prh_fix='sed "s/予め/あらかじめ/" docs/new.md >docs/n.tmp; mv docs/n.tmp docs/new.md'
# --fix over the whole file: both rules applied.
prh_blind='sed -e "s/予め/あらかじめ/" -e "s/サーバ/サーバー/g" docs/new.md >docs/n.tmp; mv docs/n.tmp docs/new.md'

new_run prh-direction-reversed "$prh_good" "$prh_fix"
grade "$prh_report"
expect_pass "prh: a good run passes every assertion"

# Nothing fixed: 予め stays, and so the tree has no diff at all.
new_run prh-direction-reversed "$prh_good" ":"
grade "$prh_report"
expect_fail "prh: the scaffold plants 予め" "fixed 予め to あらかじめ" "no 予め left" \
  "touched docs/new.md only"

new_run prh-direction-reversed "$prh_good" "$prh_blind"
grade "$prh_report"
expect_fail "prh: applying the minority direction is caught" \
  "kept サーバ in docs/new.md (the project's majority)" \
  "did not apply サーバー (the dictionary's direction, here the minority)"

new_run prh-direction-reversed "rec_bash 'textlint-docs docs/new.md'; rec_edit Edit docs/new.md; rec_bash 'git diff'" "$prh_fix"
grade "$prh_report"
expect_fail "prh: keeping サーバ without counting is caught" "counted サーバ across the project"

new_run prh-direction-reversed "$prh_good" "$prh_fix"
grade "${prh_report/サーバー 0 : サーバ 7。/}"
expect_fail "prh: the direction reported without its count is caught" \
  "reports the count behind the サーバ finding"

# Step 5.1's look at the tree is not 5.4's look at the fix.
new_run prh-direction-reversed "rec_bash 'git diff'; rec_bash 'textlint-docs docs/new.md'; rec_bash 'rg -oI サーバー -g *.md .'; rec_edit Edit docs/new.md" "$prh_fix"
grade "$prh_report"
expect_fail "prh: a diff read only before the fix is caught" "read git diff after fixing"

new_run prh-direction-reversed "rec_bash 'textlint-docs docs/new.md'; rec_bash 'rg -oI サーバー -g *.md .'; rec_edit Edit docs/new.md; rec_bash 'git --no-pager diff docs/new.md'" "$prh_fix"
grade "$prh_report"
expect_pass "prh: git --no-pager diff counts as reading the diff"

new_run prh-direction-reversed "$prh_good" "$prh_fix"
grade "${prh_report/逆なので/一致するが}"
expect_fail "prh: a report silent on the direction is caught" \
  "reports that the dictionary runs against the project"

new_run prh-direction-reversed "rec_bash 'textlint-docs docs/new.md'; rec_bash 'rg -oI サーバー -g *.md .'; rec_edit Edit docs/new.md" "$prh_fix"
grade "$prh_report"
expect_fail "prh: fixing without reading the diff is caught" "read git diff after fixing"

new_run prh-direction-reversed "$prh_good" "$prh_fix; printf 'x\n' >>docs/ops.md"
grade "$prh_report"
expect_fail "prh: touching another document is caught" "touched docs/new.md only"

new_run prh-direction-reversed "$prh_good" "$prh_fix; git commit -qam fix"
grade "$prh_report"
expect_fail "prh: a commit is caught" "committed nothing"

new_run prh-direction-reversed "$prh_good" "$prh_fix"
grade "$prh_report" 1
expect_fail "prh: a refused command is caught" "no command was refused"

# ============================================================
# fires-on-trigger-phrase (and fires-on-paraphrase, by exec)
# ============================================================
for c in fires-on-trigger-phrase fires-on-paraphrase; do
  new_run "$c" 'rec_skill; rec_bash "textlint-docs docs/guide.md"'
  grade "指摘は 10 件です。"
  expect_pass "$c: a good run passes every assertion"

  new_run "$c" 'rec_bash "textlint-docs docs/guide.md"'
  grade "指摘は 10 件です。"
  expect_fail "$c: running the tool without the skill is caught" \
    "started lint-docs without being named"

  # Another skill is not this one starting.
  new_run "$c" 'rec_tool Skill "{\"skill\":\"review-test\"}"; rec_bash "textlint-docs docs/guide.md"'
  grade "指摘は 10 件です。"
  expect_fail "$c: another skill does not count" "started lint-docs without being named"

  new_run "$c" 'rec_skill'
  grade "指摘は 10 件です。"
  expect_fail "$c: starting the skill and not linting is caught" \
    "ran textlint-docs on docs/guide.md"

  new_run "$c" 'rec_skill; rec_bash "textlint-docs --fix docs/guide.md"' 'printf "x\n" >>docs/guide.md'
  grade "直しました。"
  expect_fail "$c: rewriting the document unasked is caught" "left the tree as it was"
done

# ============================================================
# no-fire-english-doc
# ============================================================
new_run no-fire-english-doc 'rec_edit Read README.md'
grade "README.md の 3 行目は 1 文が長すぎます。"
expect_pass "no-fire: a good run passes every assertion"

new_run no-fire-english-doc 'rec_skill; rec_edit Read README.md'
grade "README.md の 3 行目は 1 文が長すぎます。"
expect_fail "no-fire: starting the skill is caught" \
  "did not start lint-docs for an English document"

new_run no-fire-english-doc 'rec_bash "textlint-docs README.md"'
grade "README.md の 3 行目は 1 文が長すぎます。"
expect_fail "no-fire: running the tool directly is caught" "did not run textlint-docs"

new_run no-fire-english-doc ''
grade ""
expect_fail "no-fire: a run that answered nothing is caught" \
  "answered about README.md's overlong sentence"

new_run no-fire-english-doc ''
grade "この文書は確認できません。"
expect_fail "no-fire: a refusal is caught" "answered about README.md's overlong sentence"

# ============================================================
# after-writing-ja-doc
# ============================================================
after_write='printf "# 配布手順\n\nビルドしてから配布する。\n" >docs/deploy.md'

new_run after-writing-ja-doc 'rec_edit Write docs/deploy.md; rec_skill; rec_bash "textlint-docs docs/deploy.md"' "$after_write"
grade "書きました。"
expect_pass "after-writing: a good run passes every assertion"

new_run after-writing-ja-doc 'rec_edit Write docs/deploy.md' "$after_write"
grade "書きました。"
expect_fail "after-writing: not starting the skill is caught" \
  "started lint-docs on the document it wrote" "ran textlint-docs on docs/deploy.md"

new_run after-writing-ja-doc 'rec_skill; rec_bash "textlint-docs docs/guide.md"' "$after_write"
grade "書きました。"
expect_fail "after-writing: linting another document is caught" "ran textlint-docs on docs/deploy.md"

new_run after-writing-ja-doc 'rec_skill; rec_bash "textlint-docs docs/deploy.md"' ''
grade "書きました。"
expect_fail "after-writing: not writing the document is caught" "wrote docs/deploy.md" \
  "wrote it in Japanese"

new_run after-writing-ja-doc 'rec_edit Write docs/deploy.md; rec_skill; rec_bash "textlint-docs docs/deploy.md"' \
  'printf "# Deploy\n\nBuild, then ship.\n" >docs/deploy.md'
grade "Done."
expect_fail "after-writing: an English document is caught" "wrote it in Japanese"

if [ "$fails" -eq 0 ]; then
  printf '\nall lint-docs grader tests passed\n'
  exit 0
fi
printf '\n%d lint-docs grader test(s) failed\n' "$fails"
exit 1
