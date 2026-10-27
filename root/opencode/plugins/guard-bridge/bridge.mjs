// Guard bridge: the OpenCode translation of Claude Code's PreToolUse hooks
// for Bash (root/.claude/hooks). This module owns the translation and stays
// dependency-free, so node tests import it directly; index.js is the plugin
// entry that registers it through the @opencode/plugin host.
//
// The spawned scripts are Claude Code's, at ~/.claude/hooks — the single
// source for both tools. Their contract is Claude Code's hook contract
// (https://code.claude.com/docs/en/hooks): JSON on stdin with
// `.tool_input.command` and `.cwd`, a `{ hookSpecificOutput:
// { permissionDecision } }` object on stdout, and a silent exit meaning "no
// opinion, normal permission flow applies". Nothing here modifies those
// scripts, so the two tools cannot drift apart; the parity suite
// (root/opencode/opencode-jsonc.test.sh) pins the rule sets the scripts read.
//
// Three things Claude's hooks get that this bridge has to re-create:
//
//   1. The tool pipeline order. Verified against the OpenCode source
//      (packages/core/src/shell.ts, tool/plugin/shell.ts): plugin
//      `shell.create.before` hooks run BEFORE the tool's own prepare step,
//      which is where the command is scanned into resources and
//      permission.assert runs. So a `create.before` rewrite reaches the
//      permission decision — Claude's updatedInput treatment. But the
//      judgment scripts must decide where Claude's decision hooks do: in the
//      `permission.evaluate` hook, whose event may only change
//      `effect`/`message`, never the command.
//
//   2. Claude's decision precedence: among the hook scripts, deny > ask >
//      allow, exactly like Claude ranks permissionDecision values across its
//      hooks. Nothing in the hook layer may soften a configured deny:
//      OpenCode resolves deny rules before the evaluate hook fires.
//
//   3. Claude's failure posture per hook, from its registration in
//      root/.claude/settings.json: git-guard alone carries `onFailure:
//      "block"` (fail closed — refuse the command it could not read); the
//      five others fail silently (their only power is widening or
//      rewriting, so a broken one degrades to the next gate asking, never to
//      a wider allow).

import { spawn } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

export const HOOK_TIMEOUT_MS = 5_000 // mirrors `timeout: 5` in settings.json
export const SHELL_TOOL = "shell"

// Rank order for combining the hook verdicts (deny > ask > allow).
const RANK = { deny: 3, ask: 2, allow: 1 }

// ── engagement, mirrored from each script's own bail-out ──────────────
//
// Each script checks its engagement against the raw command string and exits
// 0 otherwise. Prefiltering here before spawning is behaviorally identical
// (the scripts have already given their answer for a non-matching command):
// it trades one process spawn per shell call for a string test. A different
// condition would be too clever: e.g. only matching a quoting-aware "curl"
// word invites a bypass the fork (the script) still covers.

// The scripts' bare-word regex, `(^|[^[:alnum:]_./-])word([^[:alnum:]_./-]|$)`:
// a shell word, not a substring — `curl https://x` engages, `curlx`,
// `curl-out` and `/usr/bin/curl -s` do not, exactly as in the script.
export function bareWord(word) {
  return new RegExp(`(^|[^A-Za-z0-9_./-])${word}([^A-Za-z0-9_./-]|$)`)
}

/**
 * The five judgment scripts that run in the permission.evaluate hook, one
 * spawned verdict each. `failure` is their degradation when the process
 * fails, mirroring the Claude registration.
 */
export const JUDGMENT_HOOKS = [
  {
    name: "approve-multiline",
    script: "approve-multiline-commands.sh",
    engages: (command) => command.includes("\n"),
    failure: "silent",
  },
  {
    name: "git-dash-c-allow",
    script: "git-dash-c-allow.sh",
    engages: (command) => command.includes("-C"),
    failure: "silent",
  },
  {
    name: "curl-guard",
    script: "curl-guard.sh",
    engages: (command) => bareWord("curl").test(command),
    failure: "silent",
  },
  {
    name: "rm-guard",
    script: "rm-guard.sh",
    engages: (command) => bareWord("rm").test(command),
    failure: "silent",
  },
  {
    name: "git-guard",
    script: "git-guard.sh",
    // Plain substring, like the script's own first bail-out — it must reach
    // /usr/bin/git and any spelling that could be git, and refusing a
    // spelling it cannot read is the point.
    engages: (command) => command.includes("git"),
    // The one hook Claude registers with onFailure: "block".
    failure: "deny",
  },
]

/** The one rewrite script, run in the shell.create.before hook. */
export const STRIP_REWRITE_HOOK = {
  name: "strip-redundant-cd",
  script: "strip-redundant-cd.sh",
  engages: (command) => /^cd /.test(command),
}

/**
 * Claude's hook output: `{ hookSpecificOutput: { permissionDecision,
 * permissionDecisionReason, updatedInput } }`. Returns `{decision, reason,
 * command}` or `undefined` when the hook stays silent (or writes something
 * JSON.parse cannot read — on a nonzero exit or a timeout the caller applies
 * the hook's failure posture separately, before this ever runs).
 */
export function parseHookOutput(stdout) {
  let data
  try {
    data = JSON.parse(stdout)
  } catch {
    return undefined
  }
  const out = data?.hookSpecificOutput
  const decision = out?.permissionDecision
  const result = { decision: undefined, reason: undefined, command: undefined }
  if (decision === "allow" || decision === "ask" || decision === "deny") result.decision = decision
  if (typeof out?.permissionDecisionReason === "string") result.reason = out.permissionDecisionReason
  if (typeof out?.updatedInput?.command === "string") result.command = out.updatedInput.command
  return result
}

/** Highest-ranked verdict from the spawn results, `undefined` for none. */
export function combineVerdicts(results) {
  let best
  for (const item of results) {
    if (item === undefined) continue
    if (best === undefined || RANK[item.decision] > RANK[best.decision]) best = item
  }
  return best
}

/**
 * The working directory the shell runs in. Claude's hook input carried the
 * session cwd; OpenCode's evaluate event carries none, so the bridge
 * reconstructs it: the tool's `workdir` when given, resolved against the
 * session directory. A non-existent directory falls back to the session
 * directory — the scripts resolve operands against the directory they are
 * told, and a resolution from the wrong base can only fail their checks,
 * never widen them (rm-guard allows only paths it can resolve *inside* the
 * disposable roots).
 */
export function resolveExecutionDir(base, cwd) {
  if (typeof cwd !== "string" || cwd === "") return base
  const expanded = cwd.startsWith("~") ? path.join(os.homedir(), cwd.slice(1)) : cwd
  const candidate = path.resolve(base, expanded)
  try {
    if (fs.statSync(candidate).isDirectory()) return candidate
  } catch {
    // fall through: the base is the only directory known to exist
  }
  return base
}

/**
 * Permission events without tool source (none today: the shell tool always
 * sets one) and events whose pairing fell through reconstruct the command
 * from the scanner-produced resources. Joining with " && " puts each
 * resource back into its own segment for the scripts — never glueing two
 * commands into one token — and a reconstruction the scripts cannot parse
 * degrades to "no verdict", the safe direction. A missing or non-array
 * resources field is the same no-op: this cannot throw, because an
 * exception from a judgment side must never break the permission flow.
 */
export function commandFromResources(resources) {
  return Array.isArray(resources) ? resources.join(" && ") : ""
}

/** Key for pairing a tool call with its permission evaluation. */
export function pairKey({ messageID, id }) {
  return `${messageID}:${id}`
}

/**
 * The evaluate event carries the tool-call identity only inside `source`
 * (Permission.Source); execute.before/after carry it top level.
 */
export function eventPair(event) {
  const source = event.source
  return source ? pairKey(source) : undefined
}

// ── process plumbing ──────────────────────────────────────────────────

/**
 * Run one hook script: JSON on stdin, capture stdout/stderr, kill after
 * `timeoutMs`. `runHook` never throws: every outcome is data — spawn errors,
 * nonzero exits and timeouts all land in `{failed: true, reason}`.
 */
export function runHook(file, { stdin, cwd, env, timeoutMs }, spawnImpl = spawn) {
  return new Promise((resolve) => {
    let settled = false
    const once = (value) => {
      if (settled) return
      settled = true
      resolve(value)
    }
    let child
    try {
      // The scripts' PATH and HOME come from this process: `env` carries only
      // the hook contract's additions (CLAUDE_PROJECT_DIR), layered on top.
      child = spawnImpl(file, [], { cwd, env: { ...process.env, ...env } })
    } catch (error) {
      return once({ failed: true, reason: String(error.message) })
    }
    const timer = setTimeout(() => {
      once({ failed: true, reason: "timed out" })
      try {
        child.kill()
      } catch {
        // already gone
      }
    }, timeoutMs)
    let stdout = ""
    let stderr = ""
    child.stdout?.on?.("data", (chunk) => {
      stdout += chunk
    })
    child.stderr?.on?.("data", (chunk) => {
      stderr += chunk
    })
    // The script may exit without reading all of stdin; EPIPE there is its
    // choice, not a bridge failure.
    child.stdin?.on?.("error", () => {})
    child.on("error", (error) => {
      clearTimeout(timer)
      once({ failed: true, reason: String(error.message) })
    })
    child.on("close", (code, signal) => {
      clearTimeout(timer)
      if (settled) return // the timeout (or a spawn error) already decided
      if (code !== 0) {
        once({ failed: true, reason: `exit ${code}${signal ? ` (${signal})` : ""}: ${tail(stderr)}` })
        return
      }
      once({ failed: false, stdout })
    })
    child.stdin?.end?.(stdin)
  })
}

function tail(text) {
  const lines = text.trim().split("\n")
  return lines.slice(-3).join("; ").slice(0, 400)
}

// ── the plugin wiring ─────────────────────────────────────────────────

/**
 * Register the hooks on the plugin context. Everything node-observable is
 * injected: `sessionGet` (default ctx.session.get) and `spawnImpl`. Tests
 * drive it with stub session lookup and mock scripts.
 *
 * Returns the small state the tests inspect: the pending tool-call stash.
 * An entry a never-evaluating shell leaks costs one command's memory, and
 * execute.after clears it; the cap is for a flood of tool calls between the
 * two events.
 */
export async function registerGuardBridge(ctx, deps = {}) {
  const hooksDir = deps.hooksDir ?? path.join(os.homedir(), ".claude", "hooks")
  const timeoutMs = deps.timeoutMs ?? HOOK_TIMEOUT_MS
  const sessionGet = deps.sessionGet ?? ((sessionID) => ctx.session.get({ sessionID }))
  const spawnImpl = deps.spawnImpl ?? spawn

  const scriptPath = (file) => path.join(hooksDir, file)
  const exists = {}
  const scriptExists = (file) => {
    if (exists[file] === undefined) {
      try {
        exists[file] = fs.statSync(scriptPath(file)).isFile()
      } catch {
        exists[file] = false
      }
    }
    return exists[file]
  }

  // One command per pending shell tool call, set by execute.before,
  // consumed by evaluate or cleared by execute.after.
  const pending = new Map()

  await ctx.tool.hook("execute.before", (event) => {
    if (event.tool !== SHELL_TOOL) return
    if (typeof event.input?.command !== "string" || event.input.command === "") return
    pending.set(pairKey(event), {
      command: event.input.command,
      workdir: typeof event.input.workdir === "string" ? event.input.workdir : undefined,
    })
    // Keep at most the freshest 128: every execute.before sets exactly one
    // entry, so the cap trims one at a time.
    if (pending.size > 128) pending.delete(pending.keys().next().value)
  })

  await ctx.tool.hook("execute.after", (event) => {
    if (event.tool === SHELL_TOOL) pending.delete(pairKey(event))
  })

  // The scripts' operating context: execution cwd. Its unset base is the
  // session's location directory, cached per session.
  const sessionDirs = new Map()
  const sessionDirOf = async (sessionID) => {
    const cached = sessionDirs.get(sessionID)
    if (cached) return cached
    let dir = ctx.location.directory
    try {
      const session = await sessionGet(sessionID)
      if (typeof session?.location?.directory === "string") dir = session.location.directory
    } catch {
      // Not resolvable here; the plugin's own location is the best available.
    }
    sessionDirs.set(sessionID, dir)
    return dir
  }

  const spawnHook = async (hook, { command, cwd, projectDir }) => {
    if (!scriptExists(hook.script)) return undefined
    const out = await runHook(
      scriptPath(hook.script),
      {
        stdin: JSON.stringify({ tool_input: { command }, cwd }),
        cwd,
        env: { CLAUDE_PROJECT_DIR: projectDir },
        timeoutMs,
      },
      spawnImpl,
    )
    if (out.failed) return { failed: true, reason: out.reason }
    return { failed: false, parsed: parseHookOutput(out.stdout) }
  }

  // Rewrites go through shell.create.before — the only hook that can change
  // the command, and (per packages/core/src/shell.ts) the one that runs
  // before the command is scanned into permission resources, so the rewrite
  // is what the rules then see: Claude's updatedInput treatment.
  await ctx.shell.hook("create.before", async (event) => {
    if (!STRIP_REWRITE_HOOK.engages(event.command)) return
    // The event cwd may be the raw tool input; make it an existing absolute
    // directory before the script resolves the cd target against it.
    const cwd = resolveExecutionDir(ctx.location.directory, event.cwd)
    const out = await spawnHook(STRIP_REWRITE_HOOK, { command: event.command, cwd, projectDir: cwd })
    // A failed hygiene rewrite is the command as written, nothing more.
    if (out === undefined || out.failed) return
    if (out.parsed?.command && out.parsed.command !== event.command) event.command = out.parsed.command
  })

  await ctx.permission.hook("evaluate", async (event) => {
    if (event.action !== SHELL_TOOL) return
    const key = eventPair(event)
    const entry = key === undefined ? undefined : pending.get(key)
    if (key !== undefined) pending.delete(key)
    const command = entry?.command || commandFromResources(event.resources)
    if (typeof command !== "string" || command === "") return

    const cwd = resolveExecutionDir(await sessionDirOf(event.sessionID), entry?.workdir)

    // The engaged scripts run concurrently, like Claude Code runs its
    // matching PreToolUse hooks. Each verdict is independent; the combination
    // rule below is where the ranking lives.
    const verdicts = await Promise.all(
      JUDGMENT_HOOKS.map(async (hook) => {
        if (!hook.engages(command)) return undefined
        const out = await spawnHook(hook, { command, cwd, projectDir: cwd })
        // A script missing because ~/.claude/hooks does not exist on an
        // OpenCode-only machine is absent, not failing: degrade to the rules
        // instead of denying every command with a git substring.
        if (out === undefined) return undefined
        if (out.failed) {
          if (hook.failure !== "deny") return undefined
          return {
            decision: "deny",
            reason: `guard-bridge: ${hook.name} failed (${out.reason}); refusing a command it could not inspect, as the hook's onFailure: "block" does in Claude Code.`,
          }
        }
        if (out.parsed?.decision === undefined) return undefined
        return { decision: out.parsed.decision, reason: out.parsed.reason }
      }),
    )

    const verdict = combineVerdicts(verdicts)
    if (verdict === undefined) return
    // deny/ask/allow rank against the configured effect the way Claude ranks
    // hook decisions: nothing softens a configured deny (OpenCode already
    // enforced those before this hook fired), and an approval carries the
    // reason the script gave.
    event.effect = verdict.decision
    if (verdict.reason) event.message = verdict.reason
  })

  return { pending, sessionDirs, scriptExists }
}
