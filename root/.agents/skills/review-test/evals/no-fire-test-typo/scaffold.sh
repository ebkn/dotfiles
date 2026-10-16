#!/bin/bash
#
# Tests that already cover the contract, with a typo in one test's name. The
# fix changes no assertion, so it is the "a typo, formatting, reordered
# imports" exception in "## When to start": a review here re-reads the whole
# suite to find what the last review already found. The pair of
# proactive-with-claude-md, which measures starting; this one measures not.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/lib.sh"

review_test_fixture_init
review_test_write_thorough_test
# Through a temporary file rather than `sed -i`, which BSD and GNU spell
# differently.
sed 's/"parses a plain number"/"pases a plain number"/' lib/quantity.test.sh >lib/quantity.test.sh.new
mv lib/quantity.test.sh.new lib/quantity.test.sh

skill_eval_init_repo
