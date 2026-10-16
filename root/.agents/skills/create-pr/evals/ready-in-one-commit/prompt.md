---
name: ready-in-one-commit
allowed_tools: Skill, Write, Edit, Bash(git*)
claude_md: root/CLAUDE.md
skills: update-pr, commit
max_turns: 60
budget_usd: 2
# The pair of draft-at-first-commit with one request instead of two: the first
# commit is also the last, so the PR may be opened ready straight away, or as a
# draft that update-pr then marks ready. Either passes; what the case pins is
# that it ends ready and pushed, and that nobody was asked.
---
README のインストール手順が古いので、`./install.sh` を使う手順に直してください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
