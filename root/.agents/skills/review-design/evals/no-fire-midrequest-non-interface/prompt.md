---
name: no-fire-midrequest-non-interface
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(./total.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 80
budget_usd: 3
claude_md: root/CLAUDE.md
# Two sequential non-interface fixes, each its own commit, in one request.
# root/CLAUDE.md is where the mid-request rule rests — "intermediate commits
# are not breakpoints" — so this case measures exactly that: no review-design
# fork between the commits; one at most, at the request's boundary.
---
parse_quantity が `12.5T`（大文字の T）を受け付けません。コメントでは大文字・小文字どちらの単位も受け付けることになっています。直してコミットしてください。
そのあと、`format_size` が KB→MB の換算を 1024 ではなく 1000 で割っています。コメントでは 1024 で割ることになっているので、それも直してコミットしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
