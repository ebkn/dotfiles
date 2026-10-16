---
name: draft-at-first-commit
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(gh pr list*), Bash(gh pr view*)
claude_md: root/CLAUDE.md
skills: update-pr, commit
max_turns: 80
budget_usd: 3
# Nothing in the prompt mentions a PR or a push: when the PR is opened, as
# what, and whether anyone is asked, rests on root/CLAUDE.md and the two
# skills. Two requests, each committed on its own, so there is a first commit
# that is not the last -- the moment a draft PR belongs to. "Commit each one"
# is said outright, since a run that edits both and splits them afterwards
# has no such moment and would fail the order checks on the scenario.
# Bash(git*) lets a run push or commit without the skills, which is part of
# what is measured, not a gap. The second line stands in for the caller's
# conventions, as in review-test's cases.
---
README のインストール手順が古いので、`./install.sh` を使う手順に直してください。そのあと CONTRIBUTING.md を新しく作り、コミットメッセージは Conventional Commits で書くという決まりを書いてください。1 つ終わるごとにコミットしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
