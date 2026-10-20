#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

# The whole measurement: asked to check a Japanese doc without the skill's
# name, the Skill tool started lint-docs.
check "started lint-docs without being named" test "$(transcript_skill_uses lint-docs)" -ge 1
# Started and then ignored would pass the line above alone.
check "ran textlint-docs on docs/guide.md" lint_docs_ran_on 'docs/guide\.md'
check_eq "used neither Edit nor Write" "0" "$(lint_docs_writes)"
check_eq "left the tree as it was" "" "$(git status --porcelain)"

skill_eval_finish
