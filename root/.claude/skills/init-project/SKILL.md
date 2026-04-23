---
name: init-project
description: Scaffold a new project in the current directory — git init, README.md, CLAUDE.md, AGENTS.md, Claude settings.json, and linter config for the specified language (TypeScript, Go, Python). Use this skill when the user wants to initialize or bootstrap a new project from scratch, set up a fresh repo, or scaffold project boilerplate.
allowed-tools: Bash(git init *), Bash(git init), Bash(git status *), Bash(git rev-parse *), Bash(git add *), Bash(git commit -m *), Bash(npm init *), Bash(npm install *), Bash(ls*), Bash(tree*), Bash(mkdir *), Bash(ln -s *), Read, Write, Glob
---

## Instructions

Initialize a new project in the current directory. Ask the user for:

1. **Project name** — used in README.md heading and CLAUDE.md
2. **One-line description** — what this project does
3. **Primary language** — one of: `typescript`, `go`, `python` (or a framework like `next`, `fastapi`, `gin`, etc.)

Then scaffold the project following the steps below. Skip any step where the file already exists — never overwrite.

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
- `Bash(npm test *)`, `Bash(npm run test*)`, `Bash(npx biome *)`, `Bash(npm run build*)`, `Bash(npm run lint*)`
- `Bash(npx tsc *)` if TypeScript

**Go** — add:
- `Bash(go test *)`, `Bash(go build *)`, `Bash(go vet *)`, `Bash(golangci-lint *)`

**Python** — add:
- `Bash(pytest *)`, `Bash(ruff *)`, `Bash(ruff check *)`, `Bash(ruff format *)`
- `Bash(pip install *)` if no pyproject.toml build system is obvious

### Step 4.5: package.json and dependencies (TypeScript / Node.js only)

If `package.json` does not exist, create one:

```json
{
  "name": "{project-name}",
  "version": "0.0.0",
  "private": true,
  "packageManager": "npm@{current npm version}",
  "engines": {
    "node": ">={current major node version}.0.0"
  },
  "scripts": {
    "dev": "next dev --turbopack",
    "build": "next build",
    "start": "next start",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "format": "biome format --write .",
    "typecheck": "tsc --noEmit",
    "test": "vitest",
    "test:run": "vitest run"
  }
}
```

Run `npm -v` and `node -v` to fill in the actual versions.

Adjust `dev`, `build`, and `start` scripts based on the framework:
- **Next.js**: `next dev --turbopack`, `next build`, `next start`
- **Plain TypeScript**: remove `dev`, `build`, `start` or set appropriate commands

Also create `.npmrc` with:

```
min-release-age=7d
```

This prevents npm from installing package versions published less than 7 days ago.

Then install biome:

```bash
npm install -D @biomejs/biome
```

**Go / Python** — skip this step.

### Step 5: Linter config

Set up a minimal linter config for the chosen language.

**TypeScript** — `biome.json`:

```json
{
  "$schema": "https://biomejs.dev/schemas/2.0.0/schema.json",
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

**Go** — `.golangci.yml`:

```yaml
linters:
  enable:
    - govet
    - errcheck
    - staticcheck
    - unused
    - gosimple
    - ineffassign
```

**Python** — `ruff.toml`:

```toml
line-length = 88

[lint]
select = ["E", "F", "I", "W"]
```

### Step 6: Test framework config

Set up a minimal test config. Do not install packages — just create the config file.

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

### Step 7: .gitignore

If `.gitignore` does not exist, create one with sensible defaults for the language:

**TypeScript**: `node_modules/`, `dist/`, `.env*.local`, `*.tsbuildinfo`
**Go**: binary name (project name), `vendor/` (optional)
**Python**: `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info/`, `.env*.local`

Always include: `.DS_Store`, `tmp/`

### Step 8: Summary

After scaffolding, run `tree -a -I '.git' --dirsfirst` and show the user what was created. List any files that were skipped because they already existed.

### Step 9: Initial commit

Stage all created files and make an initial commit:

```bash
git add <all created files>
git commit -m "chore: scaffold project with initial config"
```

Only commit the files that were created by this skill. Do not use `git add .` or `git add -A`.
