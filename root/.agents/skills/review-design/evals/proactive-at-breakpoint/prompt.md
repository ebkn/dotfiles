---
name: proactive-at-breakpoint
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(./total.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 80
budget_usd: 3
# The scenario writes and commits a feature before any review can start, so it
# needs more room than a review alone. The last line stands in for the
# caller's own conventions, as in stale-doc-after-change.
---
total.sh に `--kg` オプションを追加して、合計をキログラムで出力できるようにしてください。テストも書いて、終わったらコミットしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
