---
name: hidden-clock-no-seam
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(./total.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 90
budget_usd: 4
# 90 turns and 4 USD: room for the second review round the loop requires.
# The second line stands in for the caller's own conventions, as in
# stale-doc-after-change.
---
このブランチの変更を、設計の観点でレビューしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
