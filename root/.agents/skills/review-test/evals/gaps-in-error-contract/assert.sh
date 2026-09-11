#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

result="$(transcript_result_text)"

# --- the finding this case exists for ---
check_match "reports under a test-review heading" 'テストレビュー|[Tt]est review' "$(cat "$SKILL_EVAL_TRANSCRIPT")"
check_llm "P1 names the untested error contract" \
  'The text reports a test review and lists, as P1, that the failure behaviour of parse_quantity or sum_quantities is untested -- rejecting empty, non-numeric or negative input, the non-zero exit status, the message on stderr, or the promise of no partial sum. It fails if the review raises no P1 at all, or if its P1 items are only about naming, structure or style.' \
  "$result"

# --- the boundary: the skill reads, it does not write ---
# These hold even though the runner would allow an edit (--permission-mode
# acceptEdits): the restraint has to come from the skill body, since a host
# that ignores allowed-tools is exactly the case the body is written for.
check_eq "never called Write" 0 "$(transcript_tool_uses Write)"
check_eq "never called Edit" 0 "$(transcript_tool_uses Edit)"
check_eq "left the working tree untouched" "" "$(git status --porcelain)"
check_eq "made no commit" 0 "$(git rev-list --count eval-base..HEAD)"

skill_eval_finish
