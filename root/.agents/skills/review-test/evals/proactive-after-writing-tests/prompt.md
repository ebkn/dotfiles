---
name: proactive-after-writing-tests
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(git*)
# The second line of the prompt stands in for the caller's own conventions
# (CLAUDE.md, which the runner leaves out), as in review-design's cases.
# Without it a run tried `source lib/quantity.sh && ...`, was refused, read
# the refusal as "everything else is refused too", and stopped before running
# the tests or starting the review.
---
lib/quantity.sh のテストがまだ無いので書いてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
