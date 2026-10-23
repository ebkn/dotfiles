#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

report="$(rdd_report)"
open="$(rdd_open_text "$report")"

rdd_check_requested 'cache-ttl\.md'
check_eq "raised no P1" "0" "$(rdd_count "$report" P1)"
# A P2 is allowed, as long as it is about this change. With nothing under P1
# or P2 there is nothing to judge, and the case has passed on that count.
if [ -z "$(printf '%s' "$open" | tr -d '[:space:]')" ]; then
  check "asked for no section the change does not need" true
else
  check_llm "asked for no section the change does not need" \
    "The text is the P1 and P2 findings of a review of a one-page design document for a small change: extending a price-list cache TTL from 5 minutes to 1 hour, with a purge on update and a one-setting rollback. It passes only if every finding names a concrete risk or gap in this specific change. It fails if any finding asks to add a section or plan -- security, privacy, goals and non-goals, milestones, monitoring, a test plan, a rollout plan, or similar -- because the document lacks it, without naming what in this change could go wrong that the section would address." \
    "$open"
fi

skill_eval_finish
