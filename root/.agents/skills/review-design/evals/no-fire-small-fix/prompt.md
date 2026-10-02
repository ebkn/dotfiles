---
name: no-fire-small-fix
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(./total.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 60
budget_usd: 2
# Skill is allowed so that not starting the skill is a decision, not a
# permission it lacked. The last line stands in for the caller's own
# conventions, as in stale-doc-after-change.
---
parse_quantity が `12.5T`（大文字の T）を受け付けません。コメントでは大文字・小文字どちらの単位も受け付けることになっています。直してコミットしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
