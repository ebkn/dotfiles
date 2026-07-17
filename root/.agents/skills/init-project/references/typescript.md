# TypeScript / Node.js

Read this for both plain TypeScript and Next.js projects. Next.js additionally needs `references/nextjs.md`, which assumes the files here already exist.

Resolve every version at scaffold time — see the rule in SKILL.md. `{...}` below are placeholders.

## package.json

If `package.json` does not exist, create one. Run `npm -v` and `node -v` to fill in the actual versions:

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
- `"type": "module"` — required so `vitest.config.ts` (ESM imports) loads under `verbatimModuleSyntax` in the strict tsconfig below.
- `--passWithNoTests` — keeps CI green before any tests exist; remove it once a test suite is in place if you prefer strict failure.

Adjust `dev`, `build`, and `start` for the framework:
- **Next.js**: `next dev --turbopack`, `next build`, `next start`
- **Plain TypeScript**: remove `dev`, `build`, `start` or set appropriate commands

## .npmrc

**Write this file before the first `npm install`, not after.** npm reads `.npmrc` at invocation time, so every setting here only governs installs that come after it exists. Scaffolding dependencies first and the `.npmrc` second silently forfeits all three controls for the one install that introduces the entire dependency tree — the install that matters most. That ordering is also why this section precedes the dependency list below.

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

Recent npm versions add an `allowScripts` field in package.json plus `npm approve-scripts`, which records per-package (version-pinned) approval to run install scripts. It looks like a more granular replacement for `ignore-scripts`, but do not treat it as one yet: npm's own docs state the field is **advisory in the current release** — unreviewed scripts still run and installs merely print a list — and the `strict-allow-scripts` config that does turn it into a hard failure is undocumented. An older npm silently ignores unknown config keys, so switching to it can also mean losing the protection outright with no error. Keep `ignore-scripts=true`, which also short-circuits the whole mechanism (with it set, nothing runs, so nothing needs approving and `npm rebuild` stays the escape hatch). Revisit once npm blocks unreviewed scripts by default.

## Dev dependencies

- **Plain TypeScript** — install biome, vitest, typescript, and knip together so `lint`, `test`, `typecheck`, and `knip` all work immediately:

  ```bash
  npm install -D @biomejs/biome vitest typescript knip
  ```

- **Next.js** — install only biome and knip here; vitest and typescript come with the runtime deps in `references/nextjs.md`, which pins TypeScript for a reason documented there:

  ```bash
  npm install -D @biomejs/biome knip
  ```

## biome.json

Run `npx biome --version` to read the installed CLI version and pin `$schema` to it — a stale schema version against a newer CLI produces a deserialize warning on every lint run.

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

For **web / Next.js (JSX)** projects, keep Biome's `recommended` rules on: its accessibility (`a11y`) rules run at error level by default and are the accessibility gate CI enforces. Do not disable them — a downgraded a11y rule silently removes that gate.

## vitest.config.ts

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
  },
});
```

## tsconfig.json — plain TypeScript only

Next.js generates its own tsconfig; do not create this for Next.js projects. This exists so `npm run typecheck` runs against a real config instead of `tsc` defaults.

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

## knip.json — unused-code detection

Dead files, unused exports, and unused dependencies accumulate silently — they inflate bundles, widen the dependency attack surface, and mislead readers. Wire the detector now so the project never grows a backlog of them.

Run `npx knip --version` and use that major in the `$schema` URL, the same way Biome's schema is pinned above:

```json
{
  "$schema": "https://unpkg.com/knip@{installed-knip-major}/schema.json"
}
```

Knip auto-detects entry points and config through built-in plugins (Next.js, Vitest, Biome, etc.), so the `$schema`-only config works out of the box — add `entry`/`project`/`ignore` overrides only when a real false positive appears. Knip requires a recent Node (`npm view knip engines.node`); the `.nvmrc` below satisfies it as long as you pinned the current LTS.

For a **library** whose whole point is its public exports, set `package.json` `main`/`exports` to the public entry (or declare `entry` in `knip.json`) so knip treats the public API as used — otherwise it reports the library's entire surface as dead code.

## .nvmrc — runtime pin

Pin the runtime so local, CI, and deploy agree; CI reads this file. Match `engines.node` from package.json:

```
{exact current node version}
```

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(npm test *)`, `Bash(npm run test*)`, `Bash(npx biome *)`, `Bash(npm run build*)`, `Bash(npm run lint*)`, `Bash(npm run knip*)`, `Bash(npx knip*)`, `Bash(npx vitest *)`
- `Bash(npx tsc *)`

## Verification

Run the whole toolchain against the empty scaffold — all four must pass before moving on. If any fails, fix the config rather than proceeding:

```bash
npm run typecheck
npm run lint
npm run knip      # expect no issues: every scaffolded file is an entry point or reached from one
npm run test:run
```

If knip flags a legitimately-unused scaffold export this early, prefer adjusting `knip.json` over deleting the file.
