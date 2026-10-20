#!/bin/bash
#
# The grader of fires-on-trigger-phrase, unchanged: one grader for the pair,
# so a difference in their results is the wording's.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/fires-on-trigger-phrase/assert.sh"
