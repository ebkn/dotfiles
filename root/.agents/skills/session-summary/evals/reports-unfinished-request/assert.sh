#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/session-summary/evals/grading.sh"

summary="$(transcript_result_text)"
SKILL_EVAL_JUDGE_MODEL="${SKILL_EVAL_JUDGE_MODEL:-sonnet}"

check_eq "started session-summary once" "1" "$(transcript_skill_uses session-summary)"
summary_eval_check_read_only
check_match "names README.md" 'README' "$summary"

# What the message must find from git, not from the prompt: the prompt says
# neither is a problem.
check_llm "says the README part of the request was not done" \
  "The text is a closing report for finished work, possibly in Japanese. The user asked for JSON output from tally.sh and for its usage to be written in the Usage section of README.md. No commit changed README.md. It passes only if the text says plainly that the README part was not done -- that Usage in README.md does not document --json. It fails if it says or implies the README was updated, or does not mention the README part at all." \
  "$summary"
check_llm "warns that piping into tally.sh now fails" \
  "The text is a closing report for finished work, possibly in Japanese. The user runs tally.sh from their own scripts as generate-report | ./tally.sh, with no file argument, so it reads standard input. A change made beyond the request now exits with a usage error when no file is given, which breaks that use. It passes only if the text tells the user that running tally.sh with no file -- piping into it -- now fails, or that their piped use is affected. It fails if it presents the usage error only as a fix for a hang and never says what it breaks." \
  "$summary"
summary_eval_check_accurate

skill_eval_finish
