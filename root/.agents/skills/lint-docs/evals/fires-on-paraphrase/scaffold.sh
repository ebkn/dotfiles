#!/bin/bash
#
# The fixture of fires-on-trigger-phrase, unchanged: the pair differs only in
# how the request is worded.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/fires-on-trigger-phrase/scaffold.sh"
