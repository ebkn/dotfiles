#!/bin/bash
#
# Base state: calc.sh with no helpers yet, a passing suite, and a fresh
# branch. The prompt asks for five helpers, each implementation and tests in
# one commit — five commits inside one request, every one of them changing
# what the tests assert.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../../../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-test/evals/lib.sh"

review_test_fixture_init

# The helpers the prompt asks for do not exist yet, so the run writes them:
# calc.sh starts empty except for a load shim, keeping the first commit's
# tests trivial and the suite green throughout.
cat >calc.sh <<'CALC'
#!/bin/bash
# calc.sh — small number helpers, added behavior by behavior.
CALC
chmod +x calc.sh
skill_eval_init_repo
git checkout -q -b five-helpers
