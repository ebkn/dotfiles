// The pure layer of bridge.mjs: descriptors, parsing, ranking, resolution.
// No spawning and no wiring here -- see wire.mjs; usage:
//
//   node pure.mjs <results.tsv> <claude-hooks-dir>
//
// Records `ok|fail<TAB>name<TAB>detail` lines and exits nonzero when any
// recorded check failed (guard-bridge.test.sh turns them into checks).
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const [resultsPath, claudeHooks] = process.argv.slice(2)
const logic = await import("../bridge.mjs")

const checks = []
const check = (name, ok, detail = "") => checks.push(`${ok ? "ok" : "fail"}\t${name}\t${detail}`)

function scriptExists(name) {
  try {
    return fs.statSync(path.join(claudeHooks, name)).isFile()
  } catch {
    return false
  }
}

// The output contract of the scripts being bridged.
const dec = (decision, reason, updated) =>
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: decision,
      permissionDecisionReason: reason,
      ...(updated ? { updatedInput: updated } : {}),
    },
  })

check("HOOK_TIMEOUT_MS mirrors the 5s hook timeout", logic.HOOK_TIMEOUT_MS === 5000, String(logic.HOOK_TIMEOUT_MS))
const byName = Object.fromEntries(logic.JUDGMENT_HOOKS.map((hook) => [hook.name, hook]))
check("exactly five judgment hooks", logic.JUDGMENT_HOOKS.length === 5, String(logic.JUDGMENT_HOOKS.length))
for (const [name, script, failure] of [
  ["approve-multiline", "approve-multiline-commands.sh", "silent"],
  ["git-dash-c-allow", "git-dash-c-allow.sh", "silent"],
  ["curl-guard", "curl-guard.sh", "silent"],
  ["rm-guard", "rm-guard.sh", "silent"],
  ["git-guard", "git-guard.sh", "deny"],
]) {
  check(`${script} is a descriptor's script`, byName[name]?.script === script, JSON.stringify(byName[name]))
  check(`${script} exists next to the bridge`, scriptExists(script), claudeHooks)
  check(`${name} failure posture is ${failure}`, byName[name]?.failure === failure, JSON.stringify(byName[name]?.failure))
}
const strip = logic.STRIP_REWRITE_HOOK
check("strip is the one rewrite hook", strip?.script === "strip-redundant-cd.sh", JSON.stringify(strip))
check("strip-redundant-cd.sh exists next to the bridge", scriptExists(strip?.script), claudeHooks)

// Engagement mirrors each script's own bail-out.
const gate = (name, command) => byName[name]?.engages(command) === true
check(
  "approve-multiline engages only newline commands",
  gate("approve-multiline", "git commit -m a\nb") && !gate("approve-multiline", "git commit -m a"),
  JSON.stringify([gate("approve-multiline", "x\ny"), gate("approve-multiline", "x")]),
)
check(
  "git-dash-c engages any -C substring",
  gate("git-dash-c-allow", "git -C x status") && gate("git-dash-c-allow", "git status -C") &&
    !gate("git-dash-c-allow", "git status"),
)
check(
  "curl-guard engages the bare word, not substrings",
  gate("curl-guard", "curl https://x") && gate("curl-guard", "echo x | curl -s -f @-") &&
    !gate("curl-guard", "curlx") && !gate("curl-guard", "curl-out") && !gate("curl-guard", "recursed") &&
    !gate("curl-guard", "/usr/bin/curl -s"),
)
check(
  "rm-guard engages the bare word, not substrings",
  gate("rm-guard", "rm ./tmp/x") && !gate("rm-guard", "chmod") && !gate("rm-guard", "firmware") &&
    !gate("rm-guard", "/bin/rm -rf tmp/x"),
)
check(
  "git-guard engages the substring, like its bail-out",
  gate("git-guard", "git status") && gate("git-guard", "/usr/bin/git status") && gate("git-guard", "echo git") &&
    !gate("git-guard", "echo g it"),
)
check(
  "strip engages only a leading `cd `",
  strip.engages("cd x && y") && strip.engages("cd x; y") && !strip.engages(" cd x && y") &&
    !strip.engages("echo cd x"),
)

// parseHookOutput: Claude's hook output contract, `defer` included.
const parsedFull = logic.parseHookOutput(dec("deny", "why", { command: "git status" }))
check(
  "parseHookOutput reads decision/reason/updatedInput",
  parsedFull.decision === "deny" && parsedFull.reason === "why" && parsedFull.command === "git status",
  JSON.stringify(parsedFull),
)
const parsedDefer = logic.parseHookOutput(dec("defer", "strip reason", { command: "echo hi" }))
check(
  "parseHookOutput reads defer as no decision but keeps the rewritten command",
  parsedDefer.decision === undefined && parsedDefer.command === "echo hi" && parsedDefer.reason === "strip reason",
  JSON.stringify(parsedDefer),
)
check(
  "parseHookOutput rejects junk",
  logic.parseHookOutput("not json") === undefined && logic.parseHookOutput("{}").decision === undefined,
)
const parsedPartial = logic.parseHookOutput(dec("ask", undefined))
check(
  "parseHookOutput tolerates a missing reason and updatedInput",
  parsedPartial.decision === "ask" && parsedPartial.reason === undefined && parsedPartial.command === undefined,
  JSON.stringify(parsedPartial),
)

// combineVerdicts: deny > ask > allow, undefined skipped, ties keep the first.
const v = (decision) => (decision === undefined ? undefined : { decision, reason: `${decision} reason` })
check(
  "combine ranks deny over ask over allow",
  logic.combineVerdicts([v("allow"), v("ask"), v("deny")]).decision === "deny" &&
    logic.combineVerdicts([v("deny"), v("allow")]).decision === "deny" &&
    logic.combineVerdicts([v("ask"), v("allow")]).decision === "ask" &&
    logic.combineVerdicts([v("allow"), v("ask")]).decision === "ask",
)
check(
  "combine skips undefined and ties keep the first",
  logic.combineVerdicts([undefined, v("ask"), undefined]).reason === "ask reason" &&
    logic.combineVerdicts([v("ask"), v("ask")]).reason === "ask reason",
)
check(
  "combine of nothing is no verdict",
  logic.combineVerdicts([]) === undefined && logic.combineVerdicts([undefined]) === undefined,
)

// resolveExecutionDir: base, existing, missing, tilde, absolute.
const baseDir = fs.mkdtempSync(path.join(os.tmpdir(), "guard-bridge-pure-"))
fs.mkdirSync(path.join(baseDir, "sub"))
check(
  "resolveExecutionDir passes the base through for empty/non-string cwd",
  logic.resolveExecutionDir(baseDir, undefined) === baseDir && logic.resolveExecutionDir(baseDir, "") === baseDir,
)
const resolvedSub = logic.resolveExecutionDir(baseDir, "sub")
check("resolveExecutionDir resolves an existing relative cwd", resolvedSub === path.join(baseDir, "sub"), resolvedSub)
check("resolveExecutionDir falls back to the base for a missing directory", logic.resolveExecutionDir(baseDir, "missing-nowhere") === baseDir)
check("resolveExecutionDir expands ~", logic.resolveExecutionDir(baseDir, "~") === os.homedir())
check("resolveExecutionDir keeps an absolute cwd", logic.resolveExecutionDir(baseDir, baseDir) === baseDir)
fs.rmSync(baseDir, { recursive: true })

// Fallback command and pairing keys.
check(
  "commandFromResources joins segments and treats non-arrays as no command",
  logic.commandFromResources(["a", "rm x"]) === "a && rm x" && logic.commandFromResources([]) === "" &&
    logic.commandFromResources(undefined) === "" && logic.commandFromResources("echo x") === "",
)
check("pairKey pairs a tool call", logic.pairKey({ messageID: "m1", id: "t1" }) === "m1:t1")
check(
  "eventPair reads the evaluate event's source",
  logic.eventPair({ source: { messageID: "m1", id: "t1" } }) === "m1:t1" && logic.eventPair({}) === undefined,
)

fs.writeFileSync(resultsPath, `${checks.join("\n")}\n`)
if (checks.some((line) => !line.startsWith("ok"))) process.exitCode = 1
