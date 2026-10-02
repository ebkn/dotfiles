---
name: next-change-scattered
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(./total.sh*), Bash(./delivery.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 60
budget_usd: 2
# The second line is the next planned change the review should weigh the
# structure against; the third stands in for the caller's own conventions, as
# in stale-doc-after-change.
---
このブランチの変更を、設計の観点でレビューしてください。
次は、合計をキログラムでも出力できるようにする予定です。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
