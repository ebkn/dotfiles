# grading.sh — the checks the lint-docs cases share. Sourced from an assert.sh
# after skill-eval-assert.sh.
#
# shellcheck shell=bash

# The textlint-docs calls of the run, one per line. Matched as a word anywhere
# in the command, so `bin/textlint-docs ...` and a call after `cd` both count:
# what matters is which files reached the tool, not how it was spelled.
lint_docs_tool_calls() {
  transcript_commands | grep -E '(^|[^[:alnum:]_-])textlint-docs( |$)' || true
}

# lint_docs_ran_on <regex>
# True when some textlint-docs call names a path matching the regex.
lint_docs_ran_on() {
  lint_docs_tool_calls | grep -qE "$1"
}

# lint_docs_never_ran_on <regex>
lint_docs_never_ran_on() {
  ! lint_docs_ran_on "$1"
}

# lint_docs_ran
lint_docs_ran() {
  [ -n "$(lint_docs_tool_calls)" ]
}

# lint_docs_measured <word>
# True when the run counted the word across the project -- step 4's
# measurement -- through rg/grep on the shell or through the Grep tool. A
# count that never happened cannot back a "the dictionary agrees" claim,
# however the report words it.
#
# Two searches look like one and are not: a grep over textlint-docs' own
# output (the finding, not the project), and a search of a single .md file
# (the target, not the project). So a shell search counts only without
# textlint-docs on the line and without a .md path as an argument -- the
# documented `rg ... -g '*.md' .` passes, `rg サーバ docs/new.md` does not. A
# Grep call counts without a `path`, or with one that is not a .md file.
lint_docs_measured() {
  if transcript_commands |
    grep -E '(^|[^[:alnum:]_])(rg|grep)( |$)' |
    grep -vE 'textlint-docs' |
    grep -vE '[^*[:space:]"'\'']+\.md(["'\'']?)( |$)' |
    grep -qF "$1"; then
    return 0
  fi
  jq -s -e --arg w "$1" '
    [ .[]
      | select(.type == "assistant")
      | .message.content[]?
      | select(.type == "tool_use" and .name == "Grep")
      | select((.input.path // "") | test("\\.md$") | not)
      | .input.pattern // ""
      | select(contains($w)) ]
    | length > 0
  ' "$SKILL_EVAL_TRANSCRIPT" >/dev/null
}

# lint_docs_read_diff_after_edit
# Step 5.4: the diff is read after the last Edit, since prh is a regex
# replacement that can reach past the finding. A diff read before the fix --
# while checking the tree at step 5.1 -- says nothing about what the fix did.
# Any spelling of `git ... diff` counts.
lint_docs_read_diff_after_edit() {
  local last_edit last_diff
  last_edit="$(jq -s '
    [ to_entries[]
      | select(.value.type == "assistant")
      | select([ .value.message.content[]? | select(.type == "tool_use" and (.name == "Edit" or .name == "Write")) ] | length > 0)
      | .key ]
    | last // empty
  ' "$SKILL_EVAL_TRANSCRIPT")"
  last_diff="$(transcript_command_indexes '^git( [^ ]+)* diff( |$)' | tail -n 1)"
  [ -n "$last_diff" ] && { [ -z "$last_edit" ] || [ "$last_diff" -gt "$last_edit" ]; }
}

# lint_docs_reports_count <report>
# Step 4: "実測結果は報告に数値付きで含める". A line naming サーバ carries a
# count -- `3 : 1`, `3 件` -- not merely a location. Rather than listing
# every spelling of a count, the locations are removed -- `3 行目`, `3 行`,
# textlint's `path:3:5`, a bare `3:5` -- and whatever digit is left is one.
# A ratio survives because it is spaced (`3 : 1`) or full-width (`3：1`); a
# location never is.
lint_docs_reports_count() {
  printf '%s\n' "$1" | grep 'サーバ' |
    sed -E 's/[0-9]+ ?行目?//g; s/[0-9]+(:[0-9]+)+//g; s/:[0-9]+//g' |
    grep -qE '[0-9]'
}

# lint_docs_writes
# Edit and Write calls together: the skill's default is inspection only.
lint_docs_writes() {
  echo $(($(transcript_tool_uses Edit) + $(transcript_tool_uses Write)))
}
