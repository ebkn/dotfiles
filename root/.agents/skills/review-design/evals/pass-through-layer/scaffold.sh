#!/bin/bash
#
# A feature that picks up a forwarder on the way: delivery_sum only calls
# sum_quantities, and nothing about the feature asked for it -- the
# pass-through red flag. Its one caller is in the unit, so removing it reaches
# nothing outside and undoes nothing anyone decided: measured is whether the
# review names it and folds it away without asking, leaving behaviour alone,
# in a commit of its own. intended-layer-asks is its pair, where the same
# shape was the commit's purpose.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
skill_eval_init_repo

review_design_begin_unit feature/delivery-total
review_design_unit_incidental_forwarder
review_design_commit_unit "feat: add delivery.sh to total a delivery's tickets from a file" \
  "A delivery arrives as a list of ticket weights in a file. Total it in one go instead of pasting every weight onto total.sh's command line."
