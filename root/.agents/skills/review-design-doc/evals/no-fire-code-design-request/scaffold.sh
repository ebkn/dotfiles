#!/bin/bash
#
# The webhook doc on main, then a feature branch whose one commit adds
# lib/slug.sh and touches no doc.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja
git switch -q -c feat/slug
rdd_write_slug_module
git add lib/slug.sh
git commit -q -m "feat: add slugify"
