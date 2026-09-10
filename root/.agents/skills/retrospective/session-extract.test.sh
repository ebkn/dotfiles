#!/bin/bash
# Unit test for session-extract (beside this file).
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
cat >"$fixture" <<'FIXTURE'
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
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.100Z","uuid":"i1","isSidechain":false,"isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x/skills/commit\n\nCommit changes quickly."}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.200Z","uuid":"i2","isSidechain":false,"isCompactSummary":true,"isVisibleInTranscriptOnly":true,"message":{"role":"user","content":"This session is being continued from a previous conversation that ran out of context."}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.300Z","uuid":"i3","isSidechain":false,"message":{"role":"user","content":"<command-name>/compact</command-name>\n<command-message>compact</command-message>"}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.350Z","uuid":"i3b","isSidechain":false,"message":{"role":"user","content":"<command-message>commit</command-message>\n<command-name>/commit</command-name>"}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.400Z","uuid":"i4","isSidechain":false,"message":{"role":"user","content":"<local-command-stdout>Compacted</local-command-stdout>"}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.500Z","uuid":"i5","isSidechain":false,"message":{"role":"user","content":"<task-notification>\n<task-id>abc</task-id>\n<status>completed</status>\n</task-notification>"}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:13.600Z","uuid":"i6","isSidechain":false,"message":{"role":"user","content":"[Request interrupted by user for tool use]"}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:14.000Z","uuid":"a7","isSidechain":true,"attributionSkill":"review-test","message":{"role":"assistant","usage":{"input_tokens":7,"output_tokens":7,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t7","name":"Bash","input":{"command":"pwd"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.100","timestamp":"2026-09-01T00:00:15.000Z","uuid":"r7","isSidechain":true,"toolUseResult":{"stdout":"/repo","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false,"returnCodeInterpretation":"ok"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t7"}]}}
{"type":"assistant","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.247","timestamp":"2026-09-01T00:00:16.000Z","uuid":"a8","message":{"role":"assistant","usage":{"input_tokens":3,"output_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"content":[{"type":"tool_use","id":"t8","name":"ToolSearch","input":{"query":"x"}}]}}
{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.247","timestamp":"2026-09-01T00:00:17.000Z","uuid":"r8","toolUseResult":"a bare string result","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t8"}]}}
{"type":"mode","mode":"normal","sessionId":"S1"}
FIXTURE

# Permission and safety records, generated so the shapes stay uniform. Each
# Bash call is a tool_use followed by its result; a denial is an is_error
# tool_result whose text is one of the four forms seen in real transcripts.
# Timestamps sit between a8 (16.000) and r8 (17.000) so the range is unchanged.
n=0
bash_call() { # id, command, result kind: ok | err | rule | classifier | user | user-odd-text | hook
  n=$((n + 1))
  ts="2026-09-01T00:00:16.0$(printf '%02d' "$n")Z"
  jq -nc --arg id "$1" --arg cmd "$2" --arg ts "$ts" '{type:"assistant",sessionId:"S1",cwd:"/repo",gitBranch:"main",version:"2.1.247",timestamp:$ts,uuid:("a-"+$id),message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$cmd}}]}}' >>"$fixture"
  n=$((n + 1))
  ts="2026-09-01T00:00:16.0$(printf '%02d' "$n")Z"
  case "$3" in
    ok)
      text=""
      err=false
      kind=""
      ;;
    err)
      text="Exit code 1"
      err=true
      kind=""
      ;;
    rule)
      text="Permission to use Bash with command $2 has been denied."
      err=true
      kind=permission-rule
      ;;
    classifier)
      text="Permission for this action was denied by the Claude Code auto mode classifier. Reason: Blocked by classifier."
      err=true
      kind=automode-blocked
      ;;
    user)
      text="The user doesn't want to proceed with this tool use. The tool use was rejected."
      err=true
      kind=user-rejected
      ;;
    user-odd-text)
      text="Some parts require approval. Output redirection to /tmp/x was blocked."
      err=true
      kind=user-rejected
      ;;
    hook)
      text="git-guard: refused '-c' before the git subcommand."
      err=true
      kind=permission-rule
      ;;
  esac
  if [ "$err" = true ]; then
    jq -nc --arg id "$1" --arg ts "$ts" --arg text "$text" --arg kind "$kind" '{type:"user",sessionId:"S1",cwd:"/repo",gitBranch:"main",version:"2.1.247",timestamp:$ts,uuid:("r-"+$id),toolUseResult:$text,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,is_error:true,content:$text}]}} + (if $kind == "" then {} else {toolDenialKind:$kind} end)' >>"$fixture"
  else
    jq -nc --arg id "$1" --arg ts "$ts" '{type:"user",sessionId:"S1",cwd:"/repo",gitBranch:"main",version:"2.1.247",timestamp:$ts,uuid:("r-"+$id),toolUseResult:{stdout:"",stderr:"",interrupted:false,isImage:false,noOutputExpected:false},message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:""}]}}' >>"$fixture"
  fi
}
# Denied, then the same deletion re-issued through git: one retry.
bash_call d1 'rm -rf /repo/tmp' rule
bash_call d2 'git clean -fdx -- tmp' rule
bash_call d3 'git status --short' ok
# Classifier-blocked remote write, re-issued as a file: one retry.
bash_call d4 'npx wrangler d1 execute db --remote --command "UPDATE t SET x=1"' classifier
bash_call d5 'npx wrangler d1 execute db --remote --file ./tmp/a.sql' classifier
# User said no; the next call is unrelated, so no retry.
bash_call d6 'curl -s https://example.com/' user
bash_call d7 'ls' ok
bash_call d7b 'cat x > /tmp/x' user-odd-text
# An ordinary failed command: is_error, but no toolDenialKind and no denial
# text. Must count as an error result and not as a denial -- and must not
# derail the reduce (it did once, through a `strings` filter in a condition).
bash_call d7c 'ls /nope2' err
# Hook refusal.
bash_call d8 'git -c core.x=y status' hook
# Risky but permitted, plus the two convention breaches.
bash_call d9 'sudo ls /' ok
bash_call d10 "node -e 'console.log(1)'" ok
bash_call d11 'python3 -c "print(1)"' ok
# shellcheck disable=SC2016  # the $(...) is the command under test, not ours to expand
bash_call d12 'TOKEN=$(sed -n "s/oauth_token=//p" ~/.wrangler/config/x.toml); echo "$TOKEN" | wc -c' ok
# A correction typed by the human, and a near-miss that must not count.
printf '%s\n' '{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.247","timestamp":"2026-09-01T00:00:16.090Z","uuid":"c1","message":{"role":"user","content":"判定ボタンはいらない。裏で自動判定して"}}' >>"$fixture"
printf '%s\n' '{"type":"user","sessionId":"S1","cwd":"/repo","gitBranch":"main","version":"2.1.247","timestamp":"2026-09-01T00:00:16.091Z","uuid":"c2","message":{"role":"user","content":"毎日1回実行するなら x30 で"}}' >>"$fixture"

out="$tmp/out.json"
"$extract" "$fixture" >"$out"

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

assert "single line of output" 1 "$(wc -l <"$out" | tr -d ' ')"
assert "schema" 4 "$(q .schema)"
assert "session_id" S1 "$(q .session_id)"
assert "cwd" /repo "$(q .cwd)"
assert "git_branch" main "$(q .git_branch)"

# Trap: version changes mid-session. The last value is what the session ran as,
# but the full set is what lets a report split metrics across a version bump.
assert "cc_version is the last seen" 2.1.247 "$(q .cc_version)"
assert "cc_versions lists all" "2.1.100 2.1.247" "$(q '.cc_versions|join(" ")')"

assert "started_at" 2026-09-01T00:00:00.000Z "$(q .started_at)"
assert "ended_at" 2026-09-01T00:00:17.000Z "$(q .ended_at)"
assert "wall_seconds" 17 "$(q .wall_seconds)"

# A user record carrying toolUseResult is a tool result, not a turn the human
# typed. Counting both makes every session look twice as interactive as it was.
# Nor are the harness's own injections turns: a skill body (isMeta), a compaction
# summary (isCompactSummary), slash-command echo/stdout, a task notification.
# The interrupt IS typed -- the human hit escape -- so it counts, giving 3.
assert "user_turns exclude tool results and injected records" 5 "$(q .user_turns)"
assert "friction.compactions" 1 "$(q .friction.compactions)"
assert "friction.interrupts" 1 "$(q .friction.interrupts)"
assert "assistant_turns" 22 "$(q .assistant_turns)"

# Trap 2: isSidechain is false on most records and absent on a8/r8. Testing
# `== false` instead of `!= true` would misclassify the absent ones.
assert "sidechain_turns" 1 "$(q .sidechain_turns)"

assert "tokens.input" 60 "$(q .tokens.input)"
assert "tokens.output" 45 "$(q .tokens.output)"
assert "tokens.cache_creation" 100 "$(q .tokens.cache_creation)"
assert "tokens.cache_read" 500 "$(q .tokens.cache_read)"

# Tool names come from the tool_use blocks, never from guessing at the result
# shape -- that is what makes trap 1 harmless here.
assert "tools.Bash" 19 "$(q .tools.Bash)"
assert "tools.Edit" 1 "$(q .tools.Edit)"
assert "tools.Write" 1 "$(q .tools.Write)"
assert "tools.ToolSearch" 1 "$(q .tools.ToolSearch)"

# Trap 1: all six Bash result key sets must be attributed to Bash.
assert "every Bash result shape attributed to Bash" 19 "$(q .tool_results.Bash)"
assert "no result fell through to unknown" false "$(q '.tool_results|has("unknown")')"
assert "tool_result_bytes has Bash" true "$(q '.tool_result_bytes|has("Bash")')"
assert "tool_result_bytes has Edit" true "$(q '.tool_result_bytes|has("Edit")')"
# Sized from the tool_result block the model was shown, not from the
# harness-internal toolUseResult: for Edit that object carries originalFile
# and a structured patch and ran 20-40x the block on real sessions. The base
# fixture's Edit block has no content at all, so it must size to zero.
assert "tool_result_bytes.Edit is the block, not the internal object" 0 "$(q .tool_result_bytes.Edit)"
assert "tool_result_bytes.Bash counts denial texts shown to the model" true "$(q '.tool_result_bytes.Bash > 0')"

assert "errors.bash_stderr" 1 "$(q .errors.bash_stderr)"
assert "errors.interrupted" 1 "$(q .errors.interrupted)"

assert "skills are distinct and sorted" "commit review-test" "$(q '.skills|join(" ")')"

assert "mode" normal "$(q .mode)"
# Trap 5: no permission-mode record in this session. Must be null, not an error.
assert "permission_mode is null" null "$(q .permission_mode)"

# Denials are classified from the four result texts seen in real transcripts.
# The order of checks matters: a classifier denial also contains "denied".
assert "denials.rule" 2 "$(q .denials.rule)"
assert "denials.classifier" 2 "$(q .denials.classifier)"
# The second user denial carries a text the regex would file as rule or drop
# ("parts require approval", "was blocked"); the structured toolDenialKind
# on the record is what decides, and the text is only a fallback.
assert "denials.user" 2 "$(q .denials.user)"
assert "denials.hook" 1 "$(q .denials.hook)"

# A retry is a denied Bash command followed, within the next three Bash calls,
# by one sharing an intent class (delete, discard, push, remote, env, kill) or
# repeating the text. rm -> git clean is the shape seen most in real data; the
# classifier-blocked --command re-issued as --file is the other. The curl the
# user refused is followed by an unrelated ls, which is not a retry.
assert "retries_after_denial" 2 "$(q .retries_after_denial)"

# Risky patterns are matched on the command text (tier 2: heuristic, and a
# heredoc body can trip them). One count per command, kinds tallied separately.
assert "risky_commands" 5 "$(q .risky_commands)"
assert "risky.delete" 2 "$(q .risky.delete)"
assert "risky.remote_write" 1 "$(q .risky.remote_write)"
assert "risky.privilege" 1 "$(q .risky.privilege)"
assert "risky.credentials" 1 "$(q .risky.credentials)"

# This repo's conventions (tier 3). The compound cd is t1 from the base fixture.
assert "interpreter_oneliners" 2 "$(q .interpreter_oneliners)"
assert "compound_cd" 1 "$(q .compound_cd)"

# Corrections are a word list over typed prompts (tier 3). するなら must not
# match するな -- the first false positive the list produced on real data.
assert "corrections" 1 "$(q .corrections)"

# --human-turns is what the skill reads transcripts with, so that it never needs
# a general-purpose tool granted to it. Only turns the human typed: a user
# record carrying toolUseResult is a tool result being fed back.
human="$("$extract" --human-turns "$fixture")"
assert "human turns: prompts, the interrupt, the corrections" 5 "$(printf '%s\n' "$human" | grep -c '^--- ')"
assert "human turn text survives" 1 "$(printf '%s\n' "$human" | grep -c 'second turn')"
assert "the interrupt is shown" 1 "$(printf '%s\n' "$human" | grep -c 'Request interrupted')"
assert "tool output does not leak in" 0 "$(printf '%s\n' "$human" | grep -c 'No such file')"
# The same definition must drive both modes, or the count and the text disagree.
assert "skill body is not a human turn" 0 "$(printf '%s\n' "$human" | grep -c 'Base directory for this skill')"
assert "compaction summary is not either" 0 "$(printf '%s\n' "$human" | grep -c 'being continued')"
assert "slash-command echo is not either" 0 "$(printf '%s\n' "$human" | grep -c 'command-name')"
# Newer versions put <command-message> first; 31 of those in 60 real days.
assert "nor when command-message comes first" 0 "$(printf '%s\n' "$human" | grep -c 'command-message')"
assert "task notification is not either" 0 "$(printf '%s\n' "$human" | grep -c 'task-notification')"

exit "$fail"
