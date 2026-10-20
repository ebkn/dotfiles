#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/grading.sh"

report="$(transcript_result_text)"

# The whole measurement: the request was carried out without the skill.
check_eq "did not start lint-docs for an English document" "0" "$(transcript_skill_uses lint-docs)"
check "did not run textlint-docs" lint_docs_never_ran_on '.'
# A run that refused or did nothing would pass the two lines above.
check_match "answered about README.md" 'README|sentence|文' "$report"
check_eq "left the tree as it was" "" "$(git status --porcelain)"

skill_eval_finish
