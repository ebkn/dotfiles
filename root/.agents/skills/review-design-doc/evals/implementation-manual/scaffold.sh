#!/bin/bash
#
# A "design doc" for the same feature that holds no decision: implementation
# steps and code, with no problem, no alternative and no trade-off. A review
# that checks it section by section would list a dozen gaps; what matters is
# the one above them all -- there is nothing here to decide on. Its pair is
# clean-doc-no-false-p1, the same feature written as a design doc.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_write_manual_ja docs/design/webhook-retry.md
skill_eval_init_repo
