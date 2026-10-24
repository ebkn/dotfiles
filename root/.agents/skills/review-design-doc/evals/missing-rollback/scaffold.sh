#!/bin/bash
#
# The webhook doc releasing to every customer at once, with no staged rollout
# and no way back -- the cross-cutting concern templates name most often
# (Google, KEP's production readiness, Squarespace) and docs leave out most
# often. Every other cross-cutting section stays, so the gap is the only one.
# clean-doc-no-false-p1 is the pair.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

rdd_scaffold ja crosscutting=norollback
