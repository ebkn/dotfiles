# CI, Dependabot & supply-chain hardening

The skill writes lint/typecheck/test scripts but nothing enforces them. Add a CI workflow that runs the gates on every push and PR, plus Dependabot for updates. Generate only the block matching the chosen language.

`{sha}` and `{tag}` below are placeholders, not literals. Resolve each action's current release and its SHA at scaffold time using the hardening section further down, and write both in. Never copy a version out of this file: any tag written here is only as fresh as the last edit to it.

## .github/workflows/ci.yml

### TypeScript / Next.js

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

# Cancel superseded runs so a burst of pushes doesn't queue up N full pipelines.
# head_ref groups a PR's own runs together (stale ones get cancelled); the run_id
# fallback gives each push to main a unique group, so main runs are never cancelled
# — every commit on main keeps a complete CI result.
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

permissions:
  contents: read # least-privilege GITHUB_TOKEN; escalate per-job only where a step needs write

jobs:
  ci:
    runs-on: ubuntu-latest
    timeout-minutes: 15 # cap a hung or runaway job; GitHub's default is 360 (6h). Raise if a real build needs more.
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
      - run: npm run build   # Next.js only — the plain TS scaffold has no build script by default; drop this unless you added one
```

### Go

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

# Cancel superseded runs so a burst of pushes doesn't queue up N full pipelines.
# head_ref groups a PR's own runs together (stale ones get cancelled); the run_id
# fallback gives each push to main a unique group, so main runs are never cancelled
# — every commit on main keeps a complete CI result.
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

permissions:
  contents: read # least-privilege GITHUB_TOKEN; escalate per-job only where a step needs write

jobs:
  ci:
    runs-on: ubuntu-latest
    timeout-minutes: 15 # cap a hung or runaway job; GitHub's default is 360 (6h). Raise if a real build needs more.
    steps:
      - uses: actions/checkout@{sha} # {tag}
        with:
          persist-credentials: false
      - uses: actions/setup-go@{sha} # {tag}
        with:
          go-version-file: go.mod
      # These steps require the module to contain at least one package: on a module holding only
      # go.mod, `go vet`/`go test` exit 1 and golangci-lint exits 5. references/go.md scaffolds a
      # minimal package for exactly this reason — there is no safe exit-code tolerance for Go,
      # since a real vet diagnostic exits 1 too.
      - run: go vet ./...
      - uses: golangci/golangci-lint-action@{sha} # {tag}
        with:
          version: {latest golangci-lint 2.x} # must be a v2 release to match the v2 config from references/go.md
      - run: go test ./...
      - run: go build ./...
```

### Python

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

# Cancel superseded runs so a burst of pushes doesn't queue up N full pipelines.
# head_ref groups a PR's own runs together (stale ones get cancelled); the run_id
# fallback gives each push to main a unique group, so main runs are never cancelled
# — every commit on main keeps a complete CI result.
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

permissions:
  contents: read # least-privilege GITHUB_TOKEN; escalate per-job only where a step needs write

jobs:
  ci:
    runs-on: ubuntu-latest
    timeout-minutes: 15 # cap a hung or runaway job; GitHub's default is 360 (6h). Raise if a real build needs more.
    steps:
      - uses: actions/checkout@{sha} # {tag}
        with:
          persist-credentials: false
      # setup-uv installs uv itself; uv then provisions the Python pinned in .python-version, so no
      # actions/setup-python step is needed. The action is SHA-pinned (Dependabot bumps it) and
      # installs the current uv — the same way setup-node supplies npm. Do not add a version-file /
      # required-version uv pin: the uv Dependabot ecosystem bumps dependencies, not that constraint,
      # so it would be an un-updated pin that rots — the failure the SHA-pinning section warns about.
      - uses: astral-sh/setup-uv@{sha} # {tag}
      # `uv sync --locked` is the `npm ci` of this path: installs strictly from uv.lock — every
      # dependency exact-pinned and hashed — and fails if the lock is stale against pyproject.toml.
      - run: uv sync --locked
      - run: uv run ruff check .
      - run: uv run ruff format --check .
      - run: uv run mypy .
      # pytest exits 5 when it collects no tests, which would fail CI on the fresh scaffold, and
      # `uv run` propagates that 5. This is the Python counterpart of vitest's --passWithNoTests;
      # drop `|| [ $? -eq 5 ]` once a real suite exists so a silent collection failure fails CI again.
      # A genuine test failure still exits 1 and fails the step.
      - run: uv run pytest || [ $? -eq 5 ]
```

## Hardening the workflow

The templates above bake in three controls. Apply the SHA-pinning step before you commit:

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

  Do this for `actions/checkout`, `actions/setup-node`/`setup-go`, `astral-sh/setup-uv`, `golangci/golangci-lint-action`, and any other third-party action. The `github-actions` Dependabot block below then bumps both the SHA and the comment as new releases land, so pinning doesn't rot into a stale (possibly vulnerable) version.

## .github/dependabot.yml

Set `package-ecosystem` to `npm` / `gomod` / `uv` for the project language; the `github-actions` block keeps the SHA-pinned workflow actions current. `cooldown` mirrors the per-project publish-age gate (`.npmrc` `min-release-age`, `[tool.uv] exclude-newer`) so Dependabot doesn't open a PR onto a just-published — possibly hijacked — version. Grouping keeps PR noise down while keeping majors isolated (see the comment on `groups`):

```yaml
version: 2
updates:
  - package-ecosystem: "npm" # gomod | uv — match the project language
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 7 # hold back freshly-published versions; cooldown supports npm, gomod and uv
    groups:
      # Bundle only minor + patch into one low-risk PR. Majors match no group, so each
      # arrives as its own PR (Dependabot's default for ungrouped updates) — a breaking
      # major can't hold the safe minor/patch updates hostage inside a single red batch PR.
      # If you'd rather minimize PR count, drop `update-types` and group everything with
      # `patterns: ["*"]` alone — but then accept that one failing major blocks the batch.
      minor-and-patch:
        patterns: ["*"]
        update-types: ["minor", "patch"]
  - package-ecosystem: "github-actions" # keeps SHA pins current; cooldown is NOT supported for this ecosystem
    directory: "/"
    schedule:
      interval: "weekly"
  # Add this block ONLY if the project ships a Dockerfile — keeps the pinned base-image digest fresh:
  # - package-ecosystem: "docker"
  #   directory: "/"
  #   schedule:
  #     interval: "weekly"
  #   cooldown:
  #     default-days: 7
```

## Container image pinning — only if the project ships a Dockerfile

This skill does not scaffold a Dockerfile. But if the project deploys as a container and one gets added, pin its supply chain the same way the workflow is pinned — an unpinned base image is a mutable dependency pulled on every build:

- **Pin the base image by tag *and* digest.** A bare tag (`FROM node:22`) is re-pushable; the `@sha256:` digest is the immutable, verifiable reference:

  ```dockerfile
  FROM node:{current tag}@sha256:{resolved digest}
  ```

  Resolve the current tag and its digest when you write the Dockerfile — `docker buildx imagetools inspect node:{tag}` prints the digest. Keep the human-readable tag in front so Dependabot's `docker` ecosystem (uncomment the block above) can bump both tag and digest as new releases land — otherwise the pin rots into a stale, possibly-vulnerable image.
- **Pin OS packages** to explicit versions (`apt-get install -y curl={version}`, resolved against the base image's distro), add `--no-install-recommends`, and clean the apt lists in the same layer.
- **Install app deps from the lockfile only** — `npm ci`, never `npm install`. `npm ci` fails on a lockfile mismatch and honors the `.npmrc` (`save-exact`, `min-release-age`, `ignore-scripts`) from `references/typescript.md`.
- **Run as a non-root `USER`** and copy only what the build needs (use `.dockerignore`) to shrink the attack surface.
