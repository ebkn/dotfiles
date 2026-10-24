#!/bin/bash
#
# A one-page doc for a small change undone by one setting: no goals section,
# no security, privacy, milestones or monitoring, and it needs none of them.
# The failure this guards against is a checklist review that asks every doc for
# every section -- the overloaded template Larson says stops people writing
# design docs at all. Its pair is clean-doc-no-false-p1, the large doc that
# does have those sections.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_write_mini_ja docs/design/cache-ttl.md
skill_eval_init_repo
