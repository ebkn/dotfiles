# Go

Resolve every version at scaffold time — see the rule in SKILL.md.

## go.mod — runtime pin

CI reads its Go version from `go.mod` via `go-version-file`, so this file is the runtime pin — but the `go` directive `go mod init` writes is the **language** version, not the toolchain you are running (observed: Go 1.26.0 wrote `go 1.25.0`). Left alone, CI provisions the first, unpatched release of an older line, while local verification silently runs the newer ambient toolchain (`GOTOOLCHAIN=auto` accepts any Go ≥ the directive) — so every gate, including govulncheck's stdlib check, would be verified against a different Go than CI uses. This is the one version-shaped value in the Go path that `go mod init` pins *for* you, wrongly; resolve it like everything else. If `go.mod` does not exist yet:

```bash
go mod init {module-path}
go mod edit -go={exact installed version}   # from `go version`, e.g. 1.26.0
```

`{module-path}` comes from intake question 6. A bare project name is valid for a private module; do not invent a `github.com/...` prefix the user never gave — the path is expensive to change once imports exist.

## Minimal package — the toolchain needs one to run at all

Go treats a module with no packages as an error rather than an empty success. On a module holding only `go.mod`, `go vet ./...` and `go test ./...` both exit 1 (`matched no packages`) and `golangci-lint run` exits 5 (`no go files to analyze`); only `go build ./...` exits 0. A Go scaffold with no source file therefore commits a CI pipeline that is red on its first run.

Tolerating those codes the way the Python CI tolerates pytest's 5 is not available here: a genuine `go vet` diagnostic also exits 1, so `|| [ $? -eq 1 ]` would swallow real failures along with the empty-scaffold case. Scaffold one file instead.

For `cli` / `api` — `main.go`:

```go
package main

import "fmt"

func main() {
	fmt.Println("{project-name}")
}
```

For `library` — `{package-name}.go`, where a package clause and doc comment are enough; the `unused` linter does not flag an empty package:

```go
// Package {package-name} {one-line description}
package {package-name}
```

No test file is needed. Unlike pytest, `go test ./...` prints `[no test files]` and exits 0 once a package exists.

## .golangci.yml — linter config

```yaml
version: "2"

# `standard` is golangci-lint's default set: errcheck, govet, ineffassign, staticcheck, unused.
# Add more under `enable:` — see https://golangci-lint.run/docs/linters/
linters:
  default: standard

# In v2, gofmt-family formatters live in their own section, NOT under linters.
# `golangci-lint run` reports unformatted files as issues (and fails), and
# `golangci-lint fmt` rewrites them — see the note below.
formatters:
  enable:
    - gofmt
```

The `version: "2"` key is **required**: golangci-lint v2 rejects a config without it (`unsupported version of the configuration`), so a v1-style bare `linters.enable` list fails before any linting runs. `gosimple` and `stylecheck` were merged into `staticcheck` in v2 and are no longer separate linter names — naming them is an error, not a no-op.

The `formatters` section is **not optional decoration** — it is the project's formatting gate. golangci-lint v2 split formatters (`gofmt`, `goimports`, `gofumpt`, `golines`) out of the `linters` set into their own section, so the `standard` linters above contain **no** format check. Without a `formatters` block, `golangci-lint run` passes on unformatted code — verified: with only `linters`, a misformatted file exits 0; adding `formatters: enable: [gofmt]` makes the same file exit 1 with `File is not properly formatted (gofmt)`. Because the gate lives inside `golangci-lint run`, the existing verification and CI steps enforce it with no extra line. `gofmt` matches what `go fmt` produces, so it never fights a developer's editor; reach for `gofumpt` (a stricter superset) only if the team wants its extra rules. To *apply* the formatting rather than just check it — the write-mode counterpart of `biome format --write` or `ruff format` — run `golangci-lint fmt`; record that in the CLAUDE.md Development section as the format command.

Verify any edit:

```bash
golangci-lint config verify
```

## Test config

None needed — `go test` works out of the box. Note the convention in the CLAUDE.md Development section:

```
### Test

go test ./...
```

## Unused-code detection

Already covered: the `unused` linter, part of the `standard` set selected above, reports unused constants, variables, functions, and types.

For whole-program dead-code detection across packages, note this in the CLAUDE.md Development section as an optional deeper pass:

```bash
go run golang.org/x/tools/cmd/deadcode@{version} ./...
```

It is not a hard gate because it needs a real entry point (`main`) to be meaningful.

Resolve `{version}` the same way as govulncheck below — `go list -m -json golang.org/x/tools@latest`, 7-day quarantine, literal version written in. Being a manual, occasional pass is **not** a reason to leave `@latest` here: it still executes freshly-published third-party code on a developer's machine, with a developer's credentials, and the resolution cost is one command that is already being run for the gate below.

## Vulnerability scanning — govulncheck

golangci-lint does **not** cover known-vulnerability scanning. `govulncheck` — the Go team's official scanner from `golang.org/x/vuln` — is a **separate tool**, deliberately *not* one of golangci-lint's linters: it has to build the program and query the vulnerability database, which does not fit golangci-lint's model, so naming it under `.golangci.yml`'s `enable:` is a config error (`golangci-lint config verify` rejects it), not a no-op. Wire it as its own gate:

```bash
go run golang.org/x/vuln/cmd/govulncheck@{version} ./...
```

**Resolve `{version}` at scaffold time and write the literal version in — never ship `@latest`.** `@latest` is a mutable reference that runs a release the instant it is published, with zero quarantine, inside the same workflow that SHA-pins and 7-day-quarantines every GitHub Action. Go's module proxy and checksum database do close the *other* half of the problem — published versions are immutable, so the tj-actions failure mode (re-pointing an existing tag at new code) cannot happen here — but neither defends against a **hijacked legitimate release**, which is exactly the window the 7-day quarantine exists to close. See `references/supply-chain.md` for the general rule.

Resolve it with the toolchain — `go list` reports the publish date alongside the version, so one command covers both steps:

```bash
go list -m -json golang.org/x/vuln@latest   # -> {"Version": "v1.6.0", "Time": "2026-07-09T17:23:02Z", ...}
```

If that `Time` is under 7 days old, step back to the newest release that is at least 7 days old (`go list -m -versions golang.org/x/vuln` lists them; re-run `go list -m -json …@vX.Y.Z` for each date). Then pin the chosen version and carry the same manual-update note the `golangci-lint` version pin carries — **no Dependabot ecosystem updates a version string inside a `run:` command**, so this is re-resolved by hand, naturally when bumping the Go toolchain or revisiting the CI gates.

Pinning the scanner does **not** stale the vulnerability data, which is the objection that usually kills this: govulncheck fetches the advisory database from `https://vuln.go.dev` at *run* time, not at build time. Verified — a pinned `govulncheck@v1.6.0` invoked on 2026-07-29 reports `DB updated: 2026-07-27`. You pin the analyzer; the data stays live.

> **Do not** reach for the Go 1.24 `tool` directive (`go get -tool golang.org/x/vuln/cmd/govulncheck`) to get Dependabot updates instead. Verified on a bare module, it injects six `// indirect` requires (`x/mod`, `x/sync`, `x/sys`, `x/telemetry`, `x/tools`, `x/vuln`) into the scaffold's own `go.mod`, putting the scanner's dependency tree into the application's MVS graph — so govulncheck can later force an upgrade of a library the project itself uses. It also does not buy what it promises: Dependabot version updates cover dependencies *explicitly defined in the manifest*, and enabling `dependency-type: indirect` to catch these would open PRs for every transitive dependency in the project. This is the same conclusion `references/supply-chain.md` already reaches for golangci-lint, for the same reason.

Unlike the `deadcode` pass above, this **is** a hard gate: its reachability analysis reports only vulnerabilities your code actually *calls* (transitively), so false positives are rare. It exits 0 when nothing reachable is vulnerable and non-zero when something is — the same contract the other gates use. Two properties to know:

- **It also checks the standard library against the pinned toolchain.** govulncheck analyzes source using the `go` on `PATH`, so it flags stdlib advisories for the exact Go version `go.mod` pins. On the fresh scaffold (minimal package, no third-party deps) it passes on a current stable Go; if it *fails* at scaffold time it is telling you the pinned toolchain itself carries a known vuln — bump the Go patch release rather than weakening the gate, the same "fix the scaffold, don't weaken the gate" rule as elsewhere.
- **A green run can turn red later with no code change.** It queries the live vulnerability database (network required), so a newly-disclosed advisory against a dependency you already call flips the next run red. That is the point — it is an alert, not a regression — but if you would rather a fresh disclosure not block an unrelated PR, run this on a schedule (a separate `cron` workflow) or as `continue-on-error` rather than inline in the PR gate.

## Health endpoint — `api` or any HTTP server

Skip for `library`/`cli`. This skill does not scaffold server code for Go, so there is nothing to write yet. When the server gets built, start from the standard library: `net/http` (its 1.22+ mux matches method-and-path patterns), reaching for `chi` only if routing genuinely outgrows that — not a heavier framework. Record that policy in the CLAUDE.md Development section now so the first server commit follows it. Then add a `GET /healthz` returning `200 {"status":"ok"}` and note the route there too; the deploy orchestrator uses it for readiness checks.

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(go test *)`, `Bash(go build *)`, `Bash(go vet *)`, `Bash(golangci-lint *)`, `Bash(go mod download)`, `Bash(go list -m *)`, `Bash(go run golang.org/x/vuln/cmd/govulncheck*)`, `Bash(go run golang.org/x/tools/cmd/deadcode*)`

Scope the two `go run` entries to those module paths rather than a blanket `Bash(go run *)`, which would let `go run` execute arbitrary code with no prompt. The list must cover every command this scaffold writes into README/CLAUDE.md: `go mod download` is the Setup command, `go list -m *` re-resolves the hand-updated pins, and `deadcode` is the documented optional pass — a documented command that always prompts is a scaffold bug. `go mod init` is deliberately absent: it runs once, at scaffold time, under this skill's own permissions.

## .gitignore entries

Beyond the shared block in SKILL.md Step 6:

- the compiled binary (the project name) — the verification's own `go build ./...` writes it into the repo root, so this entry must already exist when verification runs (Step 6's ordering guarantees that)
- `vendor/` — include it unless the project deliberately commits vendored dependencies

## Verification

Run the whole toolchain against the scaffold — all five must pass before moving on. These are the same gates `references/supply-chain.md` puts in CI, so a failure here is a failure that would land red on the first push:

```bash
go vet ./...
golangci-lint run
go test ./...
go build ./...
go run golang.org/x/vuln/cmd/govulncheck@{resolved version} ./...
```

Use the same resolved version here, in the CI workflow, and in the CLAUDE.md Development section — three copies of one pin, so a drifted copy means the gate you verified is not the gate CI runs.

If any of the first four reports `matched no packages` or `no go files to analyze`, the minimal package above is missing — fix that rather than weakening the gate. `govulncheck` needs network access to fetch the vulnerability database; if it reports a vulnerability against the pinned Go toolchain's standard library, bump the Go patch release rather than dropping the step.

On a fresh scaffold expect govulncheck to end with a note like `N vulnerabilities in packages you import and M vulnerabilities in modules you require` even on a zero-dependency module — those are *unreachable* (mostly stdlib) advisories, informational only, and the run still exits 0. Only the `Your code is affected by …` count gates; don't be alarmed by the note or "fix" it.
