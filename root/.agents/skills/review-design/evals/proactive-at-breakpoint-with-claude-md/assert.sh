#!/bin/bash
#
# The grader of proactive-at-breakpoint, unchanged: one grader for the pair, so
# a difference in their results is the CLAUDE.md's and not a drift between two
# copies. evals/assert.test.sh pins it through that case.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/proactive-at-breakpoint/assert.sh"
