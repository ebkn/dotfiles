#!/bin/bash
#
# Japanese docs to match the style of. The run writes a new one; whether the
# skill then checks it, unasked, is the measurement.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/fires-on-trigger-phrase/scaffold.sh"
