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
# reported. Any `#` level, bold, or neither, since the model varies how it sets
# the line.
#
# Two engines read it: jq over the whole text (rdd_has_heading), which is what
# `(^|\n)` is for, and awk a line at a time (rdd_review_part). Keep it to the
# syntax both share, POSIX ERE: no `\s`, `(?:`, or `\p{}`, which jq accepts and
# awk rejects or reads otherwise. Its one class holding a multibyte character,
# `[:：]` at the end, still matches `：` under the C locale, by its first byte.
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
# The lines under that priority's heading, up to the next heading at its
# level or above, or one naming a priority.
#
# Read wide on purpose. The clean cases grade "no P1" on this, so a P1 the
# parser misses is a false alarm graded clean: a heading is any `#` line, and
# it is that priority's when the label appears in it as a word (`### 🔴 P1`,
# `### 重大 (P1)`). A bold-only line is a heading only when it is the bare
# label (`**P1**`, `**P1:**`, RDD_BOLD_HEADING). Any other bold line is a
# finding's title and stays in the section: taking every bold line for a
# heading closed the P1 section at its own finding on a real run. Every other
# bold shape that names a priority fails rdd_ranks_under_headings instead, so
# it is never a P1 read as none. The cost, pinned in assert.test.sh, is that a
# bold label such as `**著者への質問**` after P1 reads as part of P1 -- a false
# alarm on a clean doc, not a missed P1. Every non-blank line in a section is
# kept, bullet or paragraph.
#
# The one line dropped is an item that says there is nothing and nothing more
# ("なし", "- None."). "なし。ただし…" or "None of the goals …" is a finding
# and stays.
#
# This differs on purpose from transcript_skill_rounds' open_findings, which
# the runner prints as `round: open=N` for every skill: that reader takes only
# label-first headings, treats a section opening with "なし…" as closed, and
# reads the Skill's tool_result rather than the final response. For a
# requested review its number is informational and this reader decides the
# grade; for the proactive pair it is what review_loop_checks grades the loop
# on, which is why evals/README.md asks SKILL.md for label-first headings.
# Widening it instead would change review-test's and review-design's grading.

# rdd_digits <P1|P2|P3>
# The spellings of that priority's digit, as alternatives. The one home of
# the digits every label pattern takes, as rdd_label is of the letters.
# RDD_BOLD_HEADING spells its own ASCII `P[123]` on purpose (see there); a
# spelling added here does not reach it, and a bold label it rejects fails
# the contract rather than going unread.
rdd_digits() {
  case "$1" in
    P1) printf '1|１' ;;
    P2) printf '2|２' ;;
    P3) printf '3|３' ;;
    *) return 1 ;;
  esac
}

# rdd_label <digit alternatives>
# The pattern of a priority label as a word: P, p, Ｐ or ｐ before one of the
# digits given (rdd_digits). Literal alternatives, never a class holding a
# multibyte character, so the locale does not decide; the boundary class is
# ASCII for the same reason.
rdd_label() {
  printf '(^|[^A-Za-z0-9])(P|p|Ｐ|ｐ)(%s)([^0-9]|$)' "$1"
}

# Any priority, in any spelling.
RDD_LABEL="$(rdd_label "$(rdd_digits P1)|$(rdd_digits P2)|$(rdd_digits P3)")"

# Indentation before a heading: a space or a literal tab, never [[:space:]],
# which takes in U+3000 under a UTF-8 locale -- and in macOS grep but not its
# awk, so the two readers below would disagree about the same line.
RDD_INDENT=$'[ \t]*'

# The bold-only line rdd_section takes for a priority heading. ASCII alone, so
# what it matches does not change with the locale (a full-width bracket or
# colon in a bracket expression does). Shared with rdd_ranks_under_headings,
# which fails every other bold shape naming a priority.
RDD_BOLD_HEADING="^$RDD_INDENT"'\*\*P[123]:?\*\*:?'"$RDD_INDENT"'$'

# Inside an open section, a heading deeper than the one that opened it is
# its content, whatever it names: a finding written as a sub-heading
# (`### P1` then `#### タイトル`, or `#### P2 との境界`) stays in it. Under a
# bold label, which has no level, a `#` heading stays in it unless it names a
# priority. Otherwise a heading naming this priority (rdd_label) opens the
# section and any other heading closes it.
rdd_section() {
  local digits
  digits="$(rdd_digits "$2")" || return 1
  printf '%s\n' "$1" | bold="$RDD_BOLD_HEADING" heading="^$RDD_INDENT#" any="$RDD_LABEL" \
    me="$(rdd_label "$digits")" awk '
    BEGIN { any = ENVIRON["any"]; me = ENVIRON["me"] }
    $0 ~ ENVIRON["heading"] || $0 ~ ENVIRON["bold"] {
      isbold = ($0 ~ ENVIRON["bold"])
      if (!isbold) { match($0, /#+/); lvl = RLENGTH }
      if (sec && !isbold && (sbold ? $0 !~ any : lvl > slvl)) { print; next }
      sec = ($0 ~ me)
      if (sec) { sbold = isbold; slvl = lvl }
      next
    }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*([-*][[:space:]]+)?(なし|該当なし|ありません|指摘なし|None|none|No findings|N\/A)[。.]?[[:space:]]*$/ { next }
    sec { print }
  '
}

# rdd_ranks_under_headings <report>
# No priority is written where rdd_section cannot see it. rdd_section reads
# priorities from headings alone, so a finding ranked anywhere else is unseen
# -- and on a clean doc an unseen P1 grades as none. So outside `#` headings
# and the bare bold label, any whole-word P1, P2 or P3 fails: a list item, a
# table cell, a bracket, an emoji or a label at the end of a line alike. A
# priority heading with nothing under it fails too (rdd_has_empty_priority).
#
# Five rounds of review each found ranked shapes a rule listing shapes had
# missed (`🔴 P1`, `（P1）`, `- … [P1]`, a full-width indent); only a rule with
# no shapes in it closes that. The cost, pinned in assert.test.sh, is that
# prose cannot name a priority ("上の P2 で指摘した"): SKILL.md tells the
# review to refer to a finding by its title. The label is RDD_LABEL, in any
# case and width.
RDD_INLINE_RANK="$RDD_LABEL"
rdd_ranks_under_headings() {
  local body
  # Filtered first, not piped into grep -q: its early exit can kill the
  # writer, and under pipefail that would read as "nothing found".
  body="$(printf '%s\n' "$1" | grep -vE "^$RDD_INDENT#|$RDD_BOLD_HEADING" || true)"
  ! grep -qE "$RDD_INLINE_RANK" <<<"$body" && ! rdd_has_empty_priority "$1"
}

# rdd_has_empty_priority <report>
# A priority heading closed by the next heading with no line under it.
# SKILL.md drops an empty section, and a kept one says "なし", so an empty one
# means its finding went into the heading that closed it (`### P1` then
# `### ロールバックが無い`) -- a heading no reader takes as P1's. A heading
# rdd_section keeps inside the section (a deeper one, or a plain one under a
# bold label) is content, as it is there.
rdd_has_empty_priority() {
  printf '%s\n' "$1" | bold="$RDD_BOLD_HEADING" heading="^$RDD_INDENT#" label="$RDD_LABEL" awk '
    $0 ~ ENVIRON["heading"] || $0 ~ ENVIRON["bold"] {
      isbold = ($0 ~ ENVIRON["bold"])
      if (!isbold) { match($0, /#+/); lvl = RLENGTH }
      if (open && !isbold && (obold ? $0 !~ ENVIRON["label"] : lvl > olvl)) { open = 0; next }
      if (open) found = 1
      open = ($0 ~ ENVIRON["label"])
      if (open) { obold = isbold; olvl = lvl }
      next
    }
    /^[[:space:]]*$/ { next }
    { open = 0 }
    END { exit !(found || open) }
  '
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
    # shellcheck disable=SC2034  # exit read by skill_eval_finish's exit
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

# rdd_labels_translated <text>
# None of SKILL.md's English template labels stands as a label: a report
# heading, a section heading, or a finding's "Why it matters:"/"Suggestion:".
# rdd_is_japanese counts words, so Japanese findings under English labels pass
# it -- the shape three of five reviews of real Japanese docs took. Read wide
# at the start of a line, since a model drifting from the template drifts in
# shape too: with or without a list marker (numbered included) or bold, a
# trailing colon or words after a section name. A section name needs a `#` or
# bold in front, so a bare line that happens to say "Checked" is prose. A
# label quoted -- inside a sentence, in code, a `>` line or a fenced block --
# or the Caller line (English on purpose), is not one. A fence opens and
# closes on a line of its own that starts with ``` or ~~~, so inline code
# inside a block, or a ``` mentioned mid-line, moves no boundary. jq, not
# grep, so the case folding holds in any locale.
rdd_labels_translated() {
  jq -nre --arg t "$1" '
    [foreach ($t | split("\n"))[] as $l ({fenced: false, line: null};
        if ($l | test("^[ \t]*(```|~~~)")) then {fenced: (.fenced | not), line: null}
        elif .fenced then {fenced: true, line: null}
        else {fenced: false, line: $l} end;
        .line // empty)]
    | any(.[];
        test("^[ \t]*(#+[ \t]*)?(\\*\\*)?design doc(ument)? review[ \t]*(\\*\\*)?[ \t]*[:：]"; "i")
        or test("^[ \t]*(#+[ \t]*(\\*\\*)?|\\*\\*)(the decision|questions for the author|decisions the doc leaves open|checked)\\b"; "i")
        or test("^[ \t]*([-*+][ \t]+|[0-9]+[.)][ \t]+)?(#+[ \t]*)?(\\*\\*)?(why it matters|suggestion)[ \t]*(\\*\\*)?[ \t]*([:：]|$)"; "i"))
    | not
  ' >/dev/null
}

# rdd_check_language <ja|en> <report>
# The review answers in the doc's language. Every Japanese case's doc is
# Japanese, whatever the request was written in (answers-in-doc-language asks
# in English); the English cases' are English.
rdd_check_language() {
  case "$1" in
    ja)
      check "answered in Japanese, the doc's language" rdd_is_japanese "$2"
      check "wrote the report's labels in Japanese too" rdd_labels_translated "$2"
      ;;
    en) check "wrote no Japanese into an English review" rdd_has_no_kana "$2" ;;
    # Fail closed: a typo or a call without the language would otherwise
    # skip the check and pass.
    *) check "language is ja or en, not '$1'" false ;;
  esac
}

# rdd_lint_after_review
# lint-docs started after the last round of the review. The review leaves the
# readability of Japanese prose to lint-docs rather than ranking it next to
# missing decisions, and lints the text the review is done changing. With no
# review there is nothing to be after, so it fails: a run started by slash
# command records no Skill call of the review, but under `claude -p` such a
# run ends with the fork's report and never reaches lint-docs anyway, which is
# why no case starts that way (evals/README.md).
rdd_lint_after_review() {
  local last
  last="$(transcript_skill_rounds review-design-doc | jq -s 'last.index // empty')"
  [ -n "$last" ] || return 1
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
    *) check "language is ja or en, not '$1'" false ;;
  esac
}

# rdd_every_round_japanese
# Every round's report, as the forked review handed it back, is Japanese,
# labels included: each is the review's own words, whatever language the
# caller then writes its summary in, and a round in the wrong language is one
# the user may be shown. False with no round at all.
rdd_every_round_japanese() {
  local rounds n k r
  rounds="$(transcript_skill_rounds review-design-doc)"
  n="$(jq -s 'length' <<<"$rounds")"
  [ "$n" -gt 0 ] || return 1
  for ((k = 0; k < n; k++)); do
    r="$(jq -rs --argjson k "$k" '.[$k].report' <<<"$rounds")"
    rdd_is_japanese "$r" || return 1
    rdd_labels_translated "$r" || return 1
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
# one the agent wrote. Heading and language are read off the final response,
# which with lint-docs after the review puts the report after lint-docs
# (evals/README.md). The skill must have run: asked for in words, a model can
# write a review of its own, and that would grade like the skill's.
rdd_check_requested() {
  check "started review-design-doc" test "$(transcript_skill_uses review-design-doc)" -ge 1
  check "reported under the review heading, naming the doc" rdd_has_heading "$(rdd_report)" "$2"
  check "ranks findings under priority headings, not inline" rdd_ranks_under_headings "$(rdd_review_part "$(rdd_report)")"
  rdd_check_language "$1" "$(rdd_report)"
  rdd_check_lint "$1"
  rdd_check_read_only
  check_eq "no command was refused" "0" "$(transcript_denials)"
}

# rdd_review_part <report>
# The review's part of the final response: from the first review heading on,
# without lint-docs' own section. The caller's message carries lint-docs'
# findings too, and they cite the review's priorities ("レビューの P2「…」と
# 同じ問題" on real runs; SKILL.md lets them), which is not a ranking.
#
# Above the first review heading is the caller's, with or without lint-docs'
# heading. A report with no review heading leaves nothing here and fails
# "reported under the review heading" instead.
#
# Below it, lint-docs' section runs from the heading lint-docs fixes
# (`## ドキュメント検査: …`, its SKILL.md) to the next heading at its level or
# above, or a review heading (RDD_REPORT_HEADING), however set. The limit,
# pinned in assert.test.sh: prose after lint-docs' findings with no heading of
# its own reads as lint-docs'. Colons as alternatives, not a class, so the
# locale does not decide.
rdd_review_part() {
  printf '%s\n' "$1" | review="$RDD_REPORT_HEADING" awk '
    !seen && $0 !~ ENVIRON["review"] { next }
    { seen = 1 }
    /^#+[ \t]*ドキュメント検査[ \t]*(:|：)/ { match($0, /#+/); llvl = RLENGTH; lint = 1; next }
    lint && $0 ~ ENVIRON["review"] { lint = 0 }
    lint && /^[ \t]*#/ { match($0, /#+/); if (RLENGTH <= llvl) lint = 0 }
    !lint { print }
  '
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
