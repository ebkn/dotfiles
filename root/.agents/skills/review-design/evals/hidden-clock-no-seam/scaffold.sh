#!/bin/bash
#
# A unit of work whose new interface reads the clock deep inside, so the date
# it promises can be checked only against the wall clock -- the testability
# lens. Docs and tests moved with the code, and every caller is in the unit:
# measured is whether the review names the missing seam and adds one without
# asking, leaving today's output as it was, in a commit of its own.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
skill_eval_init_repo

review_design_begin_unit feature/stamp-total
review_design_unit_clock_inside
review_design_commit_unit "feat: stamp each total with the day it was weighed" \
  "A ticket total means little without its date. total.sh now prints the day after the weight."
