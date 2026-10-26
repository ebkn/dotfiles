#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- the question was answered ---
# tally.sh passes no file to wc, which then reads stdin.
check_match "answers that wc reads standard input" '(標準入力|stdin|standard input)' "$(transcript_result_text)"
check_eq "changed nothing" "" "$(git status --porcelain)"
check_eq "committed nothing" "$(git rev-parse eval-base)" "$(git rev-parse HEAD)"

# --- not starting ("## When to start") ---
check_eq "did not start session-summary for an answered question" "0" \
  "$(transcript_skill_uses session-summary)"

skill_eval_finish
