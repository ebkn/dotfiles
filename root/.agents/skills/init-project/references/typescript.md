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
- There is deliberately no `dev`/`build`/`start`. A plain TypeScript project has nothing to serve, and the tsconfig below sets `noEmit: true`, so `typecheck` is the only `tsc` invocation and a `build` script would have nothing to do. **Next.js adds its own — see `references/nextjs.md`.** If this project ships compiled JS (a library published to npm), add a `build` script and a second tsconfig that drops `noEmit`; the CI template in `references/supply-chain.md` notes where to enable the build step.

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

- **Next.js** — install only biome and knip here; vitest and typescript come with the runtime deps in `references/nextjs.md`, which constrains the TypeScript version for a reason documented there:

  ```bash
  npm install -D @biomejs/biome knip
  ```

## biome.json

Run `npx biome --version` to read the installed CLI version and pin `$schema` to it — a stale schema version against a newer CLI produces a deserialize warning on every lint run.

```json
{
  "$schema": "https://biomejs.dev/schemas/{installed-biome-version}/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "linter": {
    "enabled": true,
    "rules": {
      "suspicious": {
        "noExplicitAny": "error",
        "noEvolvingTypes": "error",
        "noConsole": "error",
        "noArrayIndexKey": "error",
        "noVar": "error",
        "noUnnecessaryConditions": "error"
      },
      "style": {
        "noNamespace": "error",
        "useExportType": "error",
        "useNumberNamespace": "error",
        "noUselessElse": "error"
      },
      "correctness": {
        "noUnusedImports": "error",
        "noUnusedVariables": "error",
        "noUndeclaredVariables": "error"
      },
      "performance": {
        "noDelete": "error"
      }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  }
}
```

The `vcs` block makes Biome honor `.gitignore`. **Do not omit it.** Biome 2.x does *not* read `.gitignore` by default, so without this it lints and formats generated build output the moment it exists — `.next/` and `out/` (Next.js), `dist/` (a library build). The failure is invisible at scaffold time and mistimed by CI: the verification block below runs before any build, and CI's lint step happens to run before `build`, so both stay green. But locally, the first `npm run dev` populates `.next/`, and from then on `npm run lint` exits 1 on generated files for both humans and agents. `useIgnoreFile: true` makes `.gitignore` the single source of truth for what tooling ignores, matching how the rest of this scaffold is organized. (This is why Step 1 runs `git init` first — Biome resolves the VCS root from `.git/`; a missing `.gitignore` at verification time is harmless.)

For **web / Next.js (JSX)** projects, keep Biome's `recommended` rules on: its accessibility (`a11y`) rules run at error level by default and are the accessibility gate CI enforces. Do not disable them — a downgraded a11y rule silently removes that gate.

### The explicit `rules` block

The `rules` above are an opinionated layer *on top of* `recommended`, not a replacement for it. `recommended` stays enabled (nothing sets `"recommended": false`), so its defaults — including the `a11y` error-level gate just described — remain in force; these entries only tighten things it leaves loose. Every rule listed was checked against Biome 2.x's `recommended` set and is there for one of two reasons, so **nothing here merely restates a default**:

- **Promoted `warn` → `error`** (`recommended` enables them, but only as warnings, and `biome check` exits 0 on warnings — so they don't fail CI): `noExplicitAny`, `useExportType`, `noUnusedImports`, `noUnusedVariables`. Raising them to `error` makes each a hard gate.
- **Not in `recommended` at all** (off by default): the rest — e.g. `noConsole`, `noVar`, `noNamespace`, `noDelete`, `noUselessElse`, `useNumberNamespace`, `noEvolvingTypes`, `noArrayIndexKey`, `noUnnecessaryConditions`.

Rules already at `error` in `recommended` (`noCommentText`, `a11y/noAccessKey`, `a11y/useButtonType`, `a11y/useAltText`) are deliberately **omitted** — adding them would be redundant. Likewise `organizeImports`: it is an assist action that is **on by default** in Biome 2.x, so it needs no `assist` block here.

Two caveats worth knowing:

- **`noUndeclaredVariables` overlaps `tsc`.** The `typecheck` gate (`tsc --noEmit`) already flags undeclared identifiers, with full type information Biome doesn't have. Biome's version can additionally require maintaining a `javascript.globals` allow-list for globals it can't see. It's kept here as a fast editor-time signal, but if it produces false positives on globals, drop it rather than growing an allow-list — `tsc` remains the real gate.
- **`noUnnecessaryConditions` is type-aware.** It relies on Biome's type inference, which is newer and less complete than `tsc`'s; treat its findings as advisory-quality even though it's set to `error`.

Because this set is calibrated to Biome 2.x's *current* defaults, re-confirm at scaffold time if a much newer Biome is installed: `npx biome explain <rule>` shows a rule's group and default severity, and a rule newly promoted into `recommended` at `error` can be dropped from this block. A stale-but-still-valid entry only costs redundancy, not correctness.

## vitest.config.ts

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {},
});
```

**Do not set `globals: true`.** It is a trap that surfaces the moment the user writes their *first* test — too late for the verification block below to catch, since no test exists at scaffold time. With globals on, a test using bare `describe`/`it`/`expect` passes `npm run test:run` (Vitest injects the globals at runtime) but fails `npm run typecheck` with `TS2593: Cannot find name 'describe'`, because `tsc` sees no declaration for them. The result is a split-brain baseline: tests green, the CI typecheck gate red, on the user's first test. The documented fix for globals is adding `"types": ["vitest/globals"]` to `tsconfig.json` — but the Next.js path's tsconfig is generated from the official template, and editing it invites drift. Leaving globals off (Vitest's own default) means tests explicitly `import { describe, it, expect } from "vitest"`, which typechecks with no tsconfig change on either path. `test: {}` is kept as an anchor for future config.

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
