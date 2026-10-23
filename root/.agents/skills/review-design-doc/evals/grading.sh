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
# The lines under that priority's heading, up to the next heading. A section
# that opens by saying there is nothing ("なし", "None") yields nothing, as
# transcript_skill_rounds reads it: a clean review that kept the heading is not
# one with findings.
rdd_section() {
  printf '%s\n' "$1" | awk -v p="$2" '
    /^#+/ {
      sec = ($0 ~ ("^#+[[:space:]]*" p "([^0-9]|$)"))
      first = sec
      next
    }
    /^[[:space:]]*$/ { next }
    first && /^[[:space:]]*([-*][[:space:]]+)?(なし|該当なし|ありません|指摘なし|None|none|No findings|N\/A)([。.:：、,]|[[:space:]]*$)/ {
      sec = 0
    }
    { first = 0 }
    sec { print }
  '
}

# rdd_count <report> <P1|P2|P3>
# List items under that heading.
rdd_count() {
  rdd_section "$1" "$2" | grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+' || true
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

# rdd_writes
# Edit and Write calls together.
rdd_writes() {
  echo $(($(transcript_tool_uses Edit) + $(transcript_tool_uses Write)))
}

# rdd_check_read_only
# A requested review is report-only, through the caller's part too: the doc
# records its author's decisions, and a run that "fixed" it would be writing
# decisions nobody made.
rdd_check_read_only() {
  check_eq "used neither Edit nor Write" "0" "$(rdd_writes)"
  check_eq "left the tree as it was" "" "$(git status --porcelain)"
  check_eq "committed nothing" "0" "$(git rev-list --count eval-base..HEAD)"
}

# rdd_check_requested <path regex>
# The checks every case shares whose review was asked for: a report the user
# sees, naming the doc, from a run that changed nothing and was refused
# nothing.
rdd_check_requested() {
  check "reported under the review heading, naming the doc" rdd_has_heading "$(rdd_report)" "$1"
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

# rdd_untouched_after_review <path regex>
# Nothing wrote the doc after the skill started: report-only holds for a doc
# the agent itself wrote, since what a review finds missing is a decision the
# notes did not make. False when the skill never started.
rdd_untouched_after_review() {
  local skill_at last_write
  skill_at="$(rdd_skill_index)"
  [ -n "$skill_at" ] || return 1
  last_write="$(rdd_write_indexes "$1" | tail -n 1)"
  [ -z "$last_write" ] || [ "$last_write" -lt "$skill_at" ]
}
