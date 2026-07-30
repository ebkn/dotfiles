# AI Agent app (Node.js / TypeScript)

Read `references/typescript.md` first — package.json, `.npmrc`, biome, vitest, knip, and tsconfig come from there. This file adds only what an AI-agent CLI or worker needs on top.

Resolve every version at scaffold time — see the rule in SKILL.md. That rule covers **model IDs** here too: a model ID is a version-shaped value, and the one written below is only as fresh as the last edit to this file.

## Intake additions

Ask two more questions before scaffolding:

1. **Shape** — `cli` (runs one job per invocation and exits) or `worker` (long-running process that consumes work from somewhere). This selects the entry-point template below and the Biome `noConsole` treatment: `cli` removes the rule entirely, `worker` uses the `api` relaxation — both exactly as `references/typescript.md` already prescribes for those types.
2. **Harness** — `sdk` (default: `@anthropic-ai/sdk` with the beta tool runner — the agent's tools are functions you write) or `agent-sdk` (`@anthropic-ai/claude-agent-sdk` — Claude Code packaged as a library, with built-in file/bash/search tools). Choose `agent-sdk` only when the agent's job is operating on files and shells the way Claude Code does; for everything else — API-calling agents, pipeline workers, chat backends — the plain SDK is smaller and the tools stay explicit. If `agent-sdk` is chosen, scaffold everything in this file **except** `src/agent.ts`/`src/tools.ts`, and point the user at the Agent SDK docs (`https://code.claude.com/docs/en/agent-sdk`) for the harness code — its API moves too fast to template here.

## Runtime dependencies

```bash
npm install @anthropic-ai/sdk
```

Nothing else. Two dependencies are deliberately **absent**:

- **No `dotenv`.** Node ≥ 22.9 loads env files natively via `--env-file-if-exists=.env` (the `-if-exists` form matters: plain `--env-file` errors when the file is missing, which would break CI and fresh checkouts where no `.env` exists). The scripts below bake the flag in.
- **No `zod`.** The SDK's `betaTool()` helper (`@anthropic-ai/sdk/helpers/beta/json-schema`) takes a raw JSON-Schema `inputSchema` plus a `run` function, so the scaffold's tool needs no schema library. If the project's tools grow complex enough to want inferred types, upgrade to `betaZodTool` + `zod` then — one dep added deliberately, not by default.

## Model selection

Write the model ID into **one place** (`src/agent.ts` below) so a future migration is a one-line change. The current default for agent work is `claude-opus-5` — but verify at scaffold time that it is still the recommended current model, the same way tool versions are resolved: WebFetch `https://platform.claude.com/docs/en/about-claude/models/overview.md` and use the current Opus-tier ID it recommends. Record the chosen ID and date in the CLAUDE.md Constraints section so the next reader knows when it was last resolved.

## package.json scripts

Add to the base scripts from `references/typescript.md`, and **drop `--passWithNoTests` from `test`** (this scaffold ships a real test, so the zero-tests state should never occur — same reasoning as the Next.js path):

```json
"start": "node --env-file-if-exists=.env src/index.ts",
"dev": "node --watch --env-file-if-exists=.env src/index.ts"
```

There is still no `build` script. Node ≥ 23.6 (and 22.18+) executes TypeScript directly by stripping types, so the runtime runs `src/` as-is and `typecheck` remains the only `tsc` invocation — the same no-emit stance as plain TypeScript, now covering execution too. The `.nvmrc` from `references/typescript.md` pins a current LTS, which satisfies this; if the pinned Node somehow cannot run `.ts` files (the verification below catches it), add `tsx` as a devDependency and prefix the two scripts with it rather than adding a build step.

CLI invocations pass arguments after `--`: `npm start -- "summarize this repo"`.

## tsconfig.json additions

Add two options to the base `compilerOptions`:

```json
"erasableSyntaxOnly": true,
"allowImportingTsExtensions": true
```

These two are a **pair with the runtime choice above**, not style preferences:

- Node's type stripping only handles *erasable* TypeScript — `enum`, `namespace`, and constructor parameter properties need real transpilation and crash at runtime. `erasableSyntaxOnly` makes `tsc` reject those constructs at typecheck time, so the gate fails where CI can see it instead of at `npm start`.
- Node rewrites nothing, so relative imports must name the real file on disk: `import { x } from "./tools.ts"` — with the `.ts` extension. `allowImportingTsExtensions` is what lets `tsc` accept that form, and it is only legal because the base tsconfig sets `noEmit: true`. Do not "fix" imports back to `.js` extensions; they would typecheck and then fail at runtime.

Record both in the CLAUDE.md Constraints section — a future reader who removes either one gets a tree that typechecks but does not run (or vice versa).

## .env.example and credentials

Create `.env.example` (the one env file `.gitignore` keeps tracked; real values go in `.env`, which is ignored and covered by the `deny` rules from SKILL.md Step 5):

```
ANTHROPIC_API_KEY=sk-ant-...
```

Note in the CLAUDE.md Development section that the key is optional on a developer machine: the SDK's zero-arg constructor also resolves credentials from `ANTHROPIC_AUTH_TOKEN` or an `ant auth login` profile, so `new Anthropic()` works after an interactive login with no env file at all. CI never needs the key — see the test rule below.

## Scaffolded source

Three small files plus one test. The split is deliberate: `tools.ts` holds pure logic the test can exercise offline, `agent.ts` holds the one API-touching function with the model pin, `index.ts` holds the process concerns (args or shutdown).

The tool-runner surface is **beta** — verify the exact helper names against the installed SDK before writing these files (`npm view @anthropic-ai/sdk version`, then check the repo's `helpers.md` at that tag if anything below fails to typecheck). Fix the scaffold to match the SDK, not the other way around.

### `src/tools.ts`

One real tool, with the executable logic exported separately so the test needs no SDK, no network, and no key:

```ts
import { betaTool } from "@anthropic-ai/sdk/helpers/beta/json-schema";

export function currentTime(timezone: string): string {
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "long",
    timeZone: timezone,
  }).format(new Date());
}

export const getCurrentTime = betaTool({
  name: "get_current_time",
  description:
    "Get the current date and time in a given IANA timezone. Call this whenever the answer depends on the current time.",
  inputSchema: {
    type: "object",
    properties: {
      timezone: {
        type: "string",
        description: "IANA timezone name, e.g. Asia/Tokyo",
      },
    },
    required: ["timezone"],
  },
  run: (input) => currentTime(input.timezone),
});
```

The prescriptive "call this whenever…" description is intentional — current models trigger tools more reliably when the description says *when* to call, not just what it does. Keep that style for real tools.

### `src/agent.ts`

```ts
import Anthropic from "@anthropic-ai/sdk";

import { getCurrentTime } from "./tools.ts";

// Resolved at scaffold time — see CLAUDE.md Constraints before changing.
const MODEL = "{resolved current model id}";

export async function runAgent(prompt: string): Promise<string> {
  const client = new Anthropic();

  // The tool runner drives the request → execute tools → loop cycle.
  // max_tokens stays ≤ ~16000 while this call is non-streaming; switch to
  // the streaming runner (stream: true) before raising it, or the request
  // risks HTTP timeouts.
  const message = await client.beta.messages.toolRunner({
    model: MODEL,
    max_tokens: 16000,
    tools: [getCurrentTime],
    messages: [{ role: "user", content: prompt }],
  });

  // Safety classifiers on current models can decline a request with a
  // normal 200 — check stop_reason before reading content.
  if (message.stop_reason === "refusal") {
    throw new Error("The model declined this request (stop_reason: refusal).");
  }

  return message.content
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("\n");
}
```

### `src/index.ts` — `cli` shape

```ts
import { parseArgs } from "node:util";

import { runAgent } from "./agent.ts";

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { help: { type: "boolean", short: "h" } },
});

// --help must exit before any SDK construction: it is what lets CI and the
// scaffold verification run this entry point with no credentials.
if (values.help || positionals.length === 0) {
  console.log('Usage: npm start -- "<prompt>"');
  process.exit(values.help ? 0 : 1);
}

console.log(await runAgent(positionals.join(" ")));
```

### `src/index.ts` — `worker` shape

The scaffold cannot know where work comes from (a queue, a schedule, a webhook relay), so the loop body is an explicit TODO — the value here is the shutdown handling, which is easy to get wrong later:

```ts
import { parseArgs } from "node:util";

import { runAgent } from "./agent.ts";

const { values } = parseArgs({
  options: { help: { type: "boolean", short: "h" } },
});

if (values.help) {
  console.info("Usage: npm start  (long-running worker; SIGINT/SIGTERM to stop)");
  process.exit(0);
}

// Abort-based shutdown: in-flight work finishes, the loop exits cleanly,
// and a second signal still hard-kills via Node's default handler.
const shutdown = new AbortController();
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    console.info(`${signal} received — finishing current job`);
    shutdown.abort();
  });
}

while (!shutdown.signal.aborted) {
  // TODO: replace with the real work source (queue poll, schedule, …).
  // const job = await nextJob(shutdown.signal);
  // console.info(await runAgent(job.prompt));
  await new Promise((resolve) => setTimeout(resolve, 1_000));
}

console.info("worker stopped");
```

For a containerized worker, note in the CLAUDE.md Development section that orchestrators need a liveness signal — either process-level (restart policy on exit) or a minimal HTTP health endpoint added when deployment is real. This scaffold does not ship an HTTP server for the same reason the Go reference doesn't: it would be speculative code.

### The test — `src/tools.test.ts`

The one test the scaffold ships, and the reason `--passWithNoTests` is dropped. It exercises the tool's real contract (a valid IANA zone formats, an invalid one throws) and runs with **no network and no API key**:

```ts
import { describe, expect, it } from "vitest";

import { currentTime } from "./tools.ts";

describe("currentTime", () => {
  it("formats the current time for a valid IANA timezone", () => {
    expect(currentTime("Asia/Tokyo")).toMatch(/\d{4}/);
  });

  it("rejects an invalid timezone", () => {
    expect(() => currentTime("Not/AZone")).toThrow(RangeError);
  });
});
```

**Record the no-network test rule in the CLAUDE.md Development → Test section:**

> Tests never call the Anthropic API. CI has no `ANTHROPIC_API_KEY`, so any test that constructs a live client fails there by design. Test agent behavior by extracting pure logic (as `tools.ts` does) or by injecting a fake client; treat a test that needs a real key as a manual eval script, not part of `npm test`.

This is the correct default for both cost and determinism — an API-calling test suite bills real tokens on every CI run and flakes on model output.

## .claude/settings.json entries

Use the standard TypeScript entries from `references/typescript.md`. Two script entries are deliberately **not** allow-listed, for the same reason that path excludes the vitest watcher:

- `npm start` / `npm run dev` — `dev` is a watcher (long-running interactive process), and both execute the agent, which spends real API credits. An agent run should be a deliberate human action, not something auto-approved.

## Verification

First normalize formatting once (`npm run lint:fix` — hand-copied snippets won't match Biome's formatter), then run the full gate set:

```bash
npm run typecheck
npm run lint
npm run knip      # src/index.ts is a knip default entry; tools/agent are reached from it
npm test
node --env-file-if-exists=.env src/index.ts --help
```

All five must pass **without any `.env` present** — that is the state a fresh checkout and CI start in. The last line is the one that validates the runtime decisions stack end-to-end: Node executing `.ts` directly, `.ts`-extension imports resolving, env-file flag tolerating absence, and the `--help` path exiting before any credential is needed. If it fails on type stripping (older pinned Node), apply the `tsx` fallback from the scripts section and re-run; if it fails inside the SDK import, re-check the helper names against the installed SDK version as noted above.
