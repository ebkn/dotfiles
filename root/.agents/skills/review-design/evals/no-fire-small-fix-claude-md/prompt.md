---
name: no-fire-small-fix-claude-md
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(./total.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 60
budget_usd: 2
claude_md: root/CLAUDE.md
# The pair of no-fire-small-fix, under root/CLAUDE.md — where the auto-start
# was measured to rest (9/9 vs 0/7 with and without). Under the breakpoints
# policy the small non-interface fix is still reviewed once, at the request's
# boundary: the case pins that shape, not a bare "did not run".
---
parse_quantity が `12.5T`（大文字の T）を受け付けません。コメントでは大文字・小文字どちらの単位も受け付けることになっています。直してコミットしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
