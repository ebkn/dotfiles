# Cloudflare Workers (TypeScript)

Read `references/typescript.md` first — package.json, `.npmrc`, biome, and knip come from there. This file replaces that path's tsconfig, vitest config, and test/typecheck scripts with the Workers-specific ones, because a Worker runs in `workerd`, not Node.

Resolve every version at scaffold time — see the rule in SKILL.md.

## Dev dependencies

From the base file install **only biome and knip** (`npm install -D @biomejs/biome knip`) — typescript and vitest are installed here, version-constrained by the Workers test pool:

```bash
npm install -D wrangler typescript @cloudflare/vitest-pool-workers
```

Then resolve the vitest major the installed pool actually supports before installing it — the pool declares a hard `peerDependencies.vitest` range, and this ecosystem is mid-transition (older pool lines peer on vitest 3.x with a `defineWorkersConfig` API; the 4.1+-peer line replaces it with a `cloudflareTest` plugin), so a blind `npm install -D vitest` can land one major ahead of the pool:

```bash
npm view @cloudflare/vitest-pool-workers@{installed version} peerDependencies.vitest
npm install -D vitest@{a version inside that range}
```

Record in the CLAUDE.md Constraints section which pool/vitest pairing was scaffolded and that the two must be bumped together.

## wrangler.jsonc

`wrangler.jsonc` is the recommended config format for new projects (some newer Wrangler features are JSON-config-only). Minimal, with observability on — the same default Cloudflare applies to newly created Workers:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "{project-name}",
  "main": "src/index.ts",
  "compatibility_date": "{today, yyyy-mm-dd}",
  "observability": { "enabled": true }
}
```

- **`compatibility_date` is a runtime pin, not decoration** — it freezes which workerd behaviors the Worker sees, the same role `.nvmrc` plays on the Node path. Set it to the scaffold date and treat later bumps as deliberate upgrades.
- **`nodejs_compat` is deliberately absent.** Add `"compatibility_flags": ["nodejs_compat"]` only when the project actually imports Node built-ins or an npm package that does; enabling it speculatively grows the runtime surface and papers over accidental Node-isms in Worker code.

## Boilerplate from the C3 template

Cloudflare's own scaffolder (C3) ships its TypeScript "Hello World" template inside the `cloudflare/workers-sdk` repo at `packages/create-cloudflare/templates/hello-world/ts/`. Fetch the config files from there **at the release tag matching the installed wrangler** (`dependencies` in package.json is exact-pinned by `save-exact`), never from `main` — same mutable-reference rule as the Next.js template fetch, and same tool: `curl -sS -o {file} {url}`, not WebFetch:

```
https://raw.githubusercontent.com/cloudflare/workers-sdk/wrangler@{installed-wrangler-version}/packages/create-cloudflare/templates/hello-world/ts/{file}
```

Fetch these — they are the pieces whose exact shape must match the installed toolchain, and hand-writing them is how a scaffold drifts from what Cloudflare tests:

- `tsconfig.json` — Workers-shaped (Bundler module resolution, `worker-configuration.d.ts` in `include`, `test/` excluded). **Do not create the plain-TypeScript tsconfig from the base file** — its `NodeNext` resolution and Node `lib` are wrong for workerd. This is the same replacement rule as Next.js's generated tsconfig.
- `test/tsconfig.json` and `test/env.d.ts` — the separate test-side TS project that gives `cloudflare:test` its types.
- `vitest.config.mts` — the pool wiring (`defineWorkersConfig` + `wrangler.configPath`, or the plugin form if the fetched tag has moved to it). Do not also keep the base file's `vitest.config.ts`; one vitest config only.

Read what you fetch before writing it in, and don't copy the template's `package.json` version pins — the template's devDependency ranges are known to lag npm; the installs above already resolved current versions under the `.npmrc` gates. Skip the template's `.prettierrc`/`.editorconfig` (Biome is this scaffold's formatter) and its `.gitignore` (Step 6's is broader).

## Generated types — `wrangler types`

Current guidance is to generate runtime types with `wrangler types` rather than depending on `@cloudflare/workers-types`: it writes `worker-configuration.d.ts` matched to the exact `compatibility_date`, flags, and bindings (including the `Env` interface). That file is **generated output** — gitignore it (Step 6 additions below) and make the typecheck script regenerate it, exactly the `next typegen && tsc` pattern from the Next.js path and for the same reason: a fresh CI checkout doesn't have it, and `tsconfig.json` points at it.

## package.json scripts

Replace/add on the base scripts, and **drop `--passWithNoTests`** (a real test ships below):

```json
"dev": "wrangler dev",
"deploy": "wrangler deploy",
"typecheck": "wrangler types && tsc --noEmit",
"test": "vitest run",
"cf-typegen": "wrangler types"
```

`wrangler dev` serves on `http://localhost:8787` by default — that is the `{dev-port}` for the service-access permissions in SKILL.md Step 5.

## Scaffolded source — health endpoint and its test

Workers projects are `api`-type by default, so ship the health endpoint here (the fetch handler *is* the server) plus the one real test:

`src/index.ts`:

```ts
export default {
  async fetch(request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/healthz") {
      return Response.json({ status: "ok" });
    }
    return new Response("{project-name}");
  },
} satisfies ExportedHandler<Env>;
```

`Env` comes from the generated `worker-configuration.d.ts` — do not hand-declare it.

`test/index.spec.ts` (unit style, from `cloudflare:test`; adjust imports to whatever the fetched template's test file uses at your tag — the pool's test API moved between generations, and the fetched template is the consistent known-good set):

```ts
import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { describe, expect, it } from "vitest";

import worker from "../src/index.ts";

describe("GET /healthz", () => {
  it("responds 200 with status ok", async () => {
    const request = new Request("https://example.com/healthz");
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ status: "ok" });
  });
});
```

This test suite runs **inside workerd** via the vitest pool, so `npm test` doubles as the runtime smoke test — there is no need to boot `wrangler dev` during verification.

Biome `noConsole`: use the `api` relaxation from `references/typescript.md` (allow `error`/`warn`/`info`/`debug`) — on Workers, `console.*` is precisely what the `observability` block above collects.

## Secrets

- **Local dev:** `.dev.vars` in the project root (Workers' native convention; wrangler also reads `.env`, but pick one — this scaffold picks `.dev.vars` so Workers docs apply verbatim). Per-environment files are `.dev.vars.<env>`.
- **Production:** `npx wrangler secret put <KEY>` — secrets never live in `wrangler.jsonc` or the repo.

`.dev.vars` is the `.env` of this path, so it gets the same two-layer treatment: the gitignore entry below, **and** extending both `deny` lists in `.claude/settings.json` (SKILL.md Step 5) in lockstep — `Read(.dev.vars)`, `Read(.dev.vars.*)`, `Edit(.dev.vars)`, `Edit(.dev.vars.*)`. Adding only the ignore leaves an agent free to read and exfiltrate it; adding only `Read` leaves the `Write`-overwrite gap Step 5 documents.

## .gitignore additions

Beyond the shared block in SKILL.md Step 6 and the base TypeScript entries:

```
.dev.vars*
.wrangler/
worker-configuration.d.ts
```

`.wrangler/` is wrangler's local state/cache dir; `worker-configuration.d.ts` is regenerated by `typecheck` (see above) — tracking it would re-diff on every wrangler bump, the same trap as `next-env.d.ts`.

## .claude/settings.json entries

Use the standard TypeScript entries from `references/typescript.md`, plus:

- `Bash(npx wrangler types)` — the typegen half of `typecheck`, safe and read-only in effect.

Deliberately **not** allow-listed:

- `npm run dev` / `npx wrangler dev` — long-running local server.
- `npm run deploy` / `npx wrangler deploy` — publishes to production; deploying must stay a deliberate, prompted action.

## CI & deploy

The standard TypeScript CI from `references/supply-chain.md` applies as-is (lint → typecheck → knip → test; no build step — `wrangler deploy` bundles at deploy time). The `typecheck` script's `wrangler types` runs fine in CI with no Cloudflare credentials.

**Deploy automation is opt-in — ask before scaffolding it.** Two supported routes; do not wire either without the user confirming they have (or will create) the credentials:

1. **GitHub Actions** — a separate `deploy.yml` triggered on `push: branches: [main]` using `cloudflare/wrangler-action` with `apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}` and `accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}`. SHA-pin the action under the same 7-day quarantine as every other action (`references/supply-chain.md`). The token should be a custom token with only the **Edit Cloudflare Workers** permission, scoped to the one account — there is no OIDC option for this action yet, so the static token is the accepted trade; note that in CLAUDE.md.
2. **Workers Builds** — Cloudflare's hosted CI, connected in the dashboard, no repo-side secret at all. Zero YAML to maintain and preview deployments for free; the constraint is that the dashboard Worker name must match `name` in `wrangler.jsonc`.

If the user has no preference, recommend Workers Builds (no long-lived token in GitHub) and record the choice in CLAUDE.md.

## Verification

First normalize formatting once (`npm run lint:fix`), then:

```bash
npm run typecheck   # runs wrangler types first — must recreate worker-configuration.d.ts
npm run lint
npm run knip        # src/index.ts should be detected; if flagged, add "entry": ["src/index.ts"] to knip.json rather than weakening the gate
npm test            # runs inside workerd via the vitest pool — this is the runtime smoke test
```

Then verify the typegen pairing holds under CI conditions, the same discipline as the Next.js `next typegen` check:

```bash
rm -rf worker-configuration.d.ts tsconfig.tsbuildinfo
npm run typecheck   # must pass, and must recreate worker-configuration.d.ts
```

If `npm test` fails on the pool/vitest pairing (peer-range mismatch, or a config API that doesn't match the installed pool generation), fix the versions or re-fetch the template files at the correct tag — do not hand-patch the vitest config into a hybrid of the two generations.
