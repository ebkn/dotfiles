# grading.sh — what every review-design-doc eval case reads off a run the
# same way. Sourced from a case's assert.sh after skill-eval-assert.sh.
#
# The report format these read is the contract evals/README.md states for
# SKILL.md: a heading naming the doc, then findings under `P1` / `P2` / `P3`
# headings. It is one decision, so it lives here once rather than per case.
#
# Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# The report's own heading line, not a mention of a review: "設計ドキュメントを
# レビューします" has no colon after the title, and must not count as having
# reported. `##` or bold, since the model varies how it sets the line.
RDD_REPORT_HEADING='(^|\n)(#+ *|\*\*)?(設計ドキュメント|デザインドキュメント|設計書|[Dd]esign [Dd]oc(ument)?) ?(の)?(レビュー|[Rr]eview) *[:：]'

# rdd_report
# What the user is handed at the end of the run: the final response. The skill
# may run forked, and its report then reaches the user only if the caller
# writes it out, so a report left inside the Skill's tool_result is not one.
rdd_report() {
  transcript_result_text
}

# rdd_has_heading <report> <path regex>
# The heading line is present and names the doc it reviewed.
rdd_has_heading() {
  jq -nre --arg r "$1" --arg h "$RDD_REPORT_HEADING" --arg p "$2" \
    '$r | test($h + "[^\n]*" + $p)' >/dev/null
}

# rdd_section <report> <P1|P2|P3>
# The lines under that priority's heading, up to the next heading.
#
# Read wide on purpose. The clean cases grade "no P1" on this, so a P1 the
# parser misses is a false alarm graded clean: a heading is any `#` line or a
# line that is bold and nothing else (`**P1**`), and it is that priority's when
# the label appears in it as a word (`### 🔴 P1`, `### 重大 (P1)`). Every
# non-blank line under it is kept, bullet or paragraph.
#
# The one line dropped is an item that says there is nothing and nothing more
# ("なし", "- None."). "なし。ただし…" or "None of the goals …" is a finding
# and stays.
#
# This differs on purpose from transcript_skill_rounds' open_findings, which
# the runner prints as `round: open=N` for every skill: that reader takes only
# label-first headings, treats a section opening with "なし…" as closed, and
# reads the Skill's tool_result rather than the final response. Here its
# number is informational; this reader decides the grade. Widening it instead
# would change review-test's and review-design's grading.
rdd_section() {
  printf '%s\n' "$1" | awk -v p="$2" '
    /^#+/ || /^[[:space:]]*\*\*[^*]+\*\*[[:space:]:：]*$/ {
      sec = ($0 ~ ("(^|[^A-Za-z0-9])" p "([^0-9]|$)"))
      next
    }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*([-*][[:space:]]+)?(なし|該当なし|ありません|指摘なし|None|none|No findings|N\/A)[。.]?[[:space:]]*$/ { next }
    sec { print }
  '
}

# rdd_ranks_under_headings <report>
# No finding is ranked inline: no list item that leads with its priority
# (`- **P1**: …`, `- [P2] …`, `1. P1 …`) and no table cell holding one
# (`| P1 | … |`). rdd_section reads priorities from headings alone, so a finding
# ranked inline is one it cannot see -- and on a clean doc an unseen P1 grades
# as none. Failing such a report here keeps the parser simple and the contract
# enforced. Prose that merely mentions a priority ("P1 はありません") is not a
# ranking and passes.
rdd_ranks_under_headings() {
  ! printf '%s\n' "$1" |
    grep -qE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+(\*\*|\[|`)?P[123]([^0-9]|$)|\|[[:space:]]*(\*\*)?P[123]([^0-9]|$)'
}

# rdd_count <report> <P1|P2|P3>
# Findings under that heading: its list items, or 1 for a section written as
# prose with no list. Nested evidence bullets count too; the cases ask only
# whether it is 0.
rdd_count() {
  local section items
  section="$(rdd_section "$1" "$2")"
  [ -n "$section" ] || {
    echo 0
    return
  }
  items="$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+' <<<"$section" || true)"
  [ "$items" -gt 0 ] || items=1
  echo "$items"
}

# rdd_open_text <report>
# The P1 and P2 sections together -- what a judged check reads, so that a
# finding mentioned only under P3 or in passing does not count as raised.
rdd_open_text() {
  local p1 p2
  p1="$(rdd_section "$1" P1)"
  p2="$(rdd_section "$1" P2)"
  printf '%s\n%s\n' "${p1:+### P1
$p1}" "${p2:+### P2
$p2}"
}

# rdd_check_flags <label> <rubric>
# One finding among P1 and P2 meets the rubric. A report with nothing under
# either fails without asking the judge: an empty text would otherwise be
# graded on the judge's reading of "nothing".
rdd_check_flags() {
  local open
  open="$(rdd_open_text "$(rdd_report)")"
  if [ -z "$(printf '%s' "$open" | tr -d '[:space:]')" ]; then
    printf 'FAIL  %s (no P1 or P2 finding)\n' "$1"
    SKILL_EVAL_FAILED=1
    return
  fi
  check_llm "$1" "The text is the P1 and P2 findings of a review of a software design document. It passes only if at least one finding says that $2 A finding that is about something else fails, however close." "$open"
}

# The finding missing-rollback and missing-rollback-en both ask for: one
# rubric, so a difference between them is the language's.
# shellcheck disable=SC2034  # read by the cases that source this file
RDD_ROLLBACK_RUBRIC="the doc has no way back: it goes live for every customer at once with no staged rollout, or it says nothing about how to roll the change back or turn it off if it misbehaves."

# rdd_has_kana <text>
# True when the text holds hiragana or katakana. jq's regex is Unicode-aware
# whatever the locale, where grep's bracket ranges depend on it.
rdd_has_kana() {
  jq -nre --arg t "$1" '$t | test("[\\x{3040}-\\x{30ff}]")' >/dev/null
}

# rdd_has_no_kana <text>
# The English cases' check: nothing in their fixture or prompt is Japanese, so
# any kana in the report is the skill's own. An empty report passes this and
# fails the heading check instead.
rdd_has_no_kana() {
  ! rdd_has_kana "$1"
}

# rdd_is_japanese <text>
# Written in Japanese, not merely holding some: an English review of a
# Japanese doc quotes it, so kana alone would pass one. Quoted spans (code,
# 「」, 『』, "", “”, `>` lines) and paths are dropped, and what is left must
# hold at least as many kana as ASCII words -- a Japanese review still says P1
# and Webhook, an English one is mostly words.
rdd_is_japanese() {
  jq -nre --arg t "$1" '
    $t
    | gsub("`[^`\n]*`"; "") | gsub("「[^」]*」"; "") | gsub("『[^』]*』"; "")
    | gsub("\"[^\"\n]*\""; "") | gsub("“[^”]*”"; "") | gsub("(^|\n)>[^\n]*"; "")
    | gsub("[A-Za-z0-9_-]*([./:][A-Za-z0-9_-]+)+"; "")
    | ([scan("[\\x{3040}-\\x{30ff}]")] | length) as $kana
    | ([scan("[A-Za-z]+")] | length) as $words
    | $kana > 0 and $kana >= $words
  ' >/dev/null
}

# rdd_check_language <ja|en> <report>
# The review answers in the doc's language. Every Japanese case's doc is
# Japanese, whatever the request was written in (answers-in-doc-language asks
# in English); the English cases' are English.
rdd_check_language() {
  case "$1" in
    ja) check "answered in Japanese, the doc's language" rdd_is_japanese "$2" ;;
    en) check "wrote no Japanese into an English review" rdd_has_no_kana "$2" ;;
  esac
}

# rdd_lint_after_review
# lint-docs started after the last round of the review. The review leaves the
# readability of Japanese prose to lint-docs rather than ranking it next to
# missing decisions, and lints the text the review is done changing. A case
# started by name has no Skill call of the review to order against (the slash
# command expands in place), so there any call of lint-docs counts.
rdd_lint_after_review() {
  local last
  last="$(transcript_skill_rounds review-design-doc | jq -s 'last.index // -1')"
  transcript_skill_rounds lint-docs | jq -se --argjson a "$last" 'any(.[]; .index > $a)' >/dev/null
}

# rdd_check_lint <ja|en>
# A Japanese doc goes to lint-docs; an English one does not, since lint-docs'
# rules are for Japanese prose and turn to noise on English (its own SKILL.md).
# The cases carry lint-docs (`skills: lint-docs`) either way, so that leaving
# it out of an English doc is a choice the run made.
rdd_check_lint() {
  case "$1" in
    ja) check "handed Japanese readability to lint-docs, after the review" rdd_lint_after_review ;;
    en) check_eq "left lint-docs out of an English doc" "0" "$(transcript_skill_uses lint-docs)" ;;
  esac
}

# rdd_every_round_japanese
# Every round's report, as the forked review handed it back, is Japanese: each
# is the review's own words, whatever language the caller then writes its
# summary in, and a round in the wrong language is one the user may be shown.
# False with no round at all.
rdd_every_round_japanese() {
  local rounds n k
  rounds="$(transcript_skill_rounds review-design-doc)"
  n="$(jq -s 'length' <<<"$rounds")"
  [ "$n" -gt 0 ] || return 1
  for ((k = 0; k < n; k++)); do
    rdd_is_japanese "$(jq -rs --argjson k "$k" '.[$k].report' <<<"$rounds")" || return 1
  done
}

# rdd_changed_paths
# Every path that differs from the fixture, committed or not, untracked
# included. A run that commits its doc and one that leaves it in the tree
# then read the same.
rdd_changed_paths() {
  {
    git diff --name-only eval-base
    git ls-files --others --exclude-standard
  } | sort -u
}

# rdd_writes
# Edit and Write calls together.
rdd_writes() {
  echo $(($(transcript_tool_uses Edit) + $(transcript_tool_uses Write)))
}

# rdd_check_read_only
# A requested review is report-only, through the caller's part too: the doc is
# the user's and records their decisions, and a run that "fixed" it would be
# writing decisions nobody made. Only a doc the agent wrote itself is fixed
# (proactive-after-writing-doc).
rdd_check_read_only() {
  check_eq "used neither Edit nor Write" "0" "$(rdd_writes)"
  check_eq "left the tree as it was" "" "$(git status --porcelain)"
  check_eq "committed nothing" "0" "$(git rev-list --count eval-base..HEAD)"
}

# rdd_check_requested <ja|en> <path regex>
# The checks every case shares whose review was asked for: a report the user
# sees, naming the doc, in the doc's language, with the prose handed to
# lint-docs when it is Japanese, from a run that changed nothing and was
# refused nothing. lint-docs started this way only inspects: the doc is not
# one the agent wrote.
rdd_check_requested() {
  check "reported under the review heading, naming the doc" rdd_has_heading "$(rdd_report)" "$2"
  check "ranks findings under priority headings, not inline" rdd_ranks_under_headings "$(rdd_report)"
  rdd_check_language "$1" "$(rdd_report)"
  rdd_check_lint "$1"
  rdd_check_read_only
  check_eq "no command was refused" "0" "$(transcript_denials)"
}

# rdd_skill_index
# Record index of the first call of the skill; empty when it never started.
rdd_skill_index() {
  transcript_skill_rounds review-design-doc | jq -s '.[0].index // empty'
}

# rdd_write_indexes <path regex>
# Record indexes of every Write or Edit of a file matching the regex, in
# order. Real runs record absolute paths, so the regex should not anchor at ^.
rdd_write_indexes() {
  jq -s -r --arg re "$1" '
    to_entries[]
    | select(.value.type == "assistant")
    | select([ .value.message.content[]?
               | select(.type == "tool_use" and (.name == "Write" or .name == "Edit"))
               | .input.file_path // "" | test($re) ] | any)
    | .key
  ' "$SKILL_EVAL_TRANSCRIPT"
}

# rdd_started_after_writing <path regex>
# The skill started once the doc existed: after the first Write or Edit of it.
rdd_started_after_writing() {
  local skill_at write_at
  skill_at="$(rdd_skill_index)"
  write_at="$(rdd_write_indexes "$1" | head -n 1)"
  [ -n "$skill_at" ] && [ -n "$write_at" ] && [ "$skill_at" -gt "$write_at" ]
}
