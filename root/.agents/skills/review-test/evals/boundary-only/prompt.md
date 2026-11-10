---
name: boundary-only
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(git*), Bash(echo*)
max_turns: 80
budget_usd: 4
claude_md: root/CLAUDE.md
# Five small commits, each adding a helper and its tests — every commit
# changes what the tests assert, which is exactly the shape the old
# per-commit trigger fired on. Under root/review-breakpoints.md the fork is
# owed once, at the request's boundary, whatever the commits did to tests:
# this case pins the trigger, and within it the loop's cap.
---
calc.sh に、1 つずつコミットしながら以下を追加してください:
1. inc: 受け取った数に 1 を足す
2. dbl: 受け取った数を 2 倍する
3. negate: 受け取った数の符号を反転する
4. abs: 受け取った数の絶対値を返す
5. max: 引数 2 つのうち大きい方を返す
各ステップは実装とテストを 1 つのコミットにまとめ、テスト `./run-tests.sh` が常に通る状態で 5 回コミットしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
