#!/bin/bash
#
# A unit of work in which two scripts each write the unit of a total
# themselves -- fine as it stands. The prompt says what comes next: a kg
# output, which would have to edit both. Measured is the change-cost lens:
# whether the review weighs the structure against that stated change, ranks
# the scattering P1, and pulls the formatting into one place before it -- the
# one case where adding a function is justified, since the next change is the
# change it makes cheaper -- without changing a byte of output.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
skill_eval_init_repo

review_design_begin_unit feature/unit-in-output
review_design_unit_unit_suffix_twice
review_design_commit_unit "feat: print totals with their unit, and total a delivery from a file" \
  "A bare 15.5 on a ticket left the unit to guess. Print it as 15.5t, and add delivery.sh to total a delivery listed in a file."
