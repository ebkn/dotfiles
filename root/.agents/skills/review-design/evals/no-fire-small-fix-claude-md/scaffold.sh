#!/bin/bash
#
# Identical to no-fire-small-fix's scaffold — that is the point of the pair:
# the only difference is prompt.md's `claude_md: root/CLAUDE.md`, so the
# measured difference is the file's.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
review_design_plant_upper_case_bug
skill_eval_init_repo

review_design_begin_unit fix/upper-case-unit
