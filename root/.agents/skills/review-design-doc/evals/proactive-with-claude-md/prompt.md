---
name: proactive-with-claude-md
allowed_tools: Skill, Write, Edit, Bash(git*)
skills: lint-docs
claude_md: root/CLAUDE.md
max_turns: 60
budget_usd: 4
# The pair of proactive-after-writing-doc: the same prompt, fixture and
# grader, plus the CLAUDE.md the auto-start rule is to live in, as for
# review-test, whose auto-start rests on root/CLAUDE.md rather than on its
# description (bin/skill-eval.md). Bash(git*) because that CLAUDE.md commits
# at a breakpoint; the grader accepts the doc committed or not.
---
docs/notes/webhook-retry.md の議論メモをもとに、docs/design/webhook-retry.md に設計ドキュメントを書いてください。書き終えたら報告してください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
