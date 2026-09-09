#!/bin/bash
# Unit test for bin/session-extract.
#
# The fixture is synthetic on purpose: a real transcript carries work-repo paths
# and source, runs to megabytes, and cannot be pinned as an expected value. What
# it does reproduce is every shape that made the real data hard to parse -- see
# the trap comments below. Each of those was found by measuring real sessions,
# and each fails silently if handled wrong.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
extract="$here/session-extract"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fixture="$tmp/session.jsonl"

# Traps encoded below, all observed in real transcripts:
#   1. Bash results appear with several different key sets -- the optional keys
#      (gitOperation, staleReadFileStateHint, backgroundTaskId, ...) vary per
#      call, so an exact key-set match silently drops calls.
#   2. isSidechain is `false` on some records and absent entirely on others.
#   3. Bash commands are multi-line and carry heredoc bodies containing code.
#   4. toolUseResult is sometimes a bare string, not an object.
#   5. permission-mode records do not exist in every session.
cat > "$fixture" <<'FIXTURE'
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:00.000Z","uuid":"u1","isSidechain":false,"message":{"role":"user","content":"start"}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:01.000Z","uuid":"a1","isSidechain":false,"attributionSkill":"commit","message":{"role":"assistant","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":200},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"cd /repo && grep -n foo bar.txt"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:02.000Z","uuid":"r1","isSidechain":false,"toolUseResult":{"stdout":"1:foo","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1"}]}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:03.000Z","uuid":"a2","isSidechain":false,"message":{"role":"assistant","usage":{"input_tokens":20,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":300},"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"cat > f.ts <<'EOF'\nimport x from 'y';\nconst z = 1;\nEOF"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:04.000Z","uuid":"r2","isSidechain":false,"toolUseResult":{"stdout":"","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":true,"gitOperation":false},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2"}]}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:05.000Z","uuid":"a3","isSidechain":false,"message":{"role":"assistant","usage":{"input_tokens":5,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t3","name":"Edit","input":{"file_path":"/repo/a.ts"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:06.000Z","uuid":"r3","isSidechain":false,"toolUseResult":{"filePath":"/repo/a.ts","oldString":"a","newString":"b","originalFile":"a","structuredPatch":[],"userModified":false,"replaceAll":false},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t3"}]}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:07.000Z","uuid":"a4","isSidechain":false,"message":{"role":"assistant","usage":{"input_tokens":5,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t4","name":"Write","input":{"file_path":"/repo/b.ts"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:08.000Z","uuid":"r4","isSidechain":false,"toolUseResult":{"type":"create","filePath":"/repo/b.ts","content":"x","structuredPatch":[],"originalFile":"","userModified":false},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t4"}]}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:09.000Z","uuid":"a5","isSidechain":false,"attributionSkill":"commit","message":{"role":"assistant","usage":{"input_tokens":5,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t5","name":"Bash","input":{"command":"ls /nope"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:10.000Z","uuid":"r5","isSidechain":false,"toolUseResult":{"stdout":"","stderr":"ls: /nope: No such file","interrupted":false,"isImage":false,"noOutputExpected":false,"staleReadFileStateHint":true},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t5"}]}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:11.000Z","uuid":"a6","isSidechain":false,"message":{"role":"assistant","usage":{"input_tokens":5,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t6","name":"Bash","input":{"command":"sleep 999"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:12.000Z","uuid":"r6","isSidechain":false,"toolUseResult":{"stdout":"","stderr":"","interrupted":true,"isImage":false,"noOutputExpected":false,"backgroundTaskId":"bg1","backgroundCwdHint":"/repo"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t6"}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.000Z","uuid":"u3","isSidechain":false,"message":{"role":"user","content":"second turn"}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:14.000Z","uuid":"a7","isSidechain":true,"attributionSkill":"review-test","message":{"role":"assistant","usage":{"input_tokens":7,"output_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t7","name":"Bash","input":{"command":"pwd"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:15.000Z","uuid":"r7","isSidechain":true,"toolUseResult":{"stdout":"/repo","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false,"returnCodeInterpretation":"ok"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t7"}]}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.247","timestamp":"2026-09-01T00:00:16.000Z","uuid":"a8","message":{"role":"assistant","usage":{"input_tokens":3,"output_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t8","name":"ToolSearch","input":{"query":"x"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.247","timestamp":"2026-09-01T00:00:17.000Z","uuid":"r8","toolUseResult":"a bare string result","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t8"}]}}
{"type":"mode","mode":"normal","sessionId":"S1"}
FIXTURE

out="$tmp/out.json"
"$extract" "$fixture" > "$out"

fail=0
assert() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}
q() { jq -r "$1" "$out"; }

assert "single line of output"  1     "$(wc -l < "$out" | tr -d ' ')"
assert "schema"                 1     "$(q .schema)"
assert "session_id"             S1    "$(q .session_id)"
assert "cwd"                    /repo "$(q .cwd)"
assert "git_branch"             main  "$(q .git_branch)"

# Trap: version changes mid-session. The last value is what the session ran as,
# but the full set is what lets a report split metrics across a version bump.
assert "cc_version is the last seen"    2.1.247            "$(q .cc_version)"
assert "cc_versions lists all"          "2.1.100 2.1.247"  "$(q '.cc_versions|join(" ")')"

assert "started_at" 2026-09-01T00:00:00.000Z "$(q .started_at)"
assert "ended_at"   2026-09-01T00:00:17.000Z "$(q .ended_at)"
assert "wall_seconds" 17 "$(q .wall_seconds)"

# A user record carrying toolUseResult is a tool result, not a turn the human
# typed. Counting both makes every session look twice as interactive as it was.
assert "user_turns exclude tool results" 2 "$(q .user_turns)"
assert "assistant_turns"                 8 "$(q .assistant_turns)"

# Trap 2: isSidechain is false on most records and absent on a8/r8. Testing
# `== false` instead of `!= true` would misclassify the absent ones.
assert "sidechain_turns" 1 "$(q .sidechain_turns)"

assert "tokens.input"          60  "$(q .tokens.input)"
assert "tokens.output"         45  "$(q .tokens.output)"
assert "tokens.cache_creation" 100 "$(q .tokens.cache_creation)"
assert "tokens.cache_read"     500 "$(q .tokens.cache_read)"

# Tool names come from the tool_use blocks, never from guessing at the result
# shape -- that is what makes trap 1 harmless here.
assert "tools.Bash"       5 "$(q .tools.Bash)"
assert "tools.Edit"       1 "$(q .tools.Edit)"
assert "tools.Write"      1 "$(q .tools.Write)"
assert "tools.ToolSearch" 1 "$(q .tools.ToolSearch)"

# Trap 1: all six Bash result key sets must be attributed to Bash.
assert "every Bash result shape attributed to Bash" 5 "$(q .tool_results.Bash)"
assert "no result fell through to unknown" false "$(q '.tool_results|has("unknown")')"
assert "tool_result_bytes has Bash"   true "$(q '.tool_result_bytes|has("Bash")')"
assert "tool_result_bytes has Edit"   true "$(q '.tool_result_bytes|has("Edit")')"

assert "errors.bash_stderr"  1 "$(q .errors.bash_stderr)"
assert "errors.interrupted"  1 "$(q .errors.interrupted)"

assert "skills are distinct and sorted" "commit review-test" "$(q '.skills|join(" ")')"

assert "mode" normal "$(q .mode)"
# Trap 5: no permission-mode record in this session. Must be null, not an error.
assert "permission_mode is null" null "$(q .permission_mode)"

# --human-turns is what the skill reads transcripts with, so that it never needs
# a general-purpose tool granted to it. Only turns the human typed: a user
# record carrying toolUseResult is a tool result being fed back.
human="$("$extract" --human-turns "$fixture")"
assert "human turns exclude tool results" 2 "$(printf '%s\n' "$human" | grep -c '^--- ')"
assert "human turn text survives"         1 "$(printf '%s\n' "$human" | grep -c 'second turn')"
assert "tool output does not leak in"     0 "$(printf '%s\n' "$human" | grep -c 'No such file')"

exit "$fail"
