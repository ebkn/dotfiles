#!/bin/bash
#
# The module ships with tests that only exercise the success path, so the
# documented refusals -- status 1, the message on stderr, no partial sum -- are
# untested. That is a P1 by the skill's own criteria, and finding it is what
# this case measures.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/lib.sh"

review_test_fixture_init
review_test_write_happy_path_test

skill_eval_init_repo
