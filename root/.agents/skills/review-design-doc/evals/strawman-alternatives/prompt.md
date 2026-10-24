---
name: strawman-alternatives
allowed_tools: Skill
skills: lint-docs
budget_usd: 3
# Started by name, so the case measures what the review finds, not whether it
# starts (fires-on-phrase measures that). Named in words, not as
# `/review-design-doc <path>`: under `claude -p` a forked skill started by slash
# command ends the run with its own report, so the caller never gets the turn
# that starts lint-docs and passes the report on (all 9 Japanese cases failed
# that way on the skill's first run). The second line stands in for the
# caller's conventions, as in the other skills' cases.
---
review-design-doc スキルで docs/design/webhook-retry.md をレビューしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
