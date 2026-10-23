#!/bin/bash
#
# The grader of proactive-after-writing-doc, unchanged: one grader for the
# pair, so a difference in their results is the CLAUDE.md's and not a drift
# between two copies.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/proactive-after-writing-doc/assert.sh"
