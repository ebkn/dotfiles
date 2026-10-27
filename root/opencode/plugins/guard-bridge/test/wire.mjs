// The wiring of registerGuardBridge, against the mock hook scripts the
// suite stages (group `real` runs the real ~/.claude scripts instead).
// Usage:
//
//   node wire.mjs <results.tsv> <stage-dir> <group> [<claude-hooks-dir>]
//
// Groups: allow | rank | failures | rewrite | real
// Records `ok|fail<TAB>name<TAB>detail` lines and exits nonzero when any
// recorded check failed (guard-bridge.test.sh turns them into checks).
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const [resultsPath, stage, group, claudeHooksArg] = process.argv.slice(2)
const { registerGuardBridge } = await import("../bridge.mjs")
const mockDir = process.env.MOCK_DIR
if (!mockDir) throw new Error("MOCK_DIR unset")

const sessionDir = path.join(stage, "session")
fs.mkdirSync(sessionDir, { recursive: true })

const checks = []
const check = (name, ok, detail = "") => checks.push(`${ok ? "ok" : "fail"}\t${name}\t${detail}`)

// The case-controlled behavior of one mock script.
const setOut = (name, content) => {
  const file = path.join(mockDir, `${name}.out`)
  if (content === undefined) fs.rmSync(file, { force: true })
  else fs.writeFileSync(file, content)
}
const clearOuts = () => {
  for (const file of fs.readdirSync(mockDir)) {
    if (file.endsWith(".out")) fs.rmSync(path.join(mockDir, file), { force: true })
  }
}
// A hookSpecificOutput the mock scripts or the real strip script would emit.
const dec = (decision, reason, updated) =>
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: decision,
      permissionDecisionReason: reason,
      ...(updated ? { updatedInput: updated } : {}),
    },
  })

// A ctx recording the hooks each registration attempts, with a session
// service stub pointing at the session dir.
function makeCtx(options = {}) {
  const hooks = { tool: [], shell: [], permission: [] }
  const sessionDirectory = options.sessionDirectory ?? sessionDir
  const throws = options.sessionThrows
  return {
    hooks,
    ctx: {
      location: { directory: sessionDir },
      session: {
        get: async ({ sessionID }) => {
          if (throws) throw new Error(`no session ${sessionID}`)
          return { location: { directory: sessionDirectory } }
        },
      },
      tool: { hook: (name, callback) => hooks.tool.push([name, callback]) },
      shell: { hook: (name, callback) => hooks.shell.push([name, callback]) },
      permission: { hook: (name, callback) => hooks.permission.push([name, callback]) },
    },
  }
}
const hookOf = (hooks, domain, name) => hooks[domain].find(([n]) => n === name)?.[1]
const beforeOf = (reg) => hookOf(reg.hooks, "tool", "execute.before")
const afterOf = (reg) => hookOf(reg.hooks, "tool", "execute.after")
const createOf = (reg) => hookOf(reg.hooks, "shell", "create.before")
const evaluateOf = (reg) => hookOf(reg.hooks, "permission", "evaluate")

const logPath = (name) => path.join(stage, name)
const resetLog = (name) => {
  const file = logPath(name)
  fs.rmSync(file, { force: true })
  process.env.MOCK_LOG = file
  return file
}

function registerForGroup(options = {}) {
  const { hooks, ctx } = makeCtx(options)
  const registerArgs = {
    hooksDir: options.hooksDir ?? mockDir,
    ...(options.deps ?? {}),
  }
  if (!registerArgs.sessionGet && !options.useDefaultSessionGet) {
    registerArgs.sessionGet = ctx.session.get
  }
  hooks.ctx = ctx
  return registerGuardBridge(ctx, registerArgs).then((state) => ({ ...state, hooks }))
}

const runScenario = async (name, body) => {
  clearOuts()
  const from = checks.length
  try {
    await body()
  } catch (error) {
    check(`scenario ${name} ran to completion`, false, String(error?.stack ?? error))
  }
  if (checks.length === from) check(`scenario ${name} ran to completion`, false, "recorded no checks")
}

// ── group: verdicts reach effect/message, and pair up ─────────────────
// Group `allow`: stash + source pairing + spawn observation + verdict.
if (group === "allow") {
  await runScenario("pairing and observation", async () => {
    setOut("rm-guard", dec("allow", "rm-guard allow reason"))
    const logFile = resetLog("allow.log")
    // Default sessionGet: ctx.session.get must be the one consulted.
    const reg = await registerForGroup({ useDefaultSessionGet: true })
    const before = beforeOf(reg)
    const evaluate = evaluateOf(reg)
    check(
      "registerGuardBridge subscribes the three hooks",
      typeof before === "function" && typeof evaluate === "function" && typeof afterOf(reg) === "function" &&
        typeof createOf(reg) === "function",
      JSON.stringify(reg.hooks.tool.map(([n]) => n)),
    )

    await before({ tool: "shell", messageID: "m1", id: "t1", input: { command: "rm tmp/x" } })
    const event = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "m1", id: "t1" }, effect: "ask" }
    await evaluate(event)
    check("evaluate consumes the paired stash entry", reg.pending.size === 0, String(reg.pending.size))
    check("rm-guard allow reaches effect", event.effect === "allow", JSON.stringify(event))
    check("the allow reason is carried along", event.message === "rm-guard allow reason", JSON.stringify(event.message))
    check("the session directory lookup is cached", reg.sessionDirs.get("s1") === sessionDir, String(reg.sessionDirs.get("s1")))

    // The mock log: line 0 is the stdin JSON, the rest are key=value notes.
    const log = fs.readFileSync(logFile, "utf8").trimEnd().split("\n")
    let stdin = {}
    try {
      stdin = JSON.parse(log[0])
    } catch (error) {
      check("stdin is the logged first line", false, JSON.stringify(log.slice(0, 2)))
    }
    const observed = Object.fromEntries(log.slice(1).map((line) => {
      const eq = line.indexOf("=")
      return [line.slice(0, eq), line.slice(eq + 1)]
    }))
    check("stdin carries tool_input.command", stdin.tool_input?.command === "rm tmp/x", JSON.stringify(log[0]))
    check("stdin carries the resolved execution cwd", stdin.cwd === sessionDir, JSON.stringify(stdin.cwd))
    // The child's OS cwd may print through /private on macOS; the leaf stays.
    check("spawned in the execution cwd", observed.cwd?.endsWith("/session") === true, JSON.stringify(observed.cwd))
    check("child sees CLAUDE_PROJECT_DIR = execution cwd", observed.project === sessionDir, JSON.stringify(observed.project))
    check("child keeps the host HOME", (observed.home ?? "") !== "", JSON.stringify(observed.home))
    check("child keeps the host PATH", observed.path === "set", JSON.stringify(observed.path))
  })

  await runScenario("workdir and the second pairing", async () => {
    setOut("rm-guard", dec("allow", "rm-guard allow reason"))
    const logFile = resetLog("workdir.log")
    fs.mkdirSync(path.join(sessionDir, "sub"), { recursive: true })
    const reg = await registerForGroup()
    await beforeOf(reg)({ tool: "shell", messageID: "m2", id: "t2", input: { command: "rm tmp/y", workdir: "sub" } })
    const second = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "m2", id: "t2" }, effect: "ask" }
    await evaluateOf(reg)(second)
    check("a workdir pairing still finds the stash entry", second.effect === "allow", JSON.stringify(second))
    const observed = Object.fromEntries(fs.readFileSync(logFile, "utf8").trimEnd().split("\n").slice(1).map((line) => {
      const eq = line.indexOf("=")
      return [line.slice(0, eq), line.slice(eq + 1)]
    }))
    check("workdir resolves the spawn cwd", observed.cwd?.endsWith("/sub") === true, JSON.stringify(observed.cwd))
    check("the stdin cwd is the resolved workdir", observed.project === path.join(sessionDir, "sub"), JSON.stringify(observed.project))
  })

  await runScenario("wrong tool and action are ignored", async () => {
    const reg = await registerForGroup()
    await beforeOf(reg)({ tool: "edit", messageID: "m3", id: "t3", input: { command: "rm tmp/x" } })
    await beforeOf(reg)({ tool: "shell", messageID: "m3", id: "t3", input: { command: "" } })
    check("non-shell tool calls are not stashed", reg.pending.size === 0, String(reg.pending.size))
    const event = { sessionID: "s1", action: "read", resources: [], source: { messageID: "m4", id: "t4" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check("non-shell action is ignored", event.effect === "ask" && event.message === undefined, JSON.stringify(event))
  })

  await runScenario("a throwing session service degrades to the plugin location", async () => {
    setOut("rm-guard", dec("allow", "rm-guard allow reason"))
    resetLog("fallback.log")
    const reg = await registerForGroup({ sessionThrows: true })
    await beforeOf(reg)({ tool: "shell", messageID: "m5", id: "t5", input: { command: "rm tmp/x" } })
    const event = { sessionID: "unknown", action: "shell", resources: [], source: { messageID: "m5", id: "t5" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check(
      "a throwing session service still spawns with a real cwd",
      event.effect === "allow",
      JSON.stringify(event),
    )
  })
}

// ── group: ranking, resources fallback, cap, cleanup ──────────────────
if (group === "rank") {
  await runScenario("deny outranks ask and allow", async () => {
    setOut("curl-guard", dec("deny", "curl deny reason"))
    setOut("rm-guard", dec("ask", "rm ask reason"))
    const reg = await registerForGroup()
    await beforeOf(reg)({
      tool: "shell",
      messageID: "d1",
      id: "t1",
      input: { command: "curl https://f && rm x" },
    })
    const event = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "d1", id: "t1" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check("the deny wins the ranking", event.effect === "deny", JSON.stringify(event))
    check("the winning reason is the deny's", event.message === "curl deny reason", JSON.stringify(event.message))
    // An allow alone.
    setOut("curl-guard", undefined)
    setOut("rm-guard", dec("allow", "rm allow reason"))
    await beforeOf(reg)({ tool: "shell", messageID: "d2", id: "t2", input: { command: "rm x" } })
    const allowEvent = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "d2", id: "t2" }, effect: "ask" }
    await evaluateOf(reg)(allowEvent)
    check("a lone allow reaches effect", allowEvent.effect === "allow", JSON.stringify(allowEvent))
  })

  await runScenario("unpaired events fall back to resources", async () => {
    setOut("rm-guard", dec("allow", "rm-guard allow reason"))
    const reg = await registerForGroup()
    const event = {
      sessionID: "s1",
      action: "shell",
      resources: ["echo ok", "rm x/c1"],
      source: { messageID: "f1", id: "t1" },
      effect: "ask",
    }
    await evaluateOf(reg)(event)
    check(
      "the resources fallback engages the judgment hooks",
      event.effect === "allow" && event.message === "rm-guard allow reason",
      JSON.stringify(event),
    )
    check("an unpaired evaluate left no stash entry", reg.pending.size === 0, String(reg.pending.size))
    const noEngage = {
      sessionID: "s1",
      action: "shell",
      resources: ["echo only"],
      source: { messageID: "f1", id: "t1" },
      effect: "ask",
    }
    await evaluateOf(reg)(noEngage)
    check(
      "an event nothing engages leaves the effect alone",
      noEngage.effect === "ask" && noEngage.message === undefined,
      JSON.stringify(noEngage),
    )
  })

  await runScenario("the pending stash is capped and cleared", async () => {
    const reg = await registerForGroup()
    const before = beforeOf(reg)
    for (let i = 1; i <= 130; i++) {
      await before({ tool: "shell", messageID: `m${i}`, id: `t${i}`, input: { command: `echo ${i}` } })
    }
    check("paging keeps the freshest 128 entries", reg.pending.size === 128, String(reg.pending.size))
    const event = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "m130", id: "t130" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check("the freshest entry is the one evaluate pairs with", !reg.pending.has("m130:t130"))
    await afterOf(reg)({ tool: "shell", messageID: "m128", id: "t128" })
    check("execute.after clears its shell's entry", reg.pending.has("m127:t127") && !reg.pending.has("m128:t128"))
    await afterOf(reg)({ tool: "edit", messageID: "m127", id: "t127" })
    check("execute.after ignores other tools", reg.pending.has("m127:t127"))
  })
}

// ── group: failure postures and quiet degradation ─────────────────────
if (group === "failures") {
  await runScenario("silent scripts fail silently", async () => {
    setOut("rm-guard", "crash")
    const reg = await registerForGroup()
    await beforeOf(reg)({ tool: "shell", messageID: "x1", id: "t1", input: { command: "rm x" } })
    const event = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "x1", id: "t1" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check("a crashing silent script leaves the decision alone", event.effect === "ask" && event.message === undefined, JSON.stringify(event))

    // A crash without the pairing also never denies.
    const fallback = { sessionID: "s1", action: "shell", resources: ["rm x"], effect: "ask" }
    await evaluateOf(reg)(fallback)
    check("a crashed silent script on the fallback stays ask", fallback.effect === "ask", JSON.stringify(fallback))
  })

  await runScenario("git-guard fails closed like onFailure block", async () => {
    setOut("git-guard", "crash")
    const reg = await registerForGroup()
    await beforeOf(reg)({ tool: "shell", messageID: "g1", id: "t1", input: { command: "git status" } })
    const event = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "g1", id: "t1" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check("a crashing git-guard denies", event.effect === "deny", JSON.stringify(event))
    check(
      "the deny names the hook and the Claude posture",
      event.message?.startsWith("guard-bridge: git-guard failed") === true && event.message.includes("onFailure"),
      JSON.stringify(event.message),
    )
  })

  await runScenario("an unpinned event with no resources is left alone", async () => {
    // No `source`, no stash entry, no `resources` either: commandFromResources
    // must degrade to no command rather than crash the permission flow.
    setOut("rm-guard", dec("allow", "rm-guard allow reason"))
    const reg = await registerForGroup()
    const event = { sessionID: "s1", action: "shell", effect: "ask" }
    await evaluateOf(reg)(event)
    check(
      "no source and no resources leaves the effect alone",
      event.effect === "ask" && event.message === undefined,
      JSON.stringify(event),
    )
  })

  await runScenario("absent ~/.claude/hooks degrades quietly", async () => {
    const absent = path.join(stage, "absent-mock")
    const reg = await registerForGroup({ hooksDir: absent })
    check("a missing script is absent, not failing", reg.scriptExists("git-guard.sh") === false)
    check("a missing script is absent (rm-guard too)", reg.scriptExists("rm-guard.sh") === false)
    await beforeOf(reg)({ tool: "shell", messageID: "n1", id: "t1", input: { command: "git status" } })
    const event = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "n1", id: "t1" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check(
      "with no hooks dir at all a git command is left to the rules",
      event.effect === "ask" && event.message === undefined,
      JSON.stringify(event),
    )
  })
}

// ── group: the create.before rewrite ──────────────────────────────────
if (group === "rewrite") {
  await runScenario("create.before rewrites through updatedInput", async () => {
    setOut("strip-redundant-cd", dec("defer", "strip mock reason", { command: "git status" }))
    const logFile = resetLog("rewrite.log")
    const reg = await registerForGroup()
    const event = { command: "cd missing-nowhere && git status", cwd: "missing-nowhere" }
    await createOf(reg)(event)
    check("the rewritten command replaces event.command", event.command === "git status", JSON.stringify(event))
    const observed = Object.fromEntries(
      fs.readFileSync(logFile, "utf8").trimEnd().split("\n")
        .slice(1)
        .map((line) => {
          const eq = line.indexOf("=")
          return [line.slice(0, eq), line.slice(eq + 1)]
        }),
    )
    check(
      "the rewrite spawning falls back to an existing dir for a raw cwd",
      observed.cwd?.endsWith("/session") === true,
      JSON.stringify(observed.cwd),
    )
  })

  await runScenario("a silent or failing strip stays unwritten", async () => {
    const reg = await registerForGroup()
    const event = { command: "cd missing-nowhere && git status", cwd: sessionDir }
    await createOf(reg)(event)
    check("a silent strip leaves the command", event.command === "cd missing-nowhere && git status", JSON.stringify(event))
    setOut("strip-redundant-cd", "crash")
    const crashed = { command: "cd missing-nowhere && git status", cwd: sessionDir }
    await createOf(reg)(crashed)
    check("a crashed strip leaves the command", crashed.command === "cd missing-nowhere && git status", JSON.stringify(crashed))
    // And the engagement prefilter holds: no leading cd, no spawn at all.
    resetLog("rewrite.log")
    const unrelated = { command: "echo cd x; y", cwd: sessionDir }
    await createOf(reg)(unrelated)
    const logged = fs.existsSync(logPath("rewrite.log")) ? fs.readFileSync(logPath("rewrite.log"), "utf8") : ""
    check("a not-leading-cd command spawns no strip", logged === "", JSON.stringify(logged))
  })
}

// ── group: the real scripts, driven exactly as OpenCode would ─────────
if (group === "real") {
  if (!claudeHooksArg) throw new Error("the real group needs the claude hooks dir")
  // Production mirrors settings.json's timeout: 5 (the bridge default); the
  // test runs the real scripts on a busy runner next to other suites, so the
  // registration gets a test-only generous timeout instead of asserting the
  // scripts' worst case.
  const realDeps = { timeoutMs: 30_000 }
  await runScenario("real strip rewrites a redundant cd", async () => {
    const reg = await registerForGroup({ hooksDir: claudeHooksArg, deps: realDeps })
    const event = { command: `cd ${sessionDir} && echo hello-real`, cwd: sessionDir }
    await createOf(reg)(event)
    check("real strip rewrote to the remainder", event.command === "echo hello-real", JSON.stringify(event))
    const unrelated = { command: `cd ${sessionDir}/.. && echo elsewhere`, cwd: sessionDir }
    await createOf(reg)(unrelated)
    check("real strip keeps a cd to somewhere else", unrelated.command === `cd ${sessionDir}/.. && echo elsewhere`, JSON.stringify(unrelated))
  })

  await runScenario("real git-guard denies a -c before the subcommand", async () => {
    const reg = await registerForGroup({ hooksDir: claudeHooksArg, deps: realDeps })
    await beforeOf(reg)({
      tool: "shell",
      messageID: "r1",
      id: "t1",
      input: { command: "git -c core.fsmonitor=/nonexistent-guard-probe status" },
    })
    const event = { sessionID: "s1", action: "shell", resources: [], source: { messageID: "r1", id: "t1" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check("real git-guard denies the option-bearing git", event.effect === "deny", JSON.stringify(event))
    check(
      "real git-guard denies through its JSON, not a crash",
      event.message?.startsWith("git-guard: refused") === true,
      JSON.stringify(event.message),
    )
  })

  await runScenario("real rm-guard allows inside the cwd's tmp, silent outside", async () => {
    const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "guard-bridge-rm-"))
    fs.mkdirSync(path.join(fixture, "tmp"))
    fs.writeFileSync(path.join(fixture, "tmp", "scratch.txt"), "disposable\n")
    const reg = await registerForGroup({ hooksDir: claudeHooksArg, deps: { ...realDeps, sessionGet: async () => ({ location: { directory: fixture } }) } })
    await beforeOf(reg)({ tool: "shell", messageID: "r2", id: "t2", input: { command: "rm tmp/scratch.txt" } })
    const event = { sessionID: "s2", action: "shell", resources: [], source: { messageID: "r2", id: "t2" }, effect: "ask" }
    await evaluateOf(reg)(event)
    check("real rm-guard allows the scratch operand", event.effect === "allow", JSON.stringify(event))
    check("the reason names rm-guard", event.message?.includes("rm-guard") === true, JSON.stringify(event.message))

    await beforeOf(reg)({ tool: "shell", messageID: "r3", id: "t3", input: { command: "rm /nonexistent-guard-root/other" } })
    const outside = { sessionID: "s2", action: "shell", resources: [], source: { messageID: "r3", id: "t3" }, effect: "ask" }
    await evaluateOf(reg)(outside)
    check(
      "real rm-guard stays silent on an operand outside the scratch roots",
      outside.effect === "ask" && outside.message === undefined,
      JSON.stringify(outside),
    )
    fs.rmSync(fixture, { recursive: true })
  })
}

fs.writeFileSync(resultsPath, `${checks.join("\n")}\n`)
if (checks.some((line) => !line.startsWith("ok"))) process.exitCode = 1
