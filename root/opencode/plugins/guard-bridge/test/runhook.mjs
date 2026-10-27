// runHook's process plumbing against the unit probes the suite stages
// (echo / fail / slow) and the default spawn. Usage:
//
//   node runhook.mjs <results.tsv> <stage-dir>
//
// The stage dir holds unit-echo.sh (recites stdin/cwd/env into $PROBE_LOG,
// stdout is a clean hook JSON), unit-fail.sh (stderr bait, exit 7) and
// unit-slow.sh (hangs as a sh-builtin loop, killed at the timeout).
import fs from "node:fs"
import path from "node:path"

const [resultsPath, stage] = process.argv.slice(2)
const { runHook } = await import("../bridge.mjs")

const checks = []
const check = (name, ok, detail = "") => checks.push(`${ok ? "ok" : "fail"}\t${name}\t${detail}`)

const echo = path.join(stage, "unit-echo.sh")
const probeLog = path.join(stage, "probe.log")
fs.rmSync(probeLog, { force: true })
process.env.PROBE_LOG = probeLog

const stdinPayload = JSON.stringify({ tool_input: { command: "rm tmp/x" }, cwd: stage })
const echoOut = await runHook(echo, { stdin: stdinPayload, cwd: stage, env: { CLAUDE_PROJECT_DIR: stage }, timeoutMs: 5000 })
check(
  "runHook captures the child's hook JSON",
  echoOut.failed === false && echoOut.stdout.includes('"permissionDecision":"allow"') &&
    echoOut.stdout.includes('"permissionDecisionReason":"probe"'),
  JSON.stringify(echoOut),
)

const probe = (fs.readFileSync(probeLog, "utf8").trimEnd().split("\n").map((line) => {
  const eq = line.indexOf("=")
  return [line.slice(0, eq), line.slice(eq + 1)]
}))
const observed = Object.fromEntries(probe)
check(
  "runHook delivers stdin verbatim",
  observed.stdin === stdinPayload,
  JSON.stringify(observed.stdin ?? probe),
)
// The child's OS cwd may print through /private on macOS; the leaf stays.
check(
  "runHook spawns in the given cwd",
  observed.cwd?.endsWith(`/${path.basename(stage)}`) === true,
  JSON.stringify(observed.cwd),
)
check(
  "runHook passes CLAUDE_PROJECT_DIR through",
  observed.proj === stage,
  JSON.stringify(observed.proj),
)
check("the child keeps the host HOME", (observed.home ?? "") !== "", JSON.stringify(observed.home))
check("the child keeps the host PATH", observed.path === "set", JSON.stringify(observed.path))

const failed = await runHook(path.join(stage, "unit-fail.sh"), { stdin: "{}", cwd: stage, env: {}, timeoutMs: 5000 })
check(
  "runHook reports a nonzero exit with the stderr tail",
  failed.failed === true && failed.reason.includes("exit 7") && failed.reason.includes("unit-fail stderr line 2"),
  JSON.stringify(failed.reason),
)

const slow = await runHook(path.join(stage, "unit-slow.sh"), { stdin: "{}", cwd: stage, env: {}, timeoutMs: 100 })
check(
  "runHook kills a hanging child at the timeout",
  slow.failed === true && slow.reason.includes("timed out"),
  JSON.stringify(slow.reason),
)

const missing = await runHook(path.join(stage, "missing-nowhere.sh"), { stdin: "{}", cwd: stage, env: {}, timeoutMs: 5000 })
check(
  "runHook turns a missing script into a failure, not a throw",
  missing.failed === true && missing.reason.length > 0,
  JSON.stringify(missing.reason),
)

const boom = await runHook(
  echo,
  { stdin: "{}", cwd: stage, env: {}, timeoutMs: 5000 },
  () => {
    throw new Error("mock spawner blew up")
  },
)
check(
  "runHook turns a throwing spawn impl into a failure",
  boom.failed === true && boom.reason.includes("mock spawner blew up"),
  JSON.stringify(boom.reason),
)

fs.writeFileSync(resultsPath, `${checks.join("\n")}\n`)
if (checks.some((line) => !line.startsWith("ok"))) process.exitCode = 1
