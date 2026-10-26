#!/bin/bash
#
# Discussion notes in docs/notes/, and no docs/design/ yet: the run writes the
# doc, and the review has to come after that.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_write_notes_ja docs/notes/webhook-retry.md
skill_eval_init_repo
