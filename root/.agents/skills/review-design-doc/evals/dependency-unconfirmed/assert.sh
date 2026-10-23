#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

report="$(rdd_report)"

rdd_check_requested 'webhook-retry\.md'
# The whole report, not P1/P2 alone: whether the platform team agreed is a
# fact outside the doc, so a question to the author is as good an answer as a
# ranked finding -- and the better one, if the skill files it that way.
check_llm "raises whether the platform team agreed to enlarge the database" \
  "The text is a review of a software design document. It passes only if it raises -- as a finding or as a question to the author -- that the design relies on the platform team enlarging the shared database instance without saying that the platform team has agreed to it or been asked. It fails if it does not raise this, and also fails if it states as fact that the platform team has refused." \
  "$report"

skill_eval_finish
