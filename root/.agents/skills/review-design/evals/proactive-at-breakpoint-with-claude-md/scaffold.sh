#!/bin/bash
#
# The fixture of proactive-at-breakpoint, unchanged. The pair differs in the
# CLAUDE.md prompt.md brings in, and in the ceilings.
set -eo pipefail

exec bash "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/proactive-at-breakpoint/scaffold.sh"
