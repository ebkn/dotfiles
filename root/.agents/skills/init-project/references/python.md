# Python (uv)

Resolve every version at scaffold time — see the rule in SKILL.md.

This path uses [uv](https://docs.astral.sh/uv/) as the package manager, so it reaches the same bar as the TypeScript path: a committed lockfile that pins **every** dependency — direct and transitive — to an exact version with a hash, plus a freshly-published-version quarantine. `uv` must be installed (`uv --version`); if it is not, stop and install it (`brew install uv`, or the official installer) rather than falling back to bare `pip`, which cannot produce the lockfile the rest of this file relies on.

## Project init & runtime pin

Create the project skeleton and pin the runtime in one step. Pick the kind from the intake project type:

- `cli` / `api` / `internal-web` / `public-web` → `uv init --app --name {project-name}`
- `library` → `uv init --lib --name {project-name}` (sets up a build backend so the package is importable and publishable)

Then pin the Python version so local, CI, and deploy all read the same `.python-version`:

```bash
uv python pin {current stable Python, e.g. 3.14}
```

Resolve the version rather than copying one from here — `uv python list` shows what is available, https://www.python.org/downloads/ shows what is current. `uv init` writes `requires-python` into `pyproject.toml`; keep the two consistent.

`uv init` also drops a `main.py` entry point (for `--app`) and, if none exists, a `README.md`. It does **not** overwrite files, so the README from Step 2 and the git repo from Step 1 survive untouched — running it after those steps is safe (verified). Replace the `description = "Add your description here"` it writes with the intake one-line description.

## Freshly-published-version quarantine — do this before adding any dependency

Add uv's `exclude-newer` gate to `pyproject.toml` **before** the first `uv add`, so the very install that pulls in the whole tree is already covered — the same ordering the TypeScript path requires for `.npmrc`:

```toml
[tool.uv]
exclude-newer = "7 days ago"
```

This is the counterpart of the `.npmrc` `min-release-age=7` in `references/typescript.md`: it refuses any release uploaded in the last 7 days, narrowing the window in which a freshly-hijacked version can be pulled. `"7 days ago"` is a **relative** value uv re-evaluates on every resolve, so the window keeps rolling; it is not frozen to scaffold day. (uv accepts an absolute `YYYY-MM-DD` too, but that one does not roll.)

## Dev tooling

With the quarantine in place, add the linter and test runner to the `dev` dependency group:

```bash
uv add --dev ruff pytest
```

This writes `>=`-style entries under `[dependency-groups]` in `pyproject.toml` and — crucially — pins exact versions of ruff, pytest, **and all their transitive dependencies** with hashes into `uv.lock`. Commit `uv.lock`; it is the `package-lock.json` equivalent and the whole reason this path exists.

## ruff.toml — linter config

```toml
line-length = 88

[lint]
select = ["E", "F", "I", "W"]
```

## pytest config

Add to `pyproject.toml` (it already exists after `uv init`):

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
```

Create a `tests/` directory containing an empty `__init__.py`.

Note that pytest exits 5 — a failure — when it collects no tests, which is exactly the state of the fresh scaffold, and `uv run pytest` propagates that 5. The CI workflow in `references/supply-chain.md` tolerates that specific exit code; see the comment there for when to remove the tolerance.

## Unused-code detection

Partially covered: the ruff `F` rules selected above catch unused imports (`F401`) and unused local variables (`F841`).

Whole unused functions, classes, and methods need a dedicated tool — [vulture](https://github.com/jendrikseipp/vulture). It is **not** wired as a hard gate because it produces false positives on public APIs and dynamically-referenced code, and needs a whitelist to be usable in CI. Instead note `uv run vulture .` in the CLAUDE.md Development section as an optional manual pass the maintainer can adopt once the codebase has shape (add it with `uv add --dev vulture` if they want it available).

## Health endpoint — `api` or any HTTP server

Skip for `library`/`cli`. This skill does not scaffold server code for Python, so there is nothing to write yet: when you create the server (FastAPI, Flask, …), add a `GET /healthz` returning `200 {"status":"ok"}` and note the route in the CLAUDE.md Development section. The deploy orchestrator uses it for readiness checks.

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(uv run *)`, `Bash(uv sync *)`, `Bash(uv add *)`, `Bash(uv lock *)`, `Bash(uv python pin *)`

Everything runs through `uv run`, so `Bash(pytest *)` / `Bash(ruff *)` are not needed unless you also invoke the tools outside uv.

## .gitignore entries

Beyond the shared block in SKILL.md Step 8:

- `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info/`

Do **not** ignore `uv.lock` — it is committed on purpose, exactly like `package-lock.json`.

## Verification

Run the whole toolchain against the scaffold before moving on. These are the same gates `references/supply-chain.md` puts in CI:

```bash
uv sync --locked
uv run ruff check .
uv run ruff format --check .
uv run pytest || [ $? -eq 5 ]
```

`uv sync --locked` is the `npm ci` of this path: it installs strictly from `uv.lock` and **fails** if the lock is out of date with `pyproject.toml`, so a hand-edit that forgets to re-lock cannot slip through. Do not use `uv sync --frozen` here — `--frozen` installs from the lock without checking it against `pyproject.toml`, so it silently tolerates the very drift `--locked` is meant to catch.

The `|| [ $? -eq 5 ]` mirrors the CI step and absorbs only the empty-scaffold case; a real test failure still exits 1.

## Optional: refuse to build source distributions

For an application (not a `library`), you can add `--no-build` to the CI `uv sync` to install only pre-built wheels, so no dependency's `setup.py` build code runs — the nearest uv analogue to the npm `ignore-scripts=true`. It is **not** the default because it is narrower than it looks: it breaks the moment any dependency ships sdist-only, and it cannot install a `library` project's own package (verified: `uv sync --no-build` on a packaged project fails with "marked as `--no-build` but has no binary distribution"). Reach for it only on an app whose dependency set is known to be all-wheel, and expect to drop it when that stops being true.
