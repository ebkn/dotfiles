#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# --- the rewording happened ---
check_match "the rewording is in" \
  '再送間隔を指数的に広げる方法' "$(cat docs/design/webhook-retry.md)"
check_not_match "the old wording is not kept beside it" '指数バックオフ' \
  "$(cat docs/design/webhook-retry.md)"
check "committed the rewording" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check "only the doc changed" test -z "$(git diff eval-base..HEAD --name-only | grep -v '^docs/design/webhook-retry\.md$')"
check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

# --- no re-review for wording (root/review-breakpoints.md) ---
# The decision: a re-round is owed by changed claims, structure or decisions.
# A reworded sentence is none of those, so the skill never starts — the
# measured difference against the per-commit behaviour that ran 55 forks.
check_eq "no review-design-doc fork for a rewording" "0" \
  "$(transcript_skill_uses review-design-doc)"

skill_eval_finish
