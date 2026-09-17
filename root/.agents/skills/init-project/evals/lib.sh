# lib.sh — the fixture the init-project eval cases share.
#
# The Swift path drives Xcode: xcodebuild, xcodegen, swiftlint and the
# toolchain's `swift format`. Running them for real would need a full Xcode on
# whatever machine grades the case and a genuine compile per run — minutes, and
# a different answer on a machine with a different Xcode. So they are stubbed on
# PATH, in the fixture's bin/, which bin/skill-eval prepends for `claude -p` and
# keeps out of the fixture's git.
#
# The stubs decide nothing. Each records its argv and exits 0, and the only side
# effects are the two the Makefile is supposed to produce: the generated
# .xcodeproj and the DerivedData directory. That leaves `make`, the Makefile the
# skill wrote, and the shell running it all real, so a case can assert on what
# the Makefile actually passed rather than on what it says it passes.
#
# The limit that buys, stated here rather than discovered from a green run: a
# case cannot see whether the app compiles, whether .swiftlint.yml parses, or
# whether any gate would reject anything. It measures the scaffold, not the
# toolchain. Anything about the toolchain belongs in the skill's own
# Verification block, run against a real machine.
#
# Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# init_project_write_toolchain_stubs
# Writes the Xcode toolchain stubs into bin/. Call it *after*
# skill_eval_init_repo: bin/ has to stay untracked, and the runner only adds it
# to .git/info/exclude once the scaffold has finished.
init_project_write_toolchain_stubs() {
  mkdir -p bin

  # Every stub appends here, so a case can read the real argv the Makefile
  # produced -- the flags are the thing under test, and a Makefile that passes
  # the wrong ones still exits 0.
  : >bin/calls.log

  cat >bin/xcodebuild <<'STUB'
#!/bin/bash
set -eo pipefail
printf 'xcodebuild %s\n' "$*" >>"$(dirname "$0")/calls.log"

case " $* " in
  *" -version "*)
    printf 'Xcode 26.0\nBuild version 26A100\n'
    exit 0
    ;;
esac

# Create whatever -derivedDataPath was given, so a case can see where build
# output would have landed. No flag means the shared location, and nothing is
# created -- which is exactly the state a project-local `clean` cannot clean.
prev=""
for arg in "$@"; do
  if [ "$prev" = "-derivedDataPath" ]; then
    mkdir -p "$arg/Build/Products"
  fi
  prev="$arg"
done

printf '** BUILD SUCCEEDED **\n'
STUB

  cat >bin/xcodegen <<'STUB'
#!/bin/bash
set -eo pipefail
printf 'xcodegen %s\n' "$*" >>"$(dirname "$0")/calls.log"

case "${1:-}" in
  --version | version)
    printf '2.44.1\n'
    exit 0
    ;;
esac

# Read the name out of project.yml rather than taking it from the case: this is
# the one stub that is allowed to fail, because "generate succeeded but the
# spec names nothing" is a scaffold error worth surfacing as a failure.
if [ ! -f project.yml ]; then
  printf 'xcodegen: no project.yml in %s\n' "$PWD" >&2
  exit 1
fi
name="$(sed -n 's/^name:[[:space:]]*//p' project.yml | head -n 1)"
if [ -z "$name" ]; then
  printf 'xcodegen: project.yml has no name\n' >&2
  exit 1
fi
mkdir -p "$name.xcodeproj"
printf 'Created project at %s.xcodeproj\n' "$name"
STUB

  cat >bin/swiftlint <<'STUB'
#!/bin/bash
set -eo pipefail
printf 'swiftlint %s\n' "$*" >>"$(dirname "$0")/calls.log"
case "${1:-}" in
  version | --version)
    printf '0.62.0\n'
    exit 0
    ;;
esac
printf 'Done linting! Found 0 violations, 0 serious in 0 files.\n'
STUB

  cat >bin/swift <<'STUB'
#!/bin/bash
set -eo pipefail
printf 'swift %s\n' "$*" >>"$(dirname "$0")/calls.log"
case "${1:-}" in
  --version)
    printf 'swift-driver version: 1.127.8 Apple Swift version 6.2 (swiftlang-6.2.0.19.9)\nTarget: arm64-apple-macosx26.0\n'
    exit 0
    ;;
esac
exit 0
STUB

  chmod +x bin/xcodebuild bin/xcodegen bin/swiftlint bin/swift
}
