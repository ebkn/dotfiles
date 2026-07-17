# Python

Resolve every version at scaffold time — see the rule in SKILL.md.

## .python-version — runtime pin

Pin the runtime so local, CI, and deploy agree; CI reads this file via `python-version-file`. Create `.python-version` holding the current stable Python the project targets — resolve it rather than copying one from here (`python3 --version` for what is installed locally, or https://www.python.org/downloads/ for what is current). Optionally also set `requires-python` in `pyproject.toml`.

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

## Known gap

This path is thinner than the TypeScript one: no package manager (`uv`), no lockfile, and CI installs `ruff pytest` unpinned — which sits awkwardly beside the pinning discipline the rest of this skill enforces. Consider moving to `uv` with a committed `uv.lock` when this matters.
