#!/bin/bash
#
# The fixture of fires-on-trigger-phrase, unchanged: docs/ops.md is Japanese,
# so the edit is to a document the skill would check if asked.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/fires-on-trigger-phrase/scaffold.sh"
