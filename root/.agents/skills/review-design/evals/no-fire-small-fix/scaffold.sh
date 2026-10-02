#!/bin/bash
#
# The base state with a one-character bug planted on main -- parse_quantity
# drops only a lower-case unit, though its comment promises either case -- and
# a fresh branch for the fix. The prompt asks for the fix and a commit, the
# same shape as proactive-at-breakpoint's request. The fix changes no
# interface, so the skill must not start ("## When to start"): a review after
# every small fix is the churn the trigger exists to avoid.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
review_design_plant_upper_case_bug
skill_eval_init_repo

review_design_begin_unit fix/upper-case-unit
