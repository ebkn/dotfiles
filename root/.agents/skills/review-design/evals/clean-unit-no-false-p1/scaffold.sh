#!/bin/bash
#
# The same unit of work as stale-doc-after-change, done properly: every doc
# moved with the code. A review of it should find nothing that meets P1, and a
# run that reports one is the false positive this case exists to catch --
# absolute criteria, not a quota of findings per priority.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
skill_eval_init_repo

review_design_begin_unit feature/skip-unreadable-weights
review_design_unit_skip_with_docs
review_design_commit_unit "feat: skip unreadable weights instead of refusing the total" \
  "One smudged ticket used to block the total of a whole delivery. Skip it with a warning on stderr and total the rest."
