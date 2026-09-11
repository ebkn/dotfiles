#!/bin/bash
#
# A fixture with no test file at all. The prompt asks for tests to be written
# and never mentions a review, so what is measured is whether the skill starts
# by itself afterwards ("## When to start") and how far the loop that follows
# runs ("## After the review").
#
# Unlike the other two cases this one writes. Write / Edit / Skill are opened
# in prompt.md's frontmatter, for the scenario around the skill; the skill's own
# allowed-tools are untouched.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/lib.sh"

review_test_fixture_init

skill_eval_init_repo
