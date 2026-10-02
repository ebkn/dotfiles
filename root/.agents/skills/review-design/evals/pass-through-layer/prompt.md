---
name: pass-through-layer
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 60
budget_usd: 2
# The second line stands in for the caller's own conventions, as in
# stale-doc-after-change: a chained `$?` cannot be approved in a run with no
# one to answer, and would fail the case on the harness.
---
このブランチの変更を、設計の観点でレビューしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
