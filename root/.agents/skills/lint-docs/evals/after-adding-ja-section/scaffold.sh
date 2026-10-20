#!/bin/bash
#
# The fixture of fires-on-trigger-phrase, unchanged: docs/ops.md is the
# existing Japanese document the section goes into.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/fires-on-trigger-phrase/scaffold.sh"
