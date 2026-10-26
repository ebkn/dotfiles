#!/bin/bash
#
# A finished branch, as summary_eval_finished_branch builds it: the request
# lives only in the prompt, the work only in git. The case grades the message
# itself -- every section the skill promises, and nothing taken from main.
set -eo pipefail

# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/session-summary/evals/lib.sh"
summary_eval_finished_branch
