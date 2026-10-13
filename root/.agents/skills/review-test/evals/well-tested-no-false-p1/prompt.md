---
name: well-tested-no-false-p1
allowed_tools: Bash(./run-tests.sh*)
# The second line of the prompt stands in for the caller's own conventions
# (CLAUDE.md, which the runner leaves out), as in review-design's cases.
# Without it a run tried `source lib/quantity.sh && ...`, was refused, read
# the refusal as "everything else is refused too", and stopped before running
# the tests or starting the review.
---
lib/quantity.sh のテストをレビューしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
