#!/bin/bash
#
# The same module, shipped with tests that cover the whole documented contract.
# The skill says P1 is an absolute criterion and that good tests need no P1
# manufactured for them; this case is the other half of gaps-in-error-contract,
# which a review that always finds a P1 would pass on its own.
#
# No tool is opened for this one. Fixing a P2 here would be legitimate, and the
# runner permits an edit regardless (--permission-mode acceptEdits), but nothing
# the case measures needs to commit, so git stays out.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/lib.sh"

review_test_fixture_init
review_test_write_thorough_test

skill_eval_init_repo
