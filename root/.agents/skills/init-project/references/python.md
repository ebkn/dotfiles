# Python

Resolve every version at scaffold time — see the rule in SKILL.md.

## .python-version — runtime pin

Pin the runtime so local, CI, and deploy agree; CI reads this file via `python-version-file`. Create `.python-version` holding the current stable Python the project targets — resolve it rather than copying one from here (`python3 --version` for what is installed locally, or https://www.python.org/downloads/ for what is current). Optionally also set `requires-python` in `pyproject.toml`.

## requirements-dev.txt — pinned dev tooling

CI and local runs both install the dev tooling from this file, so they agree on a version instead of each resolving whatever is newest that day. Resolve the current release of each (`pip index versions ruff`, or PyPI) and pin it exactly:

```
ruff=={resolved ruff version}
pytest=={resolved pytest version}
```

Pin with `==`, the pip counterpart of the `.npmrc` `save-exact=true` in `references/typescript.md`. Do not pin these in the workflow's `run:` line instead: Dependabot never reads shell commands, so such a pin has no updater and rots into a stale version — the exact failure the SHA-pinning section warns about. A requirements file is read by the `pip` Dependabot block in `references/supply-chain.md`, so the pin gets bumped on a schedule and the `cooldown` there gives it the same freshly-published quarantine that `min-release-age` gives npm. (Dependabot treats any `.txt` file whose name contains `requirements` as a requirements file, so this filename is picked up.)

## ruff.toml — linter config

```toml
line-length = 88

[lint]
select = ["E", "F", "I", "W"]
```

## pytest config

Add to `pyproject.toml`. If the file does not exist, create it with just this section; if it exists, append:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
```

Also create a `tests/` directory containing an empty `__init__.py`.

Note that pytest exits 5 — a failure — when it collects no tests, which is exactly the state of the fresh scaffold. The CI workflow in `references/supply-chain.md` tolerates that specific exit code; see the comment there for when to remove the tolerance.

## Unused-code detection

Partially covered: the ruff `F` rules selected above catch unused imports (`F401`) and unused local variables (`F841`).

Whole unused functions, classes, and methods need a dedicated tool — [vulture](https://github.com/jendrikseipp/vulture). It is **not** wired as a hard gate because it produces false positives on public APIs and dynamically-referenced code, and needs a whitelist to be usable in CI. Instead note `vulture .` in the CLAUDE.md Development section as an optional manual pass the maintainer can adopt once the codebase has shape.

## Health endpoint — `api` or any HTTP server

Skip for `library`/`cli`. This skill does not scaffold server code for Python, so there is nothing to write yet: when you create the server (FastAPI, Flask, …), add a `GET /healthz` returning `200 {"status":"ok"}` and note the route in the CLAUDE.md Development section. The deploy orchestrator uses it for readiness checks.

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(pytest *)`, `Bash(ruff *)`, `Bash(ruff check *)`, `Bash(ruff format *)`
- `Bash(pip install *)` if no pyproject.toml build system is obvious

## .gitignore entries

Beyond the shared block in SKILL.md Step 8:

- `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info/`

## Verification

Run the whole toolchain against the scaffold before moving on. These are the same gates `references/supply-chain.md` puts in CI:

```bash
ruff check .
ruff format --check .
pytest || [ $? -eq 5 ]
```

The `|| [ $? -eq 5 ]` mirrors the CI step and absorbs only the empty-scaffold case; a real test failure still exits 1. Unlike Go, nothing needs to be scaffolded to make these run: ruff passes on a tree whose only Python file is the empty `tests/__init__.py`.

Both tools must be on `PATH`, and this scaffold does not manage a Python environment (see Known gap below) — so they may simply not be installed. If they are missing, create an environment and install them there rather than into the system Python:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
```

then run the commands above as `.venv/bin/ruff` / `.venv/bin/pytest`. Install from `requirements-dev.txt`, not by naming the packages, so the local environment matches CI. `.venv/` is already in the `.gitignore` entries above. This install is deliberately left to prompt for approval: unlike the npm path, there is no `.npmrc` here applying `ignore-scripts`, so pip executes any package's build/install code — the one moment in this scaffold that deserves a human glance.

## Known gap

This path is still thinner than the TypeScript one. `requirements-dev.txt` pins the two direct dev tools and Dependabot keeps them fresh, but there is no lockfile, so their transitive dependencies (pytest pulls pluggy, iniconfig, packaging) resolve to whatever is newest at install time and are neither pinned nor hash-verified. Pinning a direct dependency narrows the hijack window for that package only; the npm path closes this properly with a committed `package-lock.json`.

`uv` with a committed `uv.lock` is the fix, and it is now viable rather than aspirational: dependabot-core ships a `uv` ecosystem, and `cooldown` supports it, so the migration keeps the update and quarantine story this skill relies on. That is a rewrite of this path (`uv sync --frozen` in CI as the `npm ci` equivalent, `pyproject.toml` as the manifest), not an edit — treat it as its own task.
