#!/bin/bash
#
# The fixture of proactive-after-writing-tests, unchanged. The pair differs in
# the CLAUDE.md prompt.md brings in, and in the ceilings, which only a run that
# starts the skill reaches (see bin/skill-eval.md).
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/proactive-after-writing-tests/scaffold.sh"
