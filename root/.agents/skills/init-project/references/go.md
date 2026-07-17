# Go

Resolve every version at scaffold time — see the rule in SKILL.md.

## go.mod — runtime pin

The `go` directive in `go.mod` pins the toolchain, and CI reads it via `go-version-file`. If `go.mod` does not exist yet:

```bash
go mod init {module-path}
```

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

Skip for `library`/`cli`. This skill does not scaffold server code for Go, so there is nothing to write yet: when you create the server (Gin, net/http, …), add a `GET /healthz` returning `200 {"status":"ok"}` and note the route in the CLAUDE.md Development section. The deploy orchestrator uses it for readiness checks.

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(go test *)`, `Bash(go build *)`, `Bash(go vet *)`, `Bash(golangci-lint *)`, `Bash(go mod init *)`

## .gitignore entries

Beyond the shared block in SKILL.md Step 8:

- the compiled binary (the project name)
- `vendor/` (optional)
