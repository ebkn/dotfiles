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
# True when the run counted the word in the project -- step 4's measurement --
# through rg/grep on the shell or through the Grep tool. A count that never
# happened cannot back a "the dictionary agrees" claim, however the report
# words it.
lint_docs_measured() {
  if transcript_commands | grep -E '(^|[^[:alnum:]_])(rg|grep)( |$)' | grep -qF "$1"; then
    return 0
  fi
  jq -s -e --arg w "$1" '
    [ .[]
      | select(.type == "assistant")
      | .message.content[]?
      | select(.type == "tool_use" and .name == "Grep")
      | .input.pattern // ""
      | select(contains($w)) ]
    | length > 0
  ' "$SKILL_EVAL_TRANSCRIPT" >/dev/null
}

# lint_docs_writes
# Edit and Write calls together: the skill's default is inspection only.
lint_docs_writes() {
  echo $(($(transcript_tool_uses Edit) + $(transcript_tool_uses Write)))
}
