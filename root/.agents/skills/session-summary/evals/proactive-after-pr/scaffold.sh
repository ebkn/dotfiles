#!/bin/bash
#
# create-pr's fixture (the same stale README, a fake GitHub origin holding
# main), on docs/install with no PR yet.
set -eo pipefail

# shellcheck source=../../../create-pr/evals/lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/create-pr/evals/lib.sh"
pr_eval_scaffold docs/install
