#!/bin/bash
set -eo pipefail

# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/session-summary/evals/lib.sh"
summary_eval_docs_branch
