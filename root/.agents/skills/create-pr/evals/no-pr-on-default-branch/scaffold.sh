#!/bin/bash
set -eo pipefail

# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/lib.sh"
pr_eval_scaffold main
