#!/bin/bash
#
# A unit of work that changed what sum_quantities does and left three docs --
# its comment, total.sh's usage text, the README -- describing what it used to
# do. The review is asked for explicitly. What is measured is whether it
# reports the drift as P1, fixes the docs rather than the code, and commits
# that fix on its own instead of folding it into the unit's commit.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
skill_eval_init_repo

review_design_begin_unit feature/skip-unreadable-weights
review_design_unit_skip_without_docs
review_design_commit_unit "feat: skip unreadable weights instead of refusing the total" \
  "One smudged ticket used to block the total of a whole delivery. Skip it with a warning on stderr and total the rest."
