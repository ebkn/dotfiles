#!/bin/bash
#
# A short Japanese README beside the webhook doc.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/lib.sh"

cat >README.md <<'DOC'
# webhook-relay

顧客のエンドポイントへイベントを配信するサービス。設計は docs/design/ にある。
DOC
rdd_scaffold ja
