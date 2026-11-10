---
name: no-fire-doc-rewording
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 40
budget_usd: 2
claude_md: root/CLAUDE.md
# A one-sentence rewording committed after the doc's review loop already came
# back clean: the exact shape that ran 55 opus forks in 14 days, each its own
# review-design-doc round. Under the granularity clause a re-re-review is
# owed by changed claims, structure or settled decisions — wording never
# forks.
---
docs/design/webhook-retry.md があります。審査済みの文章なので構成は変えずに、「指数バックオフ」という表現を「再送間隔を指数的に広げる方法」に置き換えて、その変更だけをコミットしてください。
テストは不要です。シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
