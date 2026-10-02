#!/bin/bash
#
# A unit of work whose whole point, says its commit, is a layer in front of
# quantity.sh -- and the layer forwards everything and hides nothing. The
# review should name it shallow, but removing it undoes what the commit set out
# to do, so that fix is the author's call: measured is whether the review asks
# instead of deleting, and does not "fix" the layer by copying quantity.sh's
# contract into it.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
skill_eval_init_repo

review_design_begin_unit feature/ticket-api
review_design_unit_intended_layer
review_design_commit_unit "feat: put a ticket API in front of quantity.sh" \
  "So that the scripts stop depending on how quantity.sh reads a weight. total.sh now goes through it."
