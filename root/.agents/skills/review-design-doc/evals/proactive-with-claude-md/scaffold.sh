#!/bin/bash
#
# The fixture of proactive-after-writing-doc, unchanged. The pair differs in
# the CLAUDE.md prompt.md brings in.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/proactive-after-writing-doc/scaffold.sh"
