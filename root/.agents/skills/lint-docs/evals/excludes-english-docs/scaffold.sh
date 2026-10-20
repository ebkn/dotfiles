#!/bin/bash
#
# Three uncommitted Markdown changes, the candidates of step 1: a Japanese doc
# with one finding, an English README, and an English SKILL.md whose
# frontmatter quotes Japanese triggers (hiragana present, 。 absent). Linting
# either English file yields sentence-length and max-comma noise, so leaving
# them out is visible in which paths reach textlint-docs.
#
# The changes are modifications of committed files, so the diff can be pinned
# by hash: the skill may not touch it.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/lint-docs/evals/lib.sh"

mkdir -p docs skills/deploy
printf '# 配布ガイド（日本語）\n\n配布の手順をまとめる。\n' >docs/guide-ja.md
printf '# deploy-kit\n' >README.md
printf -- '---\nname: deploy\n---\n' >skills/deploy/SKILL.md
skill_eval_init_repo

cat >>docs/guide-ja.md <<'EOF'

予め `make check` を実行しておく。

配布が終わったら、配布先の応答を確かめる。
EOF
lint_docs_write_english_readme
lint_docs_write_english_skill
git diff | git hash-object --stdin >.git/lint-docs-eval-diff

lint_docs_link_tool
