---
name: ready-at-finish
allowed_tools: Skill, Write, Edit, Bash(git*)
claude_md: root/CLAUDE.md
skills: create-pr, commit
max_turns: 60
budget_usd: 2
# The branch already has a draft PR, from an earlier session. The request
# finishes the work, and nothing in it mentions the PR: whether the run
# brings the PR up to date and marks it ready before reporting back, without
# opening a second one or asking, rests on root/CLAUDE.md and update-pr.
---
CONTRIBUTING.md に、テストは `./run-tests.sh` で実行するという節を足してください。これで CONTRIBUTING.md は完成です。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
