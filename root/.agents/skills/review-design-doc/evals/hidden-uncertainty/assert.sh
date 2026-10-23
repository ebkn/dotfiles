#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

rdd_check_requested ja 'webhook-retry\.md'
rdd_check_flags "P1/P2: open decisions are buried while the doc claims none" \
  "decisions that are still open are buried in the body -- the retry interval or attempt limit being TBD, whether 4xx is retried, or whether the payload is copied -- while the open-questions section says there are none, so they should be listed as open questions or decided."

skill_eval_finish
