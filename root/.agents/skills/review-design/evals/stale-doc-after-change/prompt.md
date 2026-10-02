---
name: stale-doc-after-change
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
max_turns: 60
budget_usd: 2
# The second line of the prompt stands in for the caller's own conventions
# (CLAUDE.md, which the runner deliberately leaves out). Without it the model
# chains `./run-tests.sh | grep ...; echo rc=$?` with the commit, or runs the
# tests as `bash run-tests.sh`; neither can be approved in a run with no one to
# answer, the refusal says everything else needing approval is refused too,
# and the case fails on the harness rather than on anything the skill decides.
---
このブランチの変更を、設計の観点でレビューしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
