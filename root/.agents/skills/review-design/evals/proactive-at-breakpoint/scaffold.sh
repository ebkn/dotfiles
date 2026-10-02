#!/bin/bash
#
# The base state on main, and a fresh feature branch with nothing on it yet.
# The prompt asks for a new command-line flag -- an interface -- with tests and
# a commit, and never mentions a review. What is measured is whether the skill
# starts by itself at that breakpoint ("## When to start"), after the work is
# committed rather than in the middle of it. no-fire-small-fix is its pair:
# the same shape of request for a fix that changes no interface.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
skill_eval_init_repo

review_design_begin_unit feature/kg-output
