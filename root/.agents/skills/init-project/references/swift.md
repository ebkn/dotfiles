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
  {AppName}Tests:
    type: bundle.unit-test
    platform: macOS
    sources: [{AppName}Tests]
    dependencies:
      - target: {AppName}
```

Generate with `xcodegen generate` — rerun after every `project.yml` edit; note that in the CLAUDE.md Development section, because "my new file isn't building" is the predictable failure when someone forgets.

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

- **`swift format`** (toolchain) owns formatting. Config is `.swift-format` at the root — scaffold the minimal anchor `{"version": 1}` (defaults apply; grow it only on a real disagreement). Check: `swift format lint --strict --recursive {AppName} {AppName}Tests`; write: `swift format --in-place --recursive {AppName} {AppName}Tests`. Record the write form in CLAUDE.md as the format command.
- **SwiftLint** owns the larger lint-rule catalog `swift format` doesn't attempt. `.swiftlint.yml`:

  ```yaml
  # Default rule set; opt-in rules added deliberately, not wholesale.
  included:
    - {AppName}
    - {AppName}Tests
  ```

  Gate form: `swiftlint --strict` (warnings fail). If a default rule fights the scaffold, prefer a named `disabled_rules` entry with a comment over loosening `--strict`, and record it in CLAUDE.md Constraints.

Neither tool supersedes the other as of 2026 — `swift format` covers formatting plus a small lint set; SwiftLint's catalog (opt-in, analyzer, custom rules) has no toolchain equivalent.

## Unused-code detection — periphery (documented pass, not a CI gate)

[Periphery](https://github.com/peripheryapp/periphery) scans the generated Xcode project for unreachable declarations. It requires a full build for its index store, which on this path would roughly double CI time on 10×-priced macOS runners — so unlike knip/vulture, it is wired as a **documented local pass**, the same treatment the Go path gives `deadcode`. Scaffold `.periphery.yml`:

```yaml
project: {AppName}.xcodeproj
schemes: [{AppName}]
```

and record `periphery scan` in the CLAUDE.md Development section as the occasional deep pass. Run `xcodegen generate` first — periphery consumes the generated project.

## .gitignore additions

Beyond the shared block in SKILL.md Step 6:

```
{AppName}.xcodeproj/
{AppName}/Info.plist
{AppName}/{AppName}.entitlements
DerivedData/
.build/
```

The first three are **XcodeGen output** — regenerated from `project.yml`, the same generated-file rule as `next-env.d.ts`/`worker-configuration.d.ts`. Tracking the `.xcodeproj` would immediately fork two sources of truth.

## .claude/settings.json entries

Add to the `allow` list from SKILL.md Step 5:

- `Bash(xcodegen generate)`, `Bash(swift format *)`, `Bash(swiftlint *)`, `Bash(xcodebuild build*)`, `Bash(xcodebuild test*)`, `Bash(xcodebuild -version)`, `Bash(periphery scan*)`

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
      - run: xcodegen generate
      - run: swift format lint --strict --recursive {AppName} {AppName}Tests
      - run: swiftlint --strict
      # CODE_SIGNING_ALLOWED=NO: no signing identity exists in CI, and disabling
      # signing also avoids a significant xcodebuild slowdown. Unit tests run
      # fine unsigned; only *launching* the .app needs the ad-hoc signature.
      - run: xcodebuild test -project {AppName}.xcodeproj -scheme {AppName} -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

No Swift/SPM caching is scaffolded: with zero package dependencies there is nothing meaningful to cache, and DerivedData caching is not a supported pattern. Add `actions/cache` on `~/Library/Caches/org.swift.swiftpm` only once real SPM dependencies exist.

## Signing & distribution — the recorded TODO

Local dev runs on the ad-hoc identity from `project.yml` (`CODE_SIGN_IDENTITY: "-"`); nothing more is needed to build, test, and launch on the developer's own machine. Everything beyond that is deliberately out of scope — record this block in the CLAUDE.md Launch Readiness section (this path's replacement for the web-oriented default in SKILL.md Step 3):

> Distribution is not scaffolded. Shipping outside this machine needs, in order: an Apple Developer account; a real bundle identifier (see Constraints); Developer ID signing + notarization for direct distribution, or App Store signing + review for the Mac App Store; and a re-check of the sandbox entitlements against every capability the app actually uses.

## Verification

Run against the fresh scaffold — all five must pass before moving on. The build and test steps are the same commands CI runs (modulo signing mode), so a failure here is a failure that would land red on the first push:

```bash
xcodegen generate
swift format lint --strict --recursive {AppName} {AppName}Tests
swiftlint --strict
xcodebuild build -project {AppName}.xcodeproj -scheme {AppName} -destination 'platform=macOS'
xcodebuild test -project {AppName}.xcodeproj -scheme {AppName} -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

The plain `build` (ad-hoc identity, signing on) verifies the locally-runnable `.app` path; the `test` invocation with `CODE_SIGNING_ALLOWED=NO` verifies exactly what CI will run. Formatting failures on the hand-written snippets above are expected on first run — apply `swift format --in-place --recursive {AppName} {AppName}Tests` once, then the gate judges substance. If `xcodegen generate` succeeds but the build cannot find sources, the `sources` dirs in `project.yml` don't match the created directories — fix the spec, never hand-edit the generated `.xcodeproj`.
