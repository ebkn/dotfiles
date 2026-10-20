# lib.sh — the fixture every lint-docs case builds on: Japanese documents with
# one planted finding per category the skill's description promises, and the
# English documents its step 1 has to leave out.
#
# Every planted finding was confirmed against the real toolchain before a case
# was written around it (see evals/README.md), because a fixture whose finding
# no rule reports grades the skill on something the tool never said.
#
# Sourced from a scaffold.sh, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# lint_docs_link_tool
# This checkout's textlint-docs, first on the run's PATH (the runner prepends
# the fixture's bin/). Without it a run would use whichever copy ~/.local/bin
# links to -- another worktree's rules, or nothing on a machine without relink.
# Call it after skill_eval_init_repo: bin/ is kept out of git by the runner's
# exclude, written only after the scaffold returns.
lint_docs_link_tool() {
  mkdir -p bin
  ln -s "$SKILL_EVAL_REPO_ROOT/bin/textlint-docs" bin/textlint-docs
}

# lint_docs_write_guide
# docs/guide.md carries one finding per category, each on its own line so a
# report can be checked line by line:
#   3  サーバ               表記ゆれ (prh section B; the project's majority is サーバー)
#   5  単一の真実のソース   直訳新造語 (prh section A)
#   7  再試行               過剰な漢語化 (prh section A)
#   9  予め / 事            ひらき (ja-hiragana-fukushi / -keishikimeishi)
#   11 大幅に / 完全に      誇張 (no-ai-hype-expressions)
#   13 次を実行する:        英語式コロン (no-ai-colon-continuation)
#   15 ✅                   装飾絵文字 (no-ai-list-formatting)
#   18 ことができる         冗長表現 -- no rule reports it: ja-no-redundant-expression
#                           is disabled in textlintrc.yml. Planted to measure
#                           whether the skill covers what its description promises
#                           beyond the tool.
# docs/ops.md uses サーバー three times and is otherwise clean, so the section B
# finding is one the skill should adopt after measuring.
lint_docs_write_guide() {
  mkdir -p docs
  cat >docs/guide.md <<'EOF'
# 配布ガイド

この文書は配布サーバの運用手順をまとめたものである。

設定は単一の真実のソースとして `config.yml` に置く。

失敗したジョブは再試行キューへ戻す。

予め `make check` を実行しておく事。

この仕組みで配布の手間は大幅に減り、運用は完全に自動化される。

配布の前に次を実行する:

- ✅ ビルドする
- ✅ 配布する

配布先の一覧は `targets.yml` から読み込むことができる。
EOF
  cat >docs/ops.md <<'EOF'
# 運用

配布サーバーは 2 台で構成する。

片方のサーバーを止めるときは、もう片方のサーバーが応答していることを確かめる。
EOF
}

# lint_docs_write_english_readme
# An English README whose one sentence is long and comma-heavy, so linting it
# yields sentence-length and max-comma findings that are pure noise.
lint_docs_write_english_readme() {
  cat >README.md <<'EOF'
# deploy-kit

deploy-kit builds the release bundle, uploads it to every target listed in `targets.yml`, waits for each target to report healthy, and, if any target fails, rolls the whole release back, notifies the on-call channel, and leaves the previous bundle in place, so that a half-finished release never stays live for longer than a single health-check interval.
EOF
}

# lint_docs_write_english_skill
# An English document whose frontmatter quotes Japanese triggers: hiragana is
# present, 。 is not. The shape of deep-dive/SKILL.md, which SKILL.md names as
# the reason a hiragana test misclassifies.
lint_docs_write_english_skill() {
  mkdir -p skills/deploy
  cat >skills/deploy/SKILL.md <<'EOF'
---
name: deploy
description: Ship a release — triggered by "配布して", "デプロイして" or /deploy
---

Run `make release`, then upload the bundle to every target listed in `targets.yml`, wait for each target to report healthy, and, if any of them fails, roll the release back, notify the on-call channel, and keep the previous bundle in place, so that nothing half-finished stays live for longer than one health-check interval.
EOF
}
