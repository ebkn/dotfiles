#!/bin/bash
#
# reports-finished-branch's branch, unchanged: what differs is the request
# the prompt recalls. Usage in README.md was asked for and no commit touches
# it; the usage-error fix ends `... | ./tally.sh`, which the user relies on.
set -eo pipefail

# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/session-summary/evals/lib.sh"
summary_eval_finished_branch
