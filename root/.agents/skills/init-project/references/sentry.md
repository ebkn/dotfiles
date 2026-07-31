# Sentry — error tracking (optional overlay)

Read this only when intake question 7 answered `sentry`, and read it at SKILL.md **Step 9** — after the language reference and after CI. Every stack below edits files those steps created.

Resolve every version at scaffold time — see the rule in SKILL.md. That rule bites unusually hard here, because Sentry renames options *within* a major line rather than only across one: in the current JavaScript v10 line `sendDefaultPii` is already deprecated in favour of `dataCollection`, and `enableLogs` has moved out of `_experiments` to the top level — both while v10 is still current. An option list written from memory can therefore be accepted, deprecated, and wrong all at once. Before writing any option this file does not name, check the installed SDK's own type declarations (`node_modules/@sentry/core/build/types/types/options.d.ts` for the JS SDKs) rather than a blog post or an older docs page.

## What this overlay does — and the line it does not cross

It wires the SDK into the project's real entry points and reads the DSN from the environment. It does **not** create a Sentry account, org, or project, does not write a DSN into the repo, and does not upload source maps or debug symbols from a developer machine. That split is what lets error tracking be scaffolded at init time at all: the code lands now, the account decision stays with the user.

To actually provision the project and get a DSN, point the user at Sentry's own tooling rather than reproducing it here — `https://sentry.io/signup`, or the **`sentry-get-started`** skill if this environment has it (Sentry's official skill: it provisions the project, installs/verifies the SDK, and confirms a real event arrives). Record whichever route in the CLAUDE.md Launch Readiness section.

**Do not run `npx @sentry/wizard` as part of this scaffold.** It is the right tool on an empty project and the wrong one here: it rewrites `next.config.ts`, `app/global-error.tsx`, and the instrumentation files that Step 7 just wrote deliberately — including the security-header block and the `ErrorBoundary` rename that `references/nextjs.md` documents as load-bearing — and it writes a live auth token to disk. Hand the user the wizard *after* the scaffold if they want the guided account flow, and expect to re-review the diff.

## The DSN-optional rule — why this is safe to scaffold before an account exists

Every SDK used below treats a missing DSN as "disabled", not as an error. That is what makes the scaffold verifiable on a machine with no Sentry account: the gates run, the code is exercised, and nothing is sent.

| SDK | Missing-DSN behavior | Evidence |
|---|---|---|
| `@sentry/*` (JS, v10) | `Client` constructor skips `makeDsn` and never constructs a transport, so it is a true no-op rather than a discard-at-send. The "No DSN provided" warning is gated behind `DEBUG_BUILD`, so a production bundle is silent. | `@sentry/core` compiled `client.js` constructor |
| `sentry-sdk` (Python) | `make_transport()` only instantiates a transport `if options["dsn"]`, and every send is guarded by `if self.transport is not None`. No exception. | `sentry_sdk/transport.py`, `sentry_sdk/client.py` |
| `sentry-go` | `setupTransport()` installs a `noopTransport` when `Dsn` is empty, and `Init` returns `nil`. The SDK's own comment names "setting the DSN to the empty string" as a supported way to drop all events. | `client.go` |
| `sentry-cocoa` | `SentrySDK.start` does no DSN validation; an unparseable/empty DSN is caught, logged, and reset to `nil`, and `SentryClient.isDisabled` then refuses to capture. | `Sources/Swift/Options.swift`, `Sources/Sentry/SentryClient.m` |

**"Missing" and "wrong" are not the same case.** A *malformed non-empty* DSN is a hard error in both the Python SDK (`BadDsn`, a `ValueError`, raised out of `sentry_sdk.init`) and the Go SDK (`Init` returns a non-nil error), and neither is caught for you. So the safe state is an **unset** variable, not a placeholder string — do not write `SENTRY_DSN=your-dsn-here` into `.env.example` as a value; leave it empty. This is also why the Go snippet below propagates `Init`'s error rather than discarding it: the only thing it can report is a config bug worth knowing about.

Python and Go additionally read `SENTRY_DSN` from the environment **on their own** when the option is omitted, so those snippets pass no `dsn`/`Dsn` at all. That is not laziness — it keeps the variable name in exactly one place instead of two.

Do not "improve" this by wrapping `Sentry.init` in an `if (process.env.SENTRY_DSN)` guard. The SDK already performs exactly that check internally, one layer down, so the guard is a branch that duplicates library behavior, never gets exercised in the environment where it would matter, and diverges from every Sentry doc a reader will compare against. It also creates two different runtime shapes — "initialized but disabled" and "never initialized" — where the SDKs are only documented for the first.

## Is the DSN a secret? No — but it still comes from the environment

A DSN is designed to be public: browser SDKs ship it in the client bundle, so any Next.js or other browser-side setup exposes it by construction. Treating it as a credential leads to pointless contortions (proxying it, injecting it at runtime into client code) that buy nothing.

It still belongs in the environment rather than in a committed source file, for two reasons that are not secrecy:

- **It differs per environment.** One literal in the repo means dev noise and production events land in the same project, which is the failure that makes teams stop trusting the dashboard.
- **A public DSN accepts events from anyone.** The realistic abuse is quota exhaustion, not data theft. That is a rate-limit and inbound-filter problem to handle in Sentry's project settings, not a reason to hide the string — note it in Launch Readiness rather than pretending the env var solved it.

Where it comes from differs per stack, because each path already picked an env mechanism and this overlay does not introduce a second one:

| Stack | Variable | Delivered by |
|---|---|---|
| Next.js | `NEXT_PUBLIC_SENTRY_DSN` (client) + `SENTRY_DSN` (server/edge) | `.env.local`, documented in `.env.example` |
| AI agent / plain TypeScript | `SENTRY_DSN` | `.env`, loaded by `--env-file-if-exists`; documented in `.env.example` |
| Cloudflare Workers | `SENTRY_DSN` | `.dev.vars` locally, `wrangler secret put` in production |
| Go, Python | `SENTRY_DSN` | the process environment — read by the SDK itself |
| Swift (macOS) | `SENTRY_DSN` | the process environment, read by the SDK — but see the Swift section, this does not survive a Finder launch |

The Go and Python paths get **no `.env.example`**, deliberately: neither reference scaffolds a dotenv loader, so a committed template would document a file nothing reads. Set the variable the way the deployment already sets variables (shell export, systemd unit, container env). If the project later adopts `godotenv` or `python-dotenv`, add `.env.example` then — `.gitignore` already keeps it the one tracked env file.

The one genuine secret in this overlay is the **auth token** used for source-map / dSYM upload. It never goes in the repo; see the CI section.

## PII stays off — a deliberate divergence from Sentry's onboarding snippet

Sentry's own getting-started snippets enable PII collection and describe it as adding user IP addresses and request headers. The scaffold does **not** enable it, on any stack — which conveniently means simply omitting the option, whatever it is called this month.

And it is called something different in every SDK right now, so do not assume symmetry:

| SDK | Current option | State |
|---|---|---|
| JavaScript v10 | `dataCollection` | `sendDefaultPii` deprecated, ignored when `dataCollection` is set, removed in v11 |
| Go v0.48+ | `DataCollection` | stable; `SendDefaultPII` deprecated and ignored when `DataCollection` is set — **the Go docs still show the deprecated form** |
| Python 2.66 | `send_default_pii` | current and correct; `data_collection` exists only under `_experiments` |

Omitting all of them is the off state in every case, so the scaffold sidesteps the whole matrix. It matters only when someone later turns PII on and reaches for the wrong spelling.

This is the same correct-by-default direction as the deny-all `Permissions-Policy` in `references/nextjs.md`: a fresh project has no privacy review, no data-retention decision, and possibly no idea yet what its request bodies will contain — and PII sent to a third-party processor is not retractable by editing the code later. Turning it on is one line whenever the project decides it wants IPs and request bodies; turning it *off* after a year of collection is a deletion request.

Record the decision in the CLAUDE.md Constraints section so a reader following the Sentry docs verbatim does not "fix" the scaffold back to the docs' default without making that call deliberately.

## Sample rates — errors are the baseline, tracing is metered

Errors are what the intake question asked for. Tracing is a separate, quota-consuming product that Sentry's snippets enable at `1.0` with an explicit "adjust this in production" comment attached.

Scaffold the environment-split form the docs recommend — full sampling locally, a low rate in production:

```ts
tracesSampleRate: process.env.NODE_ENV === "development" ? 1 : 0.1,
```

Two honest caveats to keep with it: `0.1` is a starting guess, not a calibrated value — it should be revisited against real traffic and the plan's quota — and dropping the option entirely is a legitimate choice if the project only wants error tracking. Delete the line rather than setting `0`; the intent reads more clearly.

**Go needs two options where the others need one.** `TracesSampleRate` alone does nothing there: `sentry-go` checks `EnableTracing` first and drops every transaction when it is false, logging `Dropping transaction: EnableTracing is set to false`. So the Go snippet below sets both. (Despite what you might expect from the JS and Python SDKs, `EnableTracing` is *not* deprecated — it is load-bearing.) Logs are inverted the same way: Python opts in with `enable_logs=True`, Go opts *out* with `DisableLogs`.

## Not scaffolded on purpose

- **Session Replay and User Feedback** (JS). Both are opt-in products with real bundle-size and privacy weight — replay records DOM mutations. Adding them is a product decision, not a scaffold default. (Session Replay is also not supported on macOS at all — see the Swift section.)
- **Profiling.** Same reasoning, plus it needs its own sample-rate calibration.
- **`library` projects.** A library must never call `Sentry.init`: init is global, single-client, process-wide state, so a library that initializes it hijacks the host application's error reporting and silently redirects the host's events to the library author's project. Libraries should throw or return errors and let the application decide. SKILL.md skips intake question 7 for `library` for this reason — if a user asks anyway, explain it rather than scaffolding it.

---

## Next.js

### Install

```bash
npm install @sentry/nextjs
```

`.npmrc` (`save-exact`, `min-release-age=7`) governs this install exactly as it does the others.

### `.env.example` and the two DSN variables

The client and server halves cannot read the same variable, and this is the detail most hand-written Sentry setups get wrong. `instrumentation-client.ts` is compiled into the browser bundle, where Next.js only inlines env vars prefixed `NEXT_PUBLIC_` — a bare `process.env.SENTRY_DSN` there is `undefined` at runtime, which (per the DSN-optional rule above) fails *silently* as a disabled SDK rather than as an error. Append both to `.env.example`, creating the file if this project type never got one (`references/nextjs.md` only creates it on the `public-web` SEO path):

```
NEXT_PUBLIC_SENTRY_DSN=
SENTRY_DSN=
```

They normally hold the same value. Real values go in `.env.local`, which `.gitignore` already covers.

### `instrumentation-client.ts` (project root, or `src/` if the app uses one)

```ts
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: process.env.NODE_ENV === "development" ? 1 : 0.1,
});

// Required for navigation spans in the App Router.
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
```

This filename — not `sentry.client.config.ts` — is the current form. `instrumentation-client.ts` is a Next.js file convention introduced in **Next.js 15.3**, and it is the only client-side form the current Sentry docs show. If the installed Next.js is older than 15.3, use `sentry.client.config.ts` instead and record the reason in CLAUDE.md Constraints.

### `sentry.server.config.ts` and `sentry.edge.config.ts`

Both files, identical contents (they are separate because the two runtimes initialize separately):

```ts
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: process.env.NODE_ENV === "development" ? 1 : 0.1,
});
```

Create the edge file even if the project has no edge-runtime code today. It costs nothing when the edge runtime is never loaded, and its absence is a silent gap the day someone adds middleware.

### `instrumentation.ts` (project root)

```ts
import * as Sentry from "@sentry/nextjs";

export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    await import("./sentry.server.config");
  }

  if (process.env.NEXT_RUNTIME === "edge") {
    await import("./sentry.edge.config");
  }
}

// Reports errors thrown in Server Components, Route Handlers, and middleware.
export const onRequestError = Sentry.captureRequestError;
```

`onRequestError` needs `@sentry/nextjs` ≥ 8.28 and Next.js 15+; on an older Next.js drop that export and note the gap in CLAUDE.md.

### The error boundaries — every one of them needs its own capture

This is the step most hand-rolled Next.js setups get wrong, and the failure is invisible: an error caught by a React error boundary is handled, so it never reaches Sentry's global handler. The Sentry docs are explicit — *"Next.js `error.tsx` files catch rendering errors to show a fallback UI. This is good for UX but means errors never reach Sentry's global handler"* — and the fix is to add `captureException` in **every** boundary, at every level of the `app/global-error.tsx` → `app/error.tsx` → `app/**/error.tsx` hierarchy.

The manual-setup file list mentions only `global-error.tsx`, which reads as though it were sufficient. It is not, and it is the *rarer* of the two: `global-error.tsx` fires only when the root layout itself fails, while route-level `error.tsx` catches everything else first. `references/nextjs.md` scaffolded both files, so both get edited here — and the same rule applies to every `error.tsx` added later. Record that in CLAUDE.md so it is not rediscovered by finding an empty Sentry dashboard.

`app/error.tsx` — add the import, the hook, and the now-used `error` parameter:

```tsx
"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

// Not named `Error`: Biome's recommended `noShadowRestrictedNames` (error level)
// rejects shadowing the global, and Next.js keys this boundary off the filename,
// so the export name is free to differ from the docs' example.
export default function ErrorBoundary({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <div role="alert">
      <h2>Something went wrong</h2>
      <button type="button" onClick={() => reset()}>
        Try again
      </button>
    </div>
  );
}
```

`app/global-error.tsx` — same treatment. Edit the existing file rather than replacing it, so the error is both reported and rendered:

```tsx
"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html lang="en">
      <body>
        <h2>Something went wrong</h2>
        <button type="button" onClick={() => reset()}>Try again</button>
      </body>
    </html>
  );
}
```

In both files `error` moves from type-only to actually destructured — it was unused before, and Biome's `noUnusedVariables` (error level) is why it was omitted from the parameter lists in the first place. Keep the existing markup and `lang="en"`; the Sentry docs' version renders Next.js's built-in error page instead, discarding a decision the scaffold already made. Keep the `ErrorBoundary` rename comment too — `references/nextjs.md` records it as load-bearing.

### `next.config.ts` — wrap, keeping the security headers

`references/nextjs.md` owns this file's contents. Sentry wraps the exported config; the `securityHeaders` block and `poweredByHeader: false` stay exactly as they were:

```ts
import { withSentryConfig } from "@sentry/nextjs";
import type { NextConfig } from "next";

const securityHeaders = [
  // ...unchanged from references/nextjs.md
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

// `org`, `project`, and `authToken` are deliberately omitted: the bundler
// plugin falls back to SENTRY_ORG / SENTRY_PROJECT / SENTRY_AUTH_TOKEN, so
// no org slug or token is committed. See CLAUDE.md Launch Readiness.
export default withSentryConfig(nextConfig, {
  silent: !process.env.CI,
  widenClientFileUpload: true,
});
```

The docs' snippet passes `org` and `project` as literal slugs and the options table labels `authToken` "Required" — none of which is true, and following it verbatim puts your org slug in the repo for no benefit. `normalizeUserOptions` in `@sentry/bundler-plugin-core` resolves each option as `userOptions.x ?? process.env.SENTRY_X`, covering `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN`, `SENTRY_URL` (defaulting to `https://sentry.io`), and `SENTRY_RELEASE`. An explicit option always wins; the env var applies only when the option is absent. Verified in the published artifact rather than the docs, which do not state it.

One quirk to know before setting the env var: `SENTRY_PROJECT` is comma-split into an array (`"a,b"` → `["a","b"]`), while the explicit `project` option is not. Irrelevant for a single project; surprising if a slug ever contains a comma.

**A missing auth token does not fail the build.** The plugin logs `No auth token provided. Will not upload source maps.` and continues; missing `org`/`project` likewise warns and skips. That is what makes it safe to scaffold this wrapper before a Sentry account exists — the build stays green, the stack traces are just unminified until the credentials appear.

`silent: !process.env.CI` keeps local builds quiet while leaving CI logs intact. `widenClientFileUpload: true` extends source-map upload to Next.js-internal and dependency code, which is where a real production stack trace usually bottoms out.

Two options deliberately **not** set:

- **`tunnelRoute`** routes SDK traffic through your own Next.js server to evade ad-blockers. It works, and it also turns your app into a proxy for a third-party endpoint and moves the traffic onto your server bill. Add it if blocked events prove to be a real problem, not preemptively.
- **`telemetry`** (default `true`) sends build-plugin diagnostics to Sentry. Leave it unless the project's policy forbids it; set `telemetry: false` if so.

### knip and Biome

**Change nothing in `knip.json` for the layout above** — it is clean as scaffolded (verified empirically, not inferred). knip's Next.js plugin already treats `instrumentation.ts`, `instrumentation-client.ts`, `app/global-error.*`, and `app/**/error.*` as entry points, its Sentry plugin (auto-enabled by any `@sentry/*` dependency) adds `sentry.{client,server,edge}.config.{js,ts}`, and `@sentry/nextjs` is seen as used because `next.config.ts` imports `withSentryConfig`.

There is one fragile spot worth knowing rather than discovering: the Sentry plugin's pattern has **no `src/` variant**. In a `src/` layout the config files survive only because knip follows the `await import("./sentry.server.config")` calls in `instrumentation.ts`. So if you both move to `src/` *and* write an `instrumentation.ts` that does not dynamically import them, knip starts flagging them — and the fix is an `entry` declaration, never deleting the file:

```json
{ "entry": ["src/sentry.{client,server,edge}.config.ts!"] }
```

Run `npm run knip` to confirm either way. Then run `npm run lint:fix` once — the snippets above are hand-formatted and Biome's formatter will disagree about line breaks.

---

## AI agent (Node.js)

The Node SDK's auto-instrumentation must load before the modules it patches. Under ESM that means Node's `--import` flag, not a top-level `Sentry.init` in the entry file: importing `instrument.mjs` first from inside the entry file is documented but explicitly degraded — only native Node APIs (`fetch`, `http`) get instrumented, not database clients, queues, or third-party libraries.

### Install

```bash
npm install @sentry/node
```

### `src/instrument.ts`

```ts
import * as Sentry from "@sentry/node";

// Loaded via `node --import` so it runs before anything it instruments.
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 0.1,
});
```

### package.json scripts

Both scripts from `references/ai-agent.md` gain the flag, **after** the env-file flag:

```json
"start": "node --env-file-if-exists=.env --import ./src/instrument.ts src/index.ts",
"dev": "node --watch --env-file-if-exists=.env --import ./src/instrument.ts src/index.ts"
```

Flag order is load-bearing and was verified on Node 24.14.1: `--env-file-if-exists` is applied before `--import`, so `process.env.SENTRY_DSN` is already populated when `instrument.ts` runs. Reversing them would leave the SDK reading an empty env and silently disabling itself — the DSN-optional behavior turning into a footgun.

Also verified on the same Node: `--import ./src/instrument.ts` works with a **`.ts`** file under Node's native type stripping, so this path needs no build step and no `tsx`. Sentry's own docs only show `.mjs` and say nothing about type stripping, so treat the verification block below as the check that this still holds on the Node version actually pinned in `.nvmrc` — if it fails, compile or rename `instrument.ts` to `instrument.mjs` rather than abandoning `--import`.

### `.env.example`

Append `SENTRY_DSN=` alongside the existing `ANTHROPIC_API_KEY`.

### Capture and flush at the edges

A short-lived process can exit before queued events are sent, so the exit path must drain the SDK. `Sentry.close(timeout)` flushes *and* disables the client — correct immediately before exit; `Sentry.flush(timeout)` flushes and leaves the client usable, which is what a long-running worker wants mid-loop.

`src/index.ts`, `cli` shape — wrap the existing final line:

```ts
try {
  console.log(await runAgent(positionals.join(" ")));
} catch (error) {
  Sentry.captureException(error);
  await Sentry.close(2000);
  console.error(error);
  process.exit(1);
}
```

`src/index.ts`, `worker` shape — capture per iteration so one bad job does not kill the loop, and drain once on the way out:

```ts
try {
  // TODO: replace with the real work source (queue poll, schedule, …).
  await new Promise((resolve) => setTimeout(resolve, 1_000));
} catch (error) {
  Sentry.captureException(error);
}
```

then, after the loop and before `console.info("worker stopped")`:

```ts
await Sentry.close(2000);
```

Both shapes need `import * as Sentry from "@sentry/node";` at the top of `src/index.ts` — importing it there as well as in `instrument.ts` is correct, not duplication: the SDK is a module singleton, and `--import` guarantees `init` already ran.

### knip

`src/instrument.ts` is loaded by a CLI flag, so nothing imports it and knip will report it as an unused file — and `@sentry/node` as an unused dependency with it. Declare it:

```json
"entry": ["src/index.ts", "src/instrument.ts"]
```

### Tests stay offline

`references/ai-agent.md` already establishes that tests never call the Anthropic API. The same rule covers Sentry: CI has no `SENTRY_DSN`, so the SDK is inert there by construction, and no test should assert on Sentry behavior. If the project later wants to test capture logic, assert against a fake transport rather than a live DSN.

---

## Cloudflare Workers

### Install

```bash
npm install @sentry/cloudflare
```

### `wrangler.jsonc` — this path needs `nodejs_compat`

`references/cloudflare-workers.md` deliberately leaves `nodejs_compat` out, on the grounds that enabling it speculatively grows the runtime surface. That reasoning does not survive contact with this SDK: `@sentry/cloudflare` needs Node compatibility APIs (`AsyncLocalStorage`) to track request context, and the flag is a stated requirement, not an optimization.

```jsonc
{
  "compatibility_flags": ["nodejs_compat"]
}
```

`nodejs_compat` requires a `compatibility_date` of **2024-09-23 or later**; the scaffold sets that field to the scaffold date, so it is satisfied. Record in CLAUDE.md Constraints that the flag is there for Sentry — that is exactly the "constraint a future reader would otherwise undo" case, since the Workers reference argues against the flag in general terms.

The SDK's own integration tests still use the narrower `nodejs_als` flag, and it does work on the current v10 line. Prefer `nodejs_compat` anyway: it is what the docs specify, it is a superset, and Sentry's v11 migration notes list it as becoming mandatory.

### DSN via `.dev.vars` and a secret

`references/cloudflare-workers.md` picked `.dev.vars` as this path's secret file, already gitignored and already in both `deny` lists. Add:

```
SENTRY_DSN=
```

For production: `npx wrangler secret put SENTRY_DSN`.

### `src/index.ts`

```ts
import * as Sentry from "@sentry/cloudflare";

export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 0.1,
  }),
  {
    async fetch(request): Promise<Response> {
      const url = new URL(request.url);
      if (url.pathname === "/healthz") {
        return Response.json({ status: "ok" });
      }
      return new Response("{project-name}");
    },
  } satisfies ExportedHandler<Env>,
);
```

Two things to verify rather than assume, because no Sentry doc shows this exact combination:

- **The `satisfies ExportedHandler<Env>` placement.** The handler object is `withSentry`'s *second* argument, so the annotation moves onto that inner object literal — it can no longer sit on the default export. `npm run typecheck` is the check.
- **`env.SENTRY_DSN` must exist on the generated `Env`.** `Env` comes from `worker-configuration.d.ts`, regenerated by `wrangler types` as part of `typecheck`. Run `npm run typecheck` and confirm the property is there; if it is not, the fix is to make sure `.dev.vars` contains the key so wrangler derives it — never hand-edit the generated file, which `typecheck` overwrites on the next run.

### The vitest pool caveat

`@cloudflare/vitest-pool-workers` is not something Sentry tests against ([sentry-javascript#22523](https://github.com/getsentry/sentry-javascript/issues/22523)). The concrete hazard: `wrangler` bundles with esbuild and tree-shakes, while the vitest pool does not, so modules a real build would have dropped (`worker_threads` has been the observed case) get pulled into the test worker and can fail against an older `compatibility_date`. Expect `npm test` to be more sensitive to that date than `wrangler dev` is; if the pool fails on a module a real deploy never loads, bump `compatibility_date` before touching the SDK.

---

## Plain TypeScript (`cli`)

The plain TypeScript path scaffolds no entry point — `tsconfig.json`'s `include` names `src/**/*` before any `src/` exists — so there is nothing to instrument yet, and inventing an entry file to hold `Sentry.init` would be speculative code of exactly the kind the Go and Python health-endpoint sections refuse to write.

Install `@sentry/node` and create `src/instrument.ts` exactly as in the AI-agent section above. Because nothing imports it and there is no entry point that could, add it to `knip.json` now — otherwise the `knip` gate fails on the very scaffold that created it:

```json
{
  "$schema": "https://unpkg.com/knip@{installed-knip-major}/schema.json",
  "entry": ["src/instrument.ts"]
}
```

Note that this is the second deferred `knip.json` decision on this path — `references/typescript.md` already defers a `library`'s `"entry": ["src/index.ts"]` to the first source file. If both apply, they merge into one array rather than replacing each other.

Then record the wiring in the CLAUDE.md Development section, so the first real entry point picks it up instead of quietly running without instrumentation:

> Error tracking is wired but not yet loaded. `src/instrument.ts` calls `Sentry.init`; it must be preloaded — `node --import ./src/instrument.ts <entry>` — when the entry point is created, and that flag belongs in the `start`/`dev` scripts at the same time. Loading it via a normal `import` from the entry file instead limits instrumentation to native Node APIs.

---

## Go

### Install — check the toolchain floor first

```bash
go get github.com/getsentry/sentry-go
go mod tidy
```

`sentry-go`'s own `go.mod` declares `go 1.25.0`, which is a hard floor rather than a suggestion: the toolchain refuses to build against it on anything older. `references/go.md` pins the `go` directive to the exact installed toolchain, so if that is below 1.25 the choice is to upgrade Go or to skip this overlay — do **not** hand-lower the SDK's requirement. Check before installing; the failure otherwise lands in the middle of `go mod tidy` and looks like a proxy problem.

Adding the SDK pulls several error/testing libraries into `go.mod` (`pkg/errors`, `pingcap/errors`, `stretchr/testify`, `goleak`, …). They look alarming next to a scaffold that otherwise has zero dependencies, and they are **test-only**: `stacktrace.go` imports nothing but the standard library and names those packages only in comments. Go downloads their `go.mod` files but not their code, so they never enter the built binary and `govulncheck`'s call-graph analysis never reaches them. The verification below is what confirms that on the version actually installed.

### `main.go` — restructured so the flush actually runs

`references/go.md` scaffolds a three-line `main`. Sentry's docs would have you `defer sentry.Flush(...)` inside it, but their own snippet also calls `log.Fatalf` on init failure — and `log.Fatal`/`os.Exit` **do not run deferred functions**. Put together as written, the flush is skipped on exactly the exits that matter most. Split `main` from a `run() error` so `os.Exit` stays confined to a function with nothing deferred:

```go
package main

import (
	"fmt"
	"os"
	"time"

	"github.com/getsentry/sentry-go"
)

func main() {
	// os.Exit skips deferred calls, so everything that must flush lives in
	// run(); main() only translates the error into an exit status.
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	// Dsn is omitted on purpose: the SDK reads SENTRY_DSN itself and stays
	// disabled when it is unset. Only a malformed value errors here, and
	// that is a config bug worth failing on rather than swallowing.
	if err := sentry.Init(sentry.ClientOptions{
		EnableTracing:    true,
		TracesSampleRate: 0.1,
	}); err != nil {
		return fmt.Errorf("sentry.Init: %w", err)
	}
	defer sentry.Flush(2 * time.Second)

	fmt.Println("{project-name}")
	return nil
}
```

Notes that keep this passing the gates in `references/go.md`:

- **`Init`'s error must be handled.** `errcheck` is part of golangci-lint's `standard` set, so a bare `sentry.Init(...)` fails the lint gate. Returning it (rather than the docs' `log.Fatalf`) is also the better behavior: the wrapped message says what failed, and it does not kill an application because its telemetry config is wrong.
- **`Flush` returns a `bool`, not an `error`**, so `defer sentry.Flush(...)` does not trip `errcheck`. `sentry.DefaultFlushTimeout` is exported and equals `2 * time.Second` if you prefer the self-documenting form.
- **`unused` stays quiet** because `run` is called from `main`. Extracting an `initSentry()` helper and forgetting to wire it up is the one way to trip it.
- **No `SendDefaultPII`.** It is deprecated as of v0.48.0 in favour of `DataCollection` — a fact the Go docs page has not caught up with — and both stay omitted per the PII section above. Omission is the no-collection state.

For an `api` project, `references/go.md` still defers all server code, so this stays the only instrumented entry point until the server exists. Record in the CLAUDE.md Development section that the eventual HTTP server should add `sentryhttp` middleware rather than calling `CaptureException` by hand in each handler.

---

## Python

### Install

```bash
uv add sentry-sdk
```

This lands as a runtime dependency (not `--dev`) and is exact-pinned with hashes into `uv.lock` like everything else, under the `exclude-newer = "7 days"` quarantine.

It ships a `py.typed` marker, so **`mypy --strict` is satisfied with no stub package and no override** — worth stating explicitly, because `references/python.md` warns that the first untyped dependency will break the strict gate and this is the scaffold's first runtime dependency. It is not that dependency.

### `main.py`

`uv init --app` created this file and `references/python.md` already annotated `main()` for the strict gate. Add the init call:

```python
import sentry_sdk


def main() -> None:
    # No dsn=: the SDK reads SENTRY_DSN itself and stays disabled when unset.
    sentry_sdk.init(traces_sample_rate=0.1)
    print("Hello from {project-name}!")


if __name__ == "__main__":
    main()
```

Keep the comment short. The docs' version of this snippet carries a 95-character comment line that trips `E501` under the `E` rules `references/python.md` selects at `line-length = 88` — and `ruff format` does **not** reflow comments, so it is a manual fix, not an autofix.

`send_default_pii` is deliberately absent (see the PII section). Note that unlike Go and JavaScript, `send_default_pii` is still the *current* option name in Python — `data_collection` exists only under `_experiments` there — so if this project ever does enable PII, use `send_default_pii=True` and do not copy the Go or JS spelling.

### Shutdown — nothing to write

The Python SDK drains automatically at exit via its `AtexitIntegration`, so a CLI needs no explicit flush and the scaffold adds none. Only two things disable that: removing the integration, or setting `shutdown_timeout=0`. If a future entry point needs a mid-run checkpoint, the API is on the client, not the module:

```python
sentry_sdk.get_client().flush()
```

`close(timeout=...)` also drains but disables the client afterwards — correct immediately before exit, wrong anywhere else.

---

## Swift — macOS SwiftUI app

Three things here have no counterpart on the other paths, and all three fail *silently* if missed.

### The sandbox entitlement — without it, nothing is sent

`references/swift.md` scaffolds an App Sandboxed app with only `com.apple.security.files.user-selected.read-only`. The sandbox blocks outgoing network connections by default, so every event upload fails with no visible error unless `debug` is on. Add to the `entitlements.properties` block in `project.yml`:

```yaml
com.apple.security.network.client: true
```

Apple's documentation for `com.apple.security.network.client` — "A Boolean value indicating whether your app may open outgoing network connections" — is the authority here; Sentry's Apple docs never mention App Sandbox at all. There is no `com.apple.security.network.outgoing` key despite the Xcode checkbox being labelled "Outgoing Connections (Client)"; do not invent one. Crash-report disk writes need no extra entitlement: the SDK's cache path resolves inside the app container, which is always writable.

Record the entitlement's purpose in CLAUDE.md Constraints — `references/swift.md` states the sandbox rule as "opt capabilities back in per-need", and this is one of those opts, not a loosening.

### `project.yml` — package and product

```yaml
packages:
  Sentry:
    url: https://github.com/getsentry/sentry-cocoa
    exactVersion: {resolved sentry-cocoa version}

targets:
  {AppName}:
    dependencies:
      - package: Sentry
        product: SentrySPM
```

`exactVersion`, not `from:`, and this is a direct consequence of a decision `references/swift.md` already made. Xcode writes `Package.resolved` inside `{AppName}.xcodeproj/`, which that reference gitignores as generated output — so there is no committed resolution file, and a `from:` range would let CI and every fresh checkout resolve to a different SDK version than the one verified here. `exactVersion` puts the pin in the one file that *is* committed. Bumping it is then a deliberate edit, matching how every other version in this scaffold is pinned. Resolve the current release under the same 7-day quarantine as everything else.

`SentrySPM` is the product to depend on: it builds from source, which the docs call the recommended choice (debuggable, supports package traits), versus the prebuilt binary `Sentry`/`Sentry-Dynamic` products. **`SentrySwiftUI` is deprecated** — SwiftUI view performance tracking moved into the main product; do not add it. Also do not link both `Sentry` and `SentryObjC` into one target.

### `{AppName}/{AppName}App.swift`

```swift
import Sentry
import SwiftUI

@main
struct {AppName}App: App {
    init() {
        SentrySDK.start { options in
            // No `options.dsn`: on macOS the SDK reads SENTRY_DSN from the
            // environment, so the DSN stays out of the repo and the SDK
            // no-ops when it is unset.
            #if DEBUG
                options.debug = true
            #endif
            // macOS does not crash on uncaught NSExceptions, so without this
            // the most common AppKit failure is never reported.
            options.enableUncaughtNSExceptionReporting = true
            options.tracesSampleRate = 0.1
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`App.init()` is the SwiftUI placement the docs use, and it runs on the main thread, which is where the SDK wants to be started. The SDK also no-ops under Xcode previews (it checks `XCODE_RUNNING_FOR_PREVIEWS`), so previews stay clean.

`enableUncaughtNSExceptionReporting` defaults to `false` and is macOS-specific: "macOS applications don't crash whenever an uncaught exception occurs." The alternative is the `SentryCrashExceptionApplication` class via `NSPrincipalClass` — **use one or the other, never both**, or crashes are reported twice.

Two options from the docs' snippet are deliberately absent: `options.sessionReplay.*` (Session Replay is iOS-only — the shared docs include serves those lines to macOS readers, but the macOS Session Replay page says it is supported on iOS) and `options.sendDefaultPii` (see the PII section above).

### DSN delivery is a real limitation here, not a detail

The `SENTRY_DSN` environment fallback is macOS-only SDK behavior and it is genuinely convenient for development — set it in the Xcode scheme, or launch from a terminal. But **an app launched from Finder or the Dock does not inherit a shell environment**, so a shipped build gets no DSN this way. Reading it from `Info.plist` is not something the SDK does; you would do it yourself (`options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String` — the setter tolerates `nil`).

Record that in CLAUDE.md Launch Readiness rather than pretending it is solved: distribution needs the DSN injected at build time, via an `Info.plist` key from `project.yml` or a generated constant.

### dSYM upload — the difference between a stack trace and hex addresses

Without uploaded debug symbols, macOS crash reports arrive unsymbolicated and are close to useless, so unlike the other optional pieces this one is worth wiring even though it needs an account. It degrades safely: the script warns and continues when `sentry-cli` or the token is missing.

```yaml
targets:
  {AppName}:
    settings:
      configs:
        Release:
          DEBUG_INFORMATION_FORMAT: dwarf-with-dsym
      base:
        ENABLE_USER_SCRIPT_SANDBOXING: NO
    postBuildScripts:
      - name: Upload Debug Symbols to Sentry
        basedOnDependencyAnalysis: false
        inputFiles:
          - ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${EXECUTABLE_NAME}
        script: |
          if [[ "$(uname -m)" == arm64 ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
          fi
          if which sentry-cli >/dev/null; then
            ERROR=$(sentry-cli debug-files upload --include-sources "$DWARF_DSYM_FOLDER_PATH" 2>&1 >/dev/null)
            if [ ! $? -eq 0 ]; then
              echo "warning: sentry-cli - $ERROR"
            fi
          else
            echo "warning: sentry-cli not installed"
          fi
```

`DEBUG_INFORMATION_FORMAT` is scoped to Release on purpose — generating dSYMs on every Debug build is a noticeable local slowdown for symbols nobody uploads. `ENABLE_USER_SCRIPT_SANDBOXING: NO` is required for the script phase to read the dSYM folder. The current subcommand is `sentry-cli debug-files upload`; `upload-dif` is the legacy spelling.

Credentials (`SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN`) must **not** go in `project.yml` — it is committed. They belong in the CI environment or a gitignored `.sentryclirc`. `sentry-cli` itself installs via `brew install getsentry/tools/sentry-cli`; add it to the prerequisites check in `references/swift.md`'s style (check, don't install).

### Lint

The docs' snippet will not survive this project's gates as-is: it is 4-space indented while `swift format` defaults to 2, and its doc-link comments exceed the 100-column default (SwiftLint's 120 warning threshold will *not* catch those, so a green `swiftlint --strict` proves nothing here). Run `swift format --in-place --recursive {AppName} {AppName}Tests` once after writing the file, then let the gates judge substance.

---

## CI

Only the Next.js path needs a CI change: source-map upload happens during `npm run build`, so the build step needs the credentials. Add to the `npm run build` step in `.github/workflows/ci.yml`:

```yaml
      - run: npm run build
        env:
          SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
          SENTRY_ORG: ${{ vars.SENTRY_ORG }}
          SENTRY_PROJECT: ${{ vars.SENTRY_PROJECT }}
```

These are the three env vars the bundler plugin falls back to (see the `next.config.ts` section), which is why nothing here is duplicated into the committed config. The token is a real credential and goes in `secrets`; the org and project slugs are not, so they go in `vars` (`Settings → Secrets and variables → Actions`) where they stay readable in the workflow log.

This is safe to add **before** any of the three exists: an unset `secrets.*`/`vars.*` expands to an empty string, and the plugin warns and skips upload rather than failing the build. So CI stays green from the first push and starts uploading source maps the moment the values are filled in — no workflow edit needed. Record that in Launch Readiness, along with the token needing `project:releases` scope.

No other stack needs a CI change. The Node, Workers, Go, and Python paths upload nothing at build time, and every gate on every path runs with the SDK disabled, because no DSN is present in CI and none should be added — a green pipeline must not depend on reaching Sentry.

Swift is the one worth being explicit about rather than lumping in: it *does* have an upload step, but the `postBuildScripts` phase only produces dSYMs under the Release configuration, and the CI job in `references/swift.md` runs `xcodebuild test` (Debug). So CI uploads nothing, the script's `sentry-cli not installed` warning is the expected output there, and symbol upload happens on whatever machine builds the release artifact. If release builds later move into CI, that job needs `SENTRY_ORG`/`SENTRY_PROJECT`/`SENTRY_AUTH_TOKEN` and a `brew install getsentry/tools/sentry-cli` step.

## `.claude/settings.json`

Extend the two `deny` lists from SKILL.md Step 5 in lockstep with one more file:

```json
"Read(.env.sentry-build-plugin)",
"Edit(.env.sentry-build-plugin)"
```

This scaffold never creates that file — it is where `@sentry/wizard` writes a live auth token, which is a genuine credential. Pre-denying an absent path is inert and is the same defense the base list already applies to `.env.production` and `.env.staging`: if it ever appears, it is an untracked secret file. The `.gitignore`'s wholesale `.env*` rule already keeps it untracked, so this closes the read/overwrite half.

Also add `WebFetch(domain:docs.sentry.io)` to the `allow` list — the project now has a Sentry dependency, and an agent that has to prompt to read its docs will guess instead.

## CLAUDE.md

Two edits, both in sections SKILL.md Step 3 created:

**Launch Readiness** — replace the "Error tracking (e.g. Sentry)…" bullet, which is now wrong, with what is actually outstanding:

> - Sentry SDK is wired and stays disabled until a DSN is set. Remaining: create the Sentry project (`https://sentry.io/signup`, or the `sentry-get-started` skill); set `SENTRY_DSN` per environment; and set inbound filters / rate limits on the project, since a DSN is public and anyone holding it can spend the quota.

Add the line that matches the stack, and drop it otherwise — a checklist item for machinery this project does not have is worse than none:

> - Next.js only: also set `NEXT_PUBLIC_SENTRY_DSN` (the client bundle cannot read the unprefixed one), and add the `SENTRY_AUTH_TOKEN` secret plus `SENTRY_ORG`/`SENTRY_PROJECT` variables in GitHub Actions so CI uploads source maps. Until then production stack traces are minified.
> - Swift only: a Finder-launched app inherits no shell environment, so the DSN must be injected at build time before distribution; `sentry-cli` must be installed wherever release builds happen, or dSYMs never upload and crash reports stay unsymbolicated.

**Constraints** — record every decision above that a future reader would otherwise reverse: PII collection left off against the docs' default, the tracing sample rate being a guess, and whichever stack-specific ones apply (`nodejs_compat` added for Sentry on Workers; `exactVersion` on the Swift package because `Package.resolved` is not committed; the network-client entitlement).

## Verification

Sentry touches entry points and build config, so the check is the **language reference's own verification block, re-run in full** — not a Sentry-specific smoke test. A wrapper that breaks `next build` or an `--import` that breaks the CLI is the realistic failure mode, and only the existing gates catch it.

Run, per stack:

| Stack | Re-run |
|---|---|
| Next.js | `npm run lint:fix`, then the full block in `references/nextjs.md` — including the `rm -rf next-env.d.ts .next tsconfig.tsbuildinfo && npm run typecheck` check |
| AI agent | the block in `references/ai-agent.md`, ending with `node --env-file-if-exists=.env --import ./src/instrument.ts src/index.ts --help` |
| Cloudflare Workers | the block in `references/cloudflare-workers.md`, including the `wrangler types` regeneration check |
| Plain TypeScript | the block in `references/typescript.md` |
| Go | the block in `references/go.md` — `govulncheck` especially, since this is the module's first real dependency and the first genuine exercise of that gate |
| Python | the block in `references/python.md` |
| Swift | `swift format --in-place --recursive {AppName} {AppName}Tests`, then the block in `references/swift.md` |

All of these must pass **with no DSN set anywhere** — that is the state of a fresh checkout and of CI, and it is the state the DSN-optional rule exists to make safe. A gate that only passes once a DSN is present means `Sentry.init` is being called somewhere it can throw; fix that rather than exporting a DSN to make the check go green.

Two additions specific to this overlay:

- `npm run knip` (TypeScript stacks) must be clean. The instrumentation files are framework/flag-loaded and are the likely failures; the fix is the `entry` declaration shown per stack, never deleting the file.
- Confirm the SDK is genuinely inert without a DSN by running the app's entry point once (`npm run build`, `… --help`, `npm test`) and checking that nothing warns about a failed transport. A "No DSN provided" debug line is expected and correct.
