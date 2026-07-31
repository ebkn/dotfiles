# Next.js (App Router)

Read `references/typescript.md` first — package.json, `.npmrc`, biome, vitest and knip come from there. This file adds only what is Next.js-specific.

Resolve every version at scaffold time — see the rule in SKILL.md.

## Runtime dependencies

Install these **before** fetching the boilerplate below — the template must be fetched at the tag matching the `next` version you actually install, and that is not always `npm view next version`. The `.npmrc` from `references/typescript.md` sets `min-release-age=7`, so `npm install next` resolves to the newest release older than seven days; whenever `latest` shipped within the last week, the installed version lags it. Install first, then read the exact version npm pinned and fetch the template at *that* tag.

```bash
npm install next react react-dom
npm install -D typescript@5 @types/node @types/react @types/react-dom vitest
```

The `typescript@5` pin is deliberate — do not "fix" it to bare `typescript`. Next.js declares no `typescript` peer dependency, so npm stays silent on a mismatch and installs whatever major is current; a TypeScript major that Next.js has not adopted yet fails only at build, as an opaque error rather than a version complaint (observed with Next.js 16.2.x + TypeScript 7.0.2, the current major at the time: `next build` dies with `The "id" argument must be of type string. Received undefined`, while the same tree builds on 5.x). The `npm run build` at the end of this file is the check. After it passes, you may *try* a newer major (`npm install -D typescript@{major}`) and keep it only if `build` stays green — otherwise revert to `@5`. Either way, record the resulting constraint in the CLAUDE.md Constraints section, so the next person does not helpfully bump it back.

## Boilerplate

Create the official App Router boilerplate from the `vercel/next.js` template at `packages/create-next-app/templates/app/ts/`.

Fetch each file from raw.githubusercontent.com **at the release tag matching the `next` version you just installed**, never from `main`:

```
https://raw.githubusercontent.com/vercel/next.js/v{next-version}/packages/create-next-app/templates/app/ts/{file}
```

Fetch with `curl -sS -o {file} {url}` (the narrow form in `allowed-tools`), **not** WebFetch. WebFetch answers a prompt *about* the page with a small model rather than returning bytes — observed live: 3 of the 5 SVGs came back as prose descriptions ("This is an SVG image file containing a logo…"), and text files came back wrapped in invented code fences. For assets a paraphrase is undetectable until something renders broken; `curl -o` writes the bytes exactly. If you must fall back to WebFetch for a text file, diff-read what was written and strip any added fences before moving on.

Resolve `{next-version}` from the **installed** version — read `dependencies.next` in `package.json`, which `save-exact=true` (set in `references/typescript.md`'s `.npmrc`) has already pinned to an exact value. Do **not** use `npm view next version`: that returns the published `latest`, which the `min-release-age=7` gate holds the install back from whenever `latest` is under seven days old, so fetching the template at the `latest` tag would reintroduce the exact drift-from-the-pinned-release this rule exists to prevent. A `main`/`HEAD` URL is worse still — a mutable reference, the same supply-chain hole this skill closes for GitHub Actions. Read what you fetch before writing it; this step copies third-party code into the project.

Create:

- `next.config.ts` — **do not fetch**; the Security headers section below supplies the whole file
- `tsconfig.json` — TypeScript config with Next.js plugin and `@/*` path alias. After copying it, append `"tmp"` to its `exclude` array: the shared `.gitignore` (SKILL.md Step 6) designates `tmp/` as the scratch dir, but the template's `**/*.ts` include would still pull any stray `.ts` left there into the typecheck program (observed: TS2307 on scratch files).
- `app/layout.tsx` — root layout with Geist fonts
- `app/page.tsx` — default home page
- `app/globals.css` — global styles
- `app/page.module.css` — page-level CSS module
- `public/` — **only the SVG assets `app/page.tsx` actually references** (at recent template versions: `next.svg`, `vercel.svg`). The template dir ships five, but the unreferenced ones are dead vendor assets knip cannot flag (it doesn't track image references) — read the fetched `page.tsx` and fetch exactly what it uses.

The vendor SVGs carry no `<title>`, and Biome 2.5+ parses `.svg` — so `a11y/noSvgWithoutTitle`, part of the `recommended` a11y gate `references/typescript.md` says never to disable, fails on all five. Resolve the conflict with a named, scoped exception in the generated `biome.json`, not a rule downgrade: these are third-party brand assets rendered through `next/image` with an `alt` at the call site, so the accessible name lives there. Scope it to `public/` only — inline SVG in `app/` must keep the rule:

```json
"overrides": [
  {
    "includes": ["public/**/*.svg"],
    "linter": { "rules": { "a11y": { "noSvgWithoutTitle": "off" } } }
  }
]
```

Record the override's rationale in the CLAUDE.md Constraints section so nobody widens it to `app/` or deletes it and re-reds the gate.

## package.json scripts

The base template in `references/typescript.md` ships lint/typecheck/knip/test only. Add the three Next.js scripts to it, **and overwrite `typecheck`**:

```json
"dev": "next dev --turbopack",
"build": "next build",
"start": "next start",
"typecheck": "next typegen && tsc --noEmit"
```

`build` is not optional here — it is what the verification at the bottom of this file runs, and the CI template in `references/supply-chain.md` runs `npm run build` for Next.js.

### Why `typecheck` is not the base `tsc --noEmit`

Two of the declarations the tsconfig `include` array points at are **generated**, not committed, and bare `tsc` generates neither:

- `next-env.d.ts` — `.gitignore`d (SKILL.md Step 6), so it is absent in every fresh checkout. It is what pulls in `next/image-types/global`, the declarations for static asset imports (`*.png`, `*.svg`, …).
- `.next/types/**/*.ts` — where the route-aware globals `PageProps`, `LayoutProps`, and `RouteContext` are emitted, plus the link table behind `typedRoutes`.

CI runs `typecheck` **before** `build` (see `references/supply-chain.md`), so on a fresh checkout neither exists when `tsc` runs. The scaffolded tree happens to survive this — `layout.tsx`'s `import type { Metadata } from "next"` reaches `next/index.d.ts`, whose `/// <reference types="./types/global" />` forwards the `*.css` / `*.module.css` declarations (verified on a real scaffold). That is luck, not design, and it runs out at the first `import logo from "./logo.png"` or first `PageProps` in a dynamic route: locally those typecheck (dev/build already wrote the files), in CI they fail with `TS2307`/`TS2304`. A green local tree and a red CI on code the author cannot reproduce is precisely the divergence this skill exists to prevent — and it lands on whoever writes that line, not on whoever scaffolded.

`next typegen` (Next.js **≥ 15.5.0**) generates both without a full build, and `next typegen && tsc --noEmit` is [the form the Next.js CLI docs recommend for CI type-checking](https://nextjs.org/docs/app/api-reference/cli/next#next-typegen-options): *"To ensure `next-env.d.ts` is present before type-checking run `next typegen`. The commands `next dev` and `next build` also generate the `next-env.d.ts` file, but it is often undesirable to run these just to type-check, for example in CI/CD environments."*

The cost, so it is a decision and not an accident: `typecheck` stops being a pure `tsc` call. `next typegen` loads `next.config.ts` **using the production build phase**, so the gate now depends on that config loading — a config that later reads a required env var will fail `typecheck`, not just `build`. The scaffolded config is static, so this is free today; if the config grows env-dependent, supply those vars to the CI typecheck step rather than reverting the script.

Also **drop `--passWithNoTests` from `test`**, so the script becomes `"test": "vitest run"`. The base in `references/typescript.md` carries that flag because a plain scaffold has nothing to test yet; this path is different — it scaffolds a real, testable health endpoint (below) plus its test, so the "no tests" state should never occur. Keeping the flag would let a future breakage that makes Vitest collect *zero* tests — a bad glob, a moved config, a renamed file — pass CI silently. Removing it turns that silent pass into a red build. This is the Next.js-only counterpart of the tension called out for the Python path, which stays tolerant because its server (and so its first real test) is deferred.

## Error & loading boundaries

`create-next-app` does not add these; without them a runtime error is a white screen. Create minimal, correct-by-default stubs:

`app/error.tsx`:

```tsx
"use client";

// Not named `Error`: Biome's recommended `noShadowRestrictedNames` (error level)
// rejects shadowing the global, and Next.js keys this boundary off the filename,
// so the export name is free to differ from the docs' example.
export default function ErrorBoundary({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
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

Keep the comment in the generated file and record the rename in the CLAUDE.md Constraints section — a future reader who "fixes" the name back to `Error` to match Next.js's docs reintroduces a lint failure. (`GlobalError` below shadows nothing, so it needs no rename.)

`app/global-error.tsx` (catches errors in the root layout; must render its own `<html>`/`<body>`):

```tsx
"use client";

export default function GlobalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
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

`app/not-found.tsx`:

```tsx
import Link from "next/link";

export default function NotFound() {
  return (
    <div>
      <h2>Not found</h2>
      <Link href="/">Return home</Link>
    </div>
  );
}
```

`app/loading.tsx`:

```tsx
export default function Loading() {
  return <p>Loading…</p>;
}
```

## Security headers

Add a static baseline header set to `next.config.ts`. **Do not add a Content-Security-Policy here** — a permissive/`unsafe-inline` CSP is a false safeguard; a real nonce-based CSP belongs in middleware once the app's script/style sources are known (left as a TODO in the CLAUDE.md Launch Readiness section). HSTS only takes effect over HTTPS, so it is inert in local dev.

```ts
import type { NextConfig } from "next";

const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "SAMEORIGIN" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
```

`Permissions-Policy: camera=(), microphone=(), geolocation=()` denies those three powerful features to **every** origin — an empty allowlist `()` is deny-all — so neither the page nor an injected third-party script can silently prompt for the camera, microphone, or location. A feature the app actually needs is opted back in deliberately (e.g. `geolocation=(self)`); starting from deny is the correct-by-default direction. `poweredByHeader: false` drops Next.js's default `X-Powered-By: Next.js` response header, which only advertises the framework to someone fingerprinting the stack — no behavior depends on it. Both are free hardening with no runtime cost.

HSTS `preload` is intentionally left **off** by default — the irreversible commitment should be opt-in, not opt-out. `includeSubDomains` is kept because it is recoverable: it enforces HTTPS per client on first visit and decays as `max-age` runs down, so lowering `max-age` walks it back. The preload list does not: adding the `preload` directive and submitting the apex at [hstspreload.org](https://hstspreload.org) hardcodes the domain and every subdomain into browsers' built-in HTTPS-only list, and removal takes months and only propagates as browsers ship — some clients may never update. Opt in deliberately, once you are certain every current and future subdomain will serve HTTPS forever, by appending `; preload` to the value above and submitting there. (This mirrors the CSP stance above: don't ship the hard-to-reverse commitment by default — leave it a deliberate, documented step.)

### `internal-web` — also keep it out of search engines

This belongs here, not in the SEO section below, because that section is skipped for `internal-web` — an instruction to hide an internal tool cannot live in a block its own audience is told to skip. An internal tool should never be indexed, and a `robots.ts` (the SEO scaffold's approach) is not enough on its own: `robots.txt` asks crawlers not to *crawl*, but a URL linked from anywhere can still be indexed. The real gate is an `X-Robots-Tag: noindex` **response header**, which the header block above already delivers on every route — add it to `securityHeaders`:

```ts
{ key: "X-Robots-Tag", value: "noindex" },
```

This is the deliberate opposite of the `public-web` SEO scaffold, which ships a `robots.ts` that *invites* crawling. Do one or the other per the project type, never both.

## SEO scaffold — `public-web` only

Skip for `internal-web`, `api`, and `library`/`cli` — an `internal-web` tool instead gets the `noindex` header described in the Security headers section above.

Replace the default `metadata` export in `app/layout.tsx` (the template already imports `Metadata`) so `metadataBase` and base metadata resolve to the real origin, not the preview/localhost domain:

```ts
export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
  title: { default: "{project-name}", template: "%s | {project-name}" },
  description: "{one-line description}",
};
```

`app/robots.ts`:

```ts
import type { MetadataRoute } from "next";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: "/api/" },
    sitemap: `${siteUrl}/sitemap.xml`,
  };
}
```

`app/sitemap.ts`:

```ts
import type { MetadataRoute } from "next";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default function sitemap(): MetadataRoute.Sitemap {
  return [{ url: siteUrl, lastModified: new Date() }];
}
```

The scaffolded code reads `NEXT_PUBLIC_SITE_URL`. Create `.env.example` (or append to it) documenting it — without a real value, canonical/OG/sitemap URLs fall back to `localhost`:

```
NEXT_PUBLIC_SITE_URL=https://example.com
```

`.env.example` is the only env file the `.gitignore` keeps tracked; real values belong in `.env.local`, which is ignored. `.env.local` is the filename Next.js conventionally uses for secrets and is the one env file it skips when `NODE_ENV=test`, so local secrets never bleed into test runs. (The wholesale `.env*` ignore means a value placed in `.env` would be safe too — but `.env.local` is what to recommend.)

## Health endpoint

Applies to any served web app or API. Skip for `library`/`cli`. The deploy orchestrator uses it for readiness checks; a trivial 200 is correct-by-default and cheap now.

`app/api/health/route.ts`:

```ts
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json({ status: "ok" });
}
```

### Its test — the one test the scaffold ships

This is what lets `test` drop `--passWithNoTests` (see the scripts section above). It also honors the project's TDD philosophy with a *real* behavior test rather than a placeholder: it asserts the endpoint's actual contract (`200` + `{ "status": "ok" }`), so it doesn't rot as the app grows, and it fails loudly the day someone breaks the route.

`app/api/health/route.test.ts`:

```ts
import { describe, expect, it } from "vitest";

import { GET } from "./route";

describe("GET /api/health", () => {
  it("responds 200 with status ok", async () => {
    const res = GET();
    expect(res.status).toBe(200);
    await expect(res.json()).resolves.toEqual({ status: "ok" });
  });
});
```

`GET` returns a standard `Response`, so the test imports and calls it directly — no Vitest environment, jsdom, or Next.js runtime needed (verified: it passes under plain-Node Vitest). Note the explicit `vitest` imports rather than globals, matching the `vitest.config.ts` in `references/typescript.md`.

### Component tests are deliberately not set up — record the boundary

The health test runs in plain Node precisely *because* `GET` returns a standard `Response`. A React **component** test cannot: it needs a browser-like DOM plus the React test tooling, none of which this scaffold installs. That omission is intentional — it keeps the dependency surface minimal and avoids committing the team to a testing stack they may not want — but it is a surprise waiting for whoever writes the first UI test. Close that surprise with a note rather than by installing the tooling speculatively.

Record it in the generated CLAUDE.md Development → Test section, e.g.:

> Component/UI tests are not scaffolded. The first one needs `jsdom` (the DOM environment), `@testing-library/react` + `@testing-library/jest-dom` (render + DOM assertions), and `@vitejs/plugin-react` (so Vitest transforms JSX/TSX), plus `test.environment: "jsdom"` in `vitest.config.ts`. The health-endpoint test runs in plain Node and needs none of these.

This is the same "record a constraint a future reader would otherwise undo" instruction as the TypeScript-version note above — here the reader would otherwise assume, from one green test, that the test harness already covers components.

## Verification

First normalize formatting once:

```bash
npm run lint:fix
```

The lint gate is `biome check .`, which enforces *formatting* as well as rules, and hand-copied snippets — this file's included — are not guaranteed to match Biome's default 80-column formatter. One `lint:fix` pass makes the subsequent gate judge substance, not line width; a formatting diff at this point is expected and fine, a *rule* error is not.

Then:

```bash
npm run build
```

This both verifies the setup and generates `next-env.d.ts`. Then run the rest of the toolchain from `references/typescript.md` — its verification block runs here, at the end of this file, not at the end of that one: before the runtime deps above are installed, `tsc`/`vitest` do not exist yet, so the earlier position cannot pass.

Finally, verify the `typecheck` override actually holds under CI conditions — a green run right after `build` proves nothing, because `build` just wrote the generated declarations:

```bash
rm -rf next-env.d.ts .next tsconfig.tsbuildinfo
npm run typecheck   # must pass, and must recreate next-env.d.ts
```

`tsconfig.tsbuildinfo` goes too: `incremental` is on (from the base tsconfig notes in `references/typescript.md`), and a surviving cache can let `tsc` skip exactly the work a fresh CI checkout would do. All three paths are `.gitignore`d, so this deletes nothing tracked. If `rm` is permission-gated in the environment, move the three aside to a gitignored location instead, run the check, then delete the displaced copies once it passes — do not leave them in the tree, and mention any leftover in the Step 10 summary if deletion is impossible. This is the one check that distinguishes the fixed script from the broken one: with the base `tsc --noEmit`, the tree is left without `next-env.d.ts` afterwards — exactly the state a fresh CI checkout starts in.
