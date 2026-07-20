# Go

Resolve every version at scaffold time — see the rule in SKILL.md.

## go.mod — runtime pin

The `go` directive in `go.mod` pins the toolchain, and CI reads it via `go-version-file`. If `go.mod` does not exist yet:

```bash
go mod init {module-path}
```

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
```

The `version: "2"` key is **required**: golangci-lint v2 rejects a config without it (`unsupported version of the configuration`), so a v1-style bare `linters.enable` list fails before any linting runs. `gosimple` and `stylecheck` were merged into `staticcheck` in v2 and are no longer separate linter names — naming them is an error, not a no-op.

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
go run golang.org/x/tools/cmd/deadcode@latest ./...
```

It is not a hard gate because it needs a real entry point (`main`) to be meaningful.

## Health endpoint — `api` or any HTTP server

Skip for `library`/`cli`. This skill does not scaffold server code for Go, so there is nothing to write yet. When the server gets built, start from the standard library: `net/http` (its 1.22+ mux matches method-and-path patterns), reaching for `chi` only if routing genuinely outgrows that — not a heavier framework. Record that policy in the CLAUDE.md Development section now so the first server commit follows it. Then add a `GET /healthz` returning `200 {"status":"ok"}` and note the route there too; the deploy orchestrator uses it for readiness checks.

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(go test *)`, `Bash(go build *)`, `Bash(go vet *)`, `Bash(golangci-lint *)`, `Bash(go mod init *)`

## .gitignore entries

Beyond the shared block in SKILL.md Step 8:

- the compiled binary (the project name)
- `vendor/` (optional)

## Verification

Run the whole toolchain against the scaffold — all four must pass before moving on. These are the same gates `references/supply-chain.md` puts in CI, so a failure here is a failure that would land red on the first push:

```bash
go vet ./...
golangci-lint run
go test ./...
go build ./...
```

If any of them reports `matched no packages` or `no go files to analyze`, the minimal package above is missing — fix that rather than weakening the gate.
