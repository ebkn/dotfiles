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
# count, in one of the two shapes every real run used: `3 件`, or a ratio
# whose second side may name the word again (`サーバー 3 : サーバ 1`,
# `3：1`). Positive shapes rather than "a digit that is not a
# location": blocklisting locations leaked each one not yet listed (a line
# number after the word, list and heading numbers, `L3`, ranges). A ratio
# is told from a location by its spaces or full-width colon, which textlint's
# `path:3:5` never has. What it rejects on purpose: `サーバー 3、サーバ 1`
# and full-width digits -- a real count graded FAIL is visible in
# assert.log, a location graded PASS is not.
lint_docs_reports_count() {
  printf '%s\n' "$1" | grep 'サーバ' |
    grep -qE '[0-9]+ ?件|[0-9]+ : ([^ 0-9]+ )?[0-9]+|[0-9]+ ?： ?([^ 0-9：]+ ?)?[0-9]+'
}

# lint_docs_started_after_writing <path regex>
# "## いつ起動するか": the skill starts at the breakpoint, once the document has
# been written -- by Write for a new one, by Edit for a rewritten section. True
# when the first Skill call of lint-docs comes after the first Write or Edit of
# a file matching the regex. Tied to the file, since a Write of something else
# before the skill does not make it the breakpoint.
lint_docs_started_after_writing() {
  local skill_at write_at
  skill_at="$(transcript_skill_rounds lint-docs | jq -s '.[0].index // empty')"
  write_at="$(jq -s --arg re "$1" '
    [ to_entries[]
      | select(.value.type == "assistant")
      | select([ .value.message.content[]?
                 | select(.type == "tool_use" and (.name == "Write" or .name == "Edit"))
                 | .input.file_path // "" | test($re) ] | any)
      | .key ]
    | first // empty
  ' "$SKILL_EVAL_TRANSCRIPT")"
  [ -n "$skill_at" ] && [ -n "$write_at" ] && [ "$skill_at" -gt "$write_at" ]
}

# lint_docs_writes
# Edit and Write calls together: the skill's default is inspection only.
lint_docs_writes() {
  echo $(($(transcript_tool_uses Edit) + $(transcript_tool_uses Write)))
}
