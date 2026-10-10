#!/bin/bash
#
# The fixture of proactive-after-writing-tests, unchanged: the pair differs only
# in the CLAUDE.md prompt.md brings in.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/proactive-after-writing-tests/scaffold.sh"
