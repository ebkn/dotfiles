# grading.sh — what every review-design eval case reads off a run the same way.
#
# Two kinds of thing live here. What the skill's report format promises -- the
# heading that starts the report, the Reviewed line that closes it, nothing
# written before it -- is one decision, made once in SKILL.md, and a copy per
# case would drift from it. And what the shared fixture does when it skips an
# unreadable weight, which more than one case pins.
#
# Sourced by a case's assert.sh after bin/skill-eval-assert.sh, whose
# transcript_* helpers it uses. Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# The report's own heading line, not any mention of a design review: a preamble
# such as "設計レビューを始めます" must not count as having reported. The colon
# after the title is what tells the two apart. How the line is set -- a `##`
# heading or bold -- is formatting the model varies, so either is accepted.
# `(^|\n)` rather than a bare `^`: jq's `^` anchors at the start of the text
# block only, and a report may follow a sentence of preamble.
REVIEW_DESIGN_REPORT_HEADING='(^|\n)(#+ *|\*\*)?(設計レビュー|[Dd]esign [Rr]eview) *[:：]'

# Git that writes, wherever it sits in a command line, and `--output`, which
# makes even git diff and git log write a file. `merge-base` must not match
# `merge`, nor a path containing `add` match `add`.
REVIEW_DESIGN_WRITING_GIT='(^|[;&|(]|[[:space:]])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+--no-pager)*[[:space:]]+(add|am|apply|checkout|cherry-pick|commit|merge|mv|push|rebase|reset|restore|revert|rm|stash|switch)([[:space:]]|$)|git[^|;&]*--output([=[:space:]]|$)'

# review_design_report_index
# The transcript record holding the first report; empty when there is none.
review_design_report_index() {
  transcript_first_text_index "$REVIEW_DESIGN_REPORT_HEADING"
}

# review_design_report_text <index>
# The text of that record; empty for an empty index.
review_design_report_text() {
  [ -n "$1" ] || return 0
  jq -rs --argjson i "$1" \
    '.[$i].message.content[]? | select(.type == "text") | .text' "$SKILL_EVAL_TRANSCRIPT"
}

# review_design_names_range <report> <base-ref> <head-ref>
# True when the report's Reviewed line names <base-ref>..<head-ref>. The next
# review in the same conversation starts from that line, so what matters is the
# right hashes, not the shape of a range. Compared as prefixes, because the
# line carries abbreviated hashes.
review_design_names_range() {
  local line base head
  line="$(grep -oE 'Reviewed: [0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' <<<"$1" | head -n 1)"
  [ -n "$line" ] || return 1
  base="${line#Reviewed: }"
  head="${base#*..}"
  base="${base%%..*}"
  case "$(git rev-parse "$2")" in "$base"*) ;; *) return 1 ;; esac
  case "$(git rev-parse "$3")" in "$head"*) ;; *) return 1 ;; esac
}

# review_design_wrote_nothing_before <index>
# review_design_ran_no_writing_git_before <index>
# The caller writes and commits in the same run as the review, so what
# separates the skill from it is order: nothing written before the report.
# Unlike review-test this skill runs git while it reviews -- the range is its
# input -- so the line is drawn at git that writes, not at git. Both fail when
# there is no report to be before.
review_design_wrote_nothing_before() {
  [ -n "$1" ] || return 1
  if transcript_tool_uses_precede Write "$1"; then return 1; fi
  if transcript_tool_uses_precede Edit "$1"; then return 1; fi
  return 0
}

review_design_ran_no_writing_git_before() {
  local first
  [ -n "$1" ] || return 1
  first="$(transcript_first_command_index "$REVIEW_DESIGN_WRITING_GIT")"
  [ -n "$first" ] || return 0
  [ "$first" -gt "$1" ]
}

# review_design_kept_existing_tests <test file>...
# True when not a line of the given test files was removed or changed since
# the unit. SKILL.md asks that the tests of what callers see pass unchanged; a
# new test beside them -- for a function a fix extracted, say -- changes
# nothing they expect, so additions pass. A changed line is a deletion plus an
# addition in git's count, so it does not.
review_design_kept_existing_tests() {
  local removed
  removed="$(git diff --numstat unit-done -- "$@" | awk '{ s += $2 } END { print s + 0 }')"
  [ "$removed" -eq 0 ]
}

# review_design_total_of <weight>...
# What total.sh prints and exits with, as "<stdout> (status <n>)". The fixture's
# tests never feed in nothing but unreadable weights, and what that should do is
# exactly the open question a good review raises (0 and status 0 cannot be told
# apart from a real zero). Answering it in code would pass every test, so a case
# pins what the unit made it do: deciding it is the user's call.
review_design_total_of() {
  local out status=0
  out="$(./total.sh "$@" 2>/dev/null)" || status=$?
  printf '%s (status %s)' "$out" "$status"
}

# The three docs that describe unreadable weights, as one text for a judge.
review_design_skipping_docs() {
  printf -- '--- lib/quantity.sh\n%s\n\n--- total.sh\n%s\n\n--- README.md\n%s\n' \
    "$(cat lib/quantity.sh)" "$(cat total.sh)" "$(cat README.md)"
}

# shellcheck disable=SC2034  # read by the cases that source this file
REVIEW_DESIGN_SKIPPING_DOCS_RUBRIC='The text holds three files of a small project that totals weights. It passes only if the documentation in all three -- the comment above sum_quantities in lib/quantity.sh, the usage text inside total.sh, and the README prose -- says that a weight that cannot be read is skipped (or ignored, or left out) while the remaining weights are still totalled. It fails if any one of the three still says that an unreadable weight refuses or fails the total, or that nothing is printed.'
