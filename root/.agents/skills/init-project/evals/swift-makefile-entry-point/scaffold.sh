#!/bin/bash
#
# An empty git repository. For a scaffolding skill the fixture is the absence of
# everything it creates, so there is nothing here but the toolchain stubs and
# the eval-base tag.
#
# Order matters: the stubs are written *after* skill_eval_init_repo, because
# bin/ must stay untracked. The runner adds it to .git/info/exclude only once
# this script has finished, so anything created before the init commit would be
# committed into the fixture and show up as the user's own work.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/init-project/evals/lib.sh"

skill_eval_init_repo

init_project_write_toolchain_stubs
