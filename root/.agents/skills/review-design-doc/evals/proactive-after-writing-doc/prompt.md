---
name: proactive-after-writing-doc
allowed_tools: Skill, Write, Edit
skills: lint-docs
max_turns: 60
budget_usd: 4
# Having written a design doc, the agent reviews it before reporting, without
# being asked, fixes what the review finds and reviews again until a round
# has no P1 or P2 -- review-test's loop. Write and Edit are the scenario's own
# tools. The ceilings leave room for the loop and lint-docs, which only a run
# that starts the skill reaches. no-fire-readme-edit is the pair: a document
# written that is not a design doc, where it must not start;
# proactive-with-claude-md is the same case with root/CLAUDE.md brought in.
---
docs/notes/webhook-retry.md の議論メモをもとに、docs/design/webhook-retry.md に設計ドキュメントを書いてください。書き終えたら報告してください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
