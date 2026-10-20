#!/bin/bash
#
# A project that writes サーバ (six times, never サーバー), and docs/new.md
# with two auto-fixable findings: 予め (ja-hiragana-fukushi, section-free) and
# サーバ (prh section B, whose expected サーバー is this project's minority).
# A blind `--fix` applies both. The tree is committed and clean, so step 5.1
# has nothing to warn about and every change afterwards is the run's.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/lib.sh"

mkdir -p docs
cat >docs/ops.md <<'EOF'
# 運用

配布サーバは 2 台で構成する。

片方のサーバを止めるときは、もう片方のサーバが応答していることを確かめる。
EOF
cat >docs/setup.md <<'EOF'
# 構築

サーバを用意し、サーバに鍵を登録する。

サーバの時刻は NTP で合わせる。
EOF
cat >docs/new.md <<'EOF'
# サーバの追加

新しい配布サーバを追加する手順である。

予め鍵を登録しておく。
EOF
skill_eval_init_repo
lint_docs_link_tool
