#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

result="$(transcript_result_text)"

check_match "reports under a test-review heading" 'テストレビュー|[Tt]est review' "$(cat "$SKILL_EVAL_TRANSCRIPT")"
check_llm "raises no P1 against tests that cover the contract" \
  'The text reports a test review of tests that already cover the contract. It passes if the review raises no P1 -- either the P1 section is absent, or it says explicitly that nothing meets the P1 criteria. Findings at P2 or P3 are fine and do not fail this. It fails if any finding is presented as P1.' \
  "$result"

check_eq "never called Write" 0 "$(transcript_tool_uses Write)"
check_eq "never called Edit" 0 "$(transcript_tool_uses Edit)"
check_eq "left the working tree untouched" "" "$(git status --porcelain)"
check_eq "made no commit" 0 "$(git rev-list --count eval-base..HEAD)"

skill_eval_finish
