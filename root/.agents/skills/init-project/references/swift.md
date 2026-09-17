# Swift — macOS SwiftUI app

Scaffolds a native macOS `.app` (SwiftUI) whose project file is **generated, not committed**: `project.yml` (XcodeGen) is the source of truth, and `{AppName}.xcodeproj` is gitignored build output. That keeps the repo reviewable and agent-editable — an `.xcodeproj` is a merge-hostile plist blob no gate can meaningfully lint.

Resolve every version at scaffold time — see the rule in SKILL.md.

## Intake additions

1. **App name** — the product/target name (PascalCase; default: the project name PascalCased). Used for the source dirs, scheme, and bundle.
2. **Bundle ID prefix** — reverse-DNS (e.g. `dev.example`). Like the Go module path: never invent a domain the user didn't give. If they have none yet, use `local.{project-name}` and record in the CLAUDE.md Constraints section that it must be changed before any signing/distribution — a bundle ID is expensive to change once the app has user data (preferences, keychain, sandbox container are all keyed to it).
3. **Minimum macOS version** — default to the installed major (`sw_vers -productVersion`); record the choice in CLAUDE.md.

## Prerequisites — check, don't install

This path needs Xcode (not just Command Line Tools) plus two Homebrew tools. Check and **ask the user to install anything missing** rather than running installers from the scaffold:

```bash
xcodebuild -version      # full Xcode; CLT-only prints an error mentioning xcode-select
xcodegen --version
swiftlint version
```

`swift format` needs no install — it ships in the Swift 6+ toolchain. `periphery` (unused-code pass, below) is optional; check `periphery version` only if the user wants it.

Homebrew installs are unpinned by design; record the versions of `xcodegen` and `swiftlint` used at scaffold time in the CLAUDE.md Constraints section so a future behavior change can be traced to a tool bump.

## Version pins

- **`.xcode-version`** — plain-text Xcode version at the repo root (the XcodesOrg convention; read by CI below). Write the installed version from `xcodebuild -version`. This is the real toolchain pin for an Xcode-project app: the effective Swift version comes from the selected Xcode, so a `.swift-version` file would pin the wrong thing here — deliberately not created.

## project.yml — XcodeGen spec

XcodeGen over Tuist, deliberately: a single static YAML with no runtime, no account, and no server component, versus a Swift-manifest system oriented around Tuist's hosted platform (and which does not honor `.xcode-version`). XcodeGen also *generates* both `Info.plist` and the entitlements file from this spec, so neither is hand-maintained.

```yaml
name: {AppName}
options:
  bundleIdPrefix: {bundle-id-prefix}
  deploymentTarget:
    macOS: "{minimum macOS version}"
settings:
  base:
    SWIFT_VERSION: "{installed Swift major.minor, from `swift --version`}"
    # Ad-hoc signing ("Sign to Run Locally"): on Apple silicon every binary
    # needs at least an ad-hoc signature to launch, and the sandbox
    # entitlement below is only enforced when embedded in one. Real
    # Developer ID / notarization is a distribution-time TODO (CLAUDE.md).
    CODE_SIGN_IDENTITY: "-"
targets:
  {AppName}:
    type: application
    platform: macOS
    sources: [{AppName}]
    info:
      path: {AppName}/Info.plist
      properties:
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
    entitlements:
      path: {AppName}/{AppName}.entitlements
      properties:
        # Sandbox ON by default — matches Apple's own app template and is
        # mandatory for Mac App Store distribution. Opt capabilities back in
        # per-need (files.user-selected, network.client, …), never by
        # removing the sandbox key.
        com.apple.security.app-sandbox: true
        com.apple.security.files.user-selected.read-only: true
        # Any outbound network call — including error-tracking uploads — also
        # needs com.apple.security.network.client, or it fails silently.
        # references/sentry.md adds it when that overlay is chosen.
  {AppName}Tests:
    type: bundle.unit-test
    platform: macOS
    sources: [{AppName}Tests]
    dependencies:
      - target: {AppName}
```

Generate with `xcodegen generate` — it must be rerun after every `project.yml` edit and after adding a source file, because "my new file isn't building" is the predictable failure when someone forgets. Rather than documenting that as a thing to remember, the Makefile below makes `build` and `test` depend on it; note in the CLAUDE.md Development section that `make generate` exists for the cases those two don't cover (opening the project in Xcode, `periphery scan`).

## Sources — minimal app plus one testable unit

The split mirrors the other languages: the view layer stays thin, and one pure function exists so the scaffold ships a real behavior test.

`{AppName}/{AppName}App.swift`:

```swift
import SwiftUI

@main
struct {AppName}App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`{AppName}/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text(Greeting.message(for: "{project-name}"))
            .padding()
    }
}
```

`{AppName}/Greeting.swift`:

```swift
enum Greeting {
    static func message(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Hello" : "Hello, \(trimmed)"
    }
}
```

`{AppName}Tests/GreetingTests.swift` — **Swift Testing**, not XCTest: it is the default for new projects since Xcode 16 and ships in the toolchain. (XCTest remains the tool for UI tests via `XCUIApplication` — note that boundary in CLAUDE.md rather than scaffolding a UI-test target speculatively.)

```swift
import Testing

@testable import {AppName}

@Suite struct GreetingTests {
    @Test func greetsByName() {
        #expect(Greeting.message(for: "  World ") == "Hello, World")
    }

    @Test func fallsBackWhenEmpty() {
        #expect(Greeting.message(for: "   ") == "Hello")
    }
}
```

## Lint & format — two tools, disjoint jobs

- **`swift format`** (toolchain) owns formatting. Config is `.swift-format` at the root — scaffold the minimal anchor `{"version": 1}` (defaults apply; grow it only on a real disagreement). Check: `swift format lint --strict --recursive {AppName} {AppName}Tests`; write: `swift format --in-place --recursive {AppName} {AppName}Tests`. Both forms are wrapped by the Makefile below; `make format` is what CLAUDE.md records as the format command.
- **SwiftLint** owns the larger lint-rule catalog `swift format` doesn't attempt. `.swiftlint.yml`:

  ```yaml
  # Default rule set; opt-in rules added deliberately, not wholesale.
  included:
    - {AppName}
    - {AppName}Tests
  ```

  Gate form: `swiftlint --strict` (warnings fail). If a default rule fights the scaffold, prefer a named `disabled_rules` entry with a comment over loosening `--strict`, and record it in CLAUDE.md Constraints.

Neither tool supersedes the other as of 2026 — `swift format` covers formatting plus a small lint set; SwiftLint's catalog (opt-in, analyzer, custom rules) has no toolchain equivalent.

## Makefile — the one entry point

Every other language here already has a task runner (`package.json` scripts, `go`, `uv run`); Swift has none, and the raw commands are the longest in this skill — `xcodebuild -project … -scheme … -destination …` repeated four ways, each of which must stay identical in README.md, CLAUDE.md, and the CI workflow. Make is the thinnest thing that fixes that: it ships with the Command Line Tools (nothing to install, nothing to pin), and one `Makefile` at the repo root becomes the single place those flags are written.

It also removes the recall requirement this path otherwise warns about twice: `build` and `test` **depend on** `generate`, so a new source file cannot be compiled-but-not-in-the-target because someone forgot `xcodegen generate`.

```make
APP := {AppName}
PROJECT := $(APP).xcodeproj
SOURCES := $(APP) $(APP)Tests

# Project-local DerivedData, so `clean` is one `rm` of paths this repo owns.
# The shared location is ~/Library/Developer/Xcode/DerivedData/$(APP)-<hash>,
# and deleting that by glob would take out a same-named project elsewhere.
# Cost: Xcode.app's GUI builds keep using the shared location, so the CLI and
# the GUI do not share a build cache (recorded in CLAUDE.md Constraints).
DERIVED_DATA := DerivedData

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(APP) \
	-destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA)

.PHONY: all generate build test lint format clean

all: lint test

# Phony rather than a file rule: the target is a directory whose mtime XcodeGen
# rewrites on every run, so make cannot compare it against project.yml.
# Regenerating unconditionally is cheap; the failure it prevents is not.
generate:
	xcodegen generate

build: generate
	$(XCODEBUILD) build

# CODE_SIGNING_ALLOWED=NO matches CI exactly: no signing identity exists there,
# and disabling signing also avoids a significant xcodebuild slowdown. Unit
# tests run fine unsigned; only *launching* the .app needs the ad-hoc signature,
# which is what `build` (signing on) covers.
test: generate
	$(XCODEBUILD) test CODE_SIGNING_ALLOWED=NO

# No `generate` prerequisite: both tools read the source dirs, not the project.
lint:
	swift format lint --strict --recursive $(SOURCES)
	swiftlint --strict

format:
	swift format --in-place --recursive $(SOURCES)

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT)
```

Three things to get right when writing it, each of which fails quietly:

- **Recipe lines are indented with a literal TAB.** Spaces produce `missing separator`, which at least is loud — but an editor that silently expands tabs makes it recur. Check with `make -n build`: it parses the whole file and runs nothing, so it fails on a space-indented recipe without building. (`cat -t Makefile` shows the tabs as `^I` if you want to see them; don't reach for `grep -P`, which BSD grep on a stock macOS does not have.)
- **Each recipe line is its own shell, and make stops at the first non-zero status.** So `lint` runs `swiftlint` only when `swift format lint` passed — fail-fast is intended, but it means one green `make lint` does not prove both tools ran. The negative tests below provoke each separately for that reason.
- **`clean` deletes generated output only.** `$(PROJECT)` and `$(DERIVED_DATA)` are both gitignored (below). If a target here ever needs to delete something tracked, that is a design error, not a bigger `rm`.

Record `make clean` in the Build block of both README.md and CLAUDE.md — SKILL.md Step 2 requires those blocks to stay byte-identical, so it goes in both or neither.

Record in CLAUDE.md Constraints that `-derivedDataPath DerivedData` is deliberate and what it costs: **Xcode.app does not read the Makefile**, so a GUI build populates the shared `~/Library/Developer/Xcode/DerivedData` instead and the two caches are built independently. Someone who works in both will see full rebuilds when switching, and the obvious "fix" — dropping the flag — silently turns `make clean` into a no-op against a path it no longer owns.

## Unused-code detection — periphery (documented pass, not a CI gate)

[Periphery](https://github.com/peripheryapp/periphery) scans the generated Xcode project for unreachable declarations. It requires a full build for its index store, which on this path would roughly double CI time on 10×-priced macOS runners — so unlike knip/vulture, it is wired as a **documented local pass**, the same treatment the Go path gives `deadcode`. Scaffold `.periphery.yml`:

```yaml
project: {AppName}.xcodeproj
schemes: [{AppName}]
```

and record `periphery scan` in the CLAUDE.md Development section as the occasional deep pass. Run `make generate` first — periphery consumes the generated project, and it is deliberately not a Makefile target: the six targets there are the gates README.md advertises, and an occasional deep pass that needs a full index build does not belong among them.

## .gitignore additions

Beyond the shared block in SKILL.md Step 6:

```
{AppName}.xcodeproj/
{AppName}/Info.plist
{AppName}/{AppName}.entitlements
DerivedData/
.build/
```

The first three are **XcodeGen output** — regenerated from `project.yml`, the same generated-file rule as `next-env.d.ts`/`worker-configuration.d.ts`. Tracking the `.xcodeproj` would immediately fork two sources of truth. `DerivedData/` is not defensive here: the Makefile puts build output there on purpose, so this line is what keeps it out of the repo.

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(make generate)`, `Bash(make build)`, `Bash(make test)`, `Bash(make lint)`, `Bash(make format)`, `Bash(make clean)`
- `Bash(xcodegen generate)`, `Bash(swift format *)`, `Bash(swiftlint *)`, `Bash(xcodebuild build*)`, `Bash(xcodebuild test*)`, `Bash(xcodebuild -version)`, `Bash(periphery scan*)`

The second line stays even though the Makefile wraps all of it — the targets are the everyday entry point, not a boundary, and an agent debugging a build needs the underlying command without a prompt per invocation.

The `make` targets are **enumerated, not `Bash(make *)`.** A wildcard pre-approves every target the Makefile will ever grow, including the signing/notarization ones the section below defers — and those are exactly the distribution actions this list keeps prompted. Extend the enumeration when a target is added; that one-line cost is the point.

Deliberately not allow-listed: `open {AppName}.app` / launching the GUI (a visible side effect on the user's machine), and any `xcodebuild archive`/signing/notarization command — distribution actions stay prompted.

## CI

Follow `references/supply-chain.md` for the workflow scaffolding rules (SHA pins, quarantine, least-privilege token, concurrency); the Swift job body is:

```yaml
jobs:
  ci:
    # macOS runners bill ~10x Linux minutes on private repos — keep this job lean
    # and don't add matrix dimensions casually.
    runs-on: macos-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@{sha} # {tag}
        with:
          persist-credentials: false
      # Pin Xcode to .xcode-version. The version must exist on the runner image
      # (github.com/actions/runner-images lists what each image ships) — when
      # writing .xcode-version at scaffold time, prefer a version the current
      # image carries, or this step fails before anything builds.
      - run: sudo xcode-select -s "/Applications/Xcode_$(cat .xcode-version).app"
      # Homebrew installs are mutable references — the accepted trade here, since
      # neither tool has a supported pinned-install path and both only gate style,
      # not runtime behavior. The compiler itself is pinned via .xcode-version.
      - run: brew install xcodegen swiftlint
      # Both targets carry their own flags (and `test` regenerates the project
      # first), so CI runs the same commands as a developer. Spelling the
      # xcodebuild invocation out here instead would fork it from the Makefile,
      # and the fork is invisible until the two disagree.
      - run: make lint
      - run: make test
```

No Swift/SPM caching is scaffolded: with zero package dependencies there is nothing meaningful to cache, and DerivedData caching is not a supported pattern. Add `actions/cache` on `~/Library/Caches/org.swift.swiftpm` only once real SPM dependencies exist.

## Signing & distribution — the recorded TODO

Local dev runs on the ad-hoc identity from `project.yml` (`CODE_SIGN_IDENTITY: "-"`); nothing more is needed to build, test, and launch on the developer's own machine. Everything beyond that is deliberately out of scope — record this block in the CLAUDE.md Launch Readiness section (this path's replacement for the web-oriented default in SKILL.md Step 3):

> Distribution is not scaffolded. Shipping outside this machine needs, in order: an Apple Developer account; a real bundle identifier (see Constraints); Developer ID signing + notarization for direct distribution, or App Store signing + review for the Mac App Store; and a re-check of the sandbox entitlements against every capability the app actually uses.

## Verification

Run against the fresh scaffold — all five must pass before moving on. `lint` and `test` are the exact commands CI runs, so a failure here is a failure that would land red on the first push:

```bash
make generate
make lint
make build
make test
make clean
```

`build` keeps signing on (ad-hoc identity), which verifies the locally-runnable `.app` path; `test` passes `CODE_SIGNING_ALLOWED=NO`, which is what CI runs. Formatting failures on the hand-written snippets above are expected on first run — `make format` once, then the gate judges substance. If `make generate` succeeds but the build cannot find sources, the `sources` dirs in `project.yml` don't match the created directories — fix the spec, never hand-edit the generated `.xcodeproj`.

**`make clean` needs its own assertion, and it goes last.** Every other target here fails loudly; a `clean` that deletes nothing exits 0 and looks identical to one that works — a typo'd variable expands to the empty string and `rm -rf` succeeds on no arguments. Assert the observable effect, then that the tree still builds:

```bash
make build                       # populate both paths
ls -d DerivedData {AppName}.xcodeproj   # both must exist
make clean
ls -d DerivedData {AppName}.xcodeproj   # both must now be gone (ls exits non-zero)
make build                       # positive control: a cleaned tree rebuilds
make clean
```

The final rebuild is the half that catches over-deletion: a `clean` that also removed `project.yml` or a source dir would pass the `ls` check and fail here.

### Then prove each gate rejects something

Two tools run here with disjoint jobs, and each can be silently inert — `swift format` with no config still lints, but `swiftlint` reads `.swiftlint.yml` and a config it cannot parse leaves you with a command that exits 0 on everything. Provoke each, confirm a **non-zero** exit, and delete the violation before the next.

These two run as the **raw commands, not `make lint`**: make stops at the first failing recipe line, so `make lint` cannot distinguish "swiftlint rejected this" from "swiftlint never ran". Attribution needs them invoked one at a time.

```bash
# swift format lint --strict — bad formatting must be caught
printf 'struct Gate {\n        let x    =   1\n}\n' > {AppName}/Gate.swift
swift format lint --strict --recursive {AppName} {AppName}Tests   # must FAIL
rm {AppName}/Gate.swift

# swiftlint --strict — a lint violation must be caught
# use a rule swift format does NOT also flag, so the failure is attributable
printf 'struct Gate {\n  let x = 1\n  func f() { let a = 1; _ = a }\n}\n' > {AppName}/Gate.swift
swiftlint --strict            # must FAIL
rm {AppName}/Gate.swift

# make test — a failing test must be caught
# add a temporary failing case to {AppName}Tests, then:
make test                     # must FAIL
```

Also prove `make lint` itself still rejects: after the two raw runs, leave one violation in place, run `make lint`, confirm non-zero, and remove it. A Makefile whose `lint` recipe names the wrong paths passes both raw checks and gates nothing.

Two things this path gets wrong more often than the others.

**Regenerate before each run — or let make do it.** `xcodegen generate` is what puts a new file into the target; a violation file added without regenerating is not compiled and the gate passes while proving nothing. `make build` / `make test` depend on `generate`, so going through the targets closes this. It reopens the moment a raw `xcodebuild` is run by hand for debugging — that invocation compiles whatever the last `generate` captured.

**Read the exit status, not the output.** `xcodebuild` prints a great deal on success and failure alike, and `** TEST FAILED **` scrolls past easily; `make` adds its own output above and below it. Check `$?` — make propagates the recipe's status, so `make test` is as trustworthy a gate as the bare command. A test-failure negative test judged by eye is the one most likely to be recorded as passed without having been run.

Confirm `git status --porcelain` is clean before moving on — including the regenerated `.xcodeproj` if it is tracked, and any `Gate.swift` left behind.
