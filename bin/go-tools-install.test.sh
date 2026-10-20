#!/bin/bash
#
# go-tools-install.test.sh -- pins what bin/go-tools-install hands `go
# install`: every package at its line's version and nothing at @latest, lines
# left out by --except, and a failed install neither stopping the rest nor
# passing as success. go is a stub that logs its arguments and fails for the
# packages named in $GO_FAIL. See bin/go-cooldown.md.
#
# Written for bash 3.2 (/bin/bash on macOS), as the tool is.
set -uo pipefail
. "$(dirname "$0")/test-lib.sh" || exit 2

TOOL="$(cd "$(dirname "$0")" && pwd -P)/go-tools-install"
test_tmpdir

mkdir -p "$TEST_TMPDIR/stub"
cat >"$TEST_TMPDIR/stub/go" <<'STUB'
#!/bin/sh
echo "$*" >>"$GO_LOG"
case " ${GO_FAIL:-} " in *" ${2%@*} "*) exit 1 ;; esac
exit 0
STUB
chmod +x "$TEST_TMPDIR/stub/go"
export GO_LOG="$TEST_TMPDIR/go.log" PATH="$TEST_TMPDIR/stub:$PATH"

PINS="$TEST_TMPDIR/go-tools.txt"
cat >"$PINS" <<'EOF'
# <module> <version> <github repo> <branch> <package>...

example.com/one v1.0.0 a/one main example.com/one/...
example.com/two v1.3.1 b/two release-branch/{X.Y} example.com/two/cmd/x example.com/two/cmd/y
EOF

: >"$GO_LOG"
assert_status "installs every line" 0 "$TOOL" "$PINS"
assert_eq "  ... each package at its line's version, in order" \
  "install example.com/one/...@v1.0.0
install example.com/two/cmd/x@v1.3.1
install example.com/two/cmd/y@v1.3.1" "$(cat "$GO_LOG")"

: >"$GO_LOG"
assert_status "--except leaves a module out" 0 "$TOOL" --except example.com/two "$PINS"
assert_eq "  ... and only that one" "install example.com/one/...@v1.0.0" "$(cat "$GO_LOG")"

: >"$GO_LOG"
out=$(GO_FAIL=example.com/two/cmd/x "$TOOL" "$PINS" 2>&1)
st=$?
assert_eq "a failed install fails the run" 1 "$st"
assert_contains "  ... naming the package" "$out" "go-tools-install: example.com/two/cmd/x@v1.3.1 failed"
assert_contains "  ... after installing the rest" "$(cat "$GO_LOG")" "install example.com/two/cmd/y@v1.3.1"

printf 'example.com/one v1.0.0 a/one\n' >"$TEST_TMPDIR/short.txt"
: >"$GO_LOG"
out=$("$TOOL" "$TEST_TMPDIR/short.txt" 2>&1)
st=$?
assert_eq "a line it cannot read fails the run" 1 "$st"
assert_contains "  ... naming it" "$out" "short.txt line 1"
assert_eq "  ... before installing anything" "" "$(cat "$GO_LOG")"

# As update-all runs it: through its link in ~/.local/bin, with no file named,
# so the default must be found beside the link's target, not the link.
mkdir -p "$TEST_TMPDIR/home-bin"
ln -s "$TOOL" "$TEST_TMPDIR/home-bin/go-tools-install"
: >"$GO_LOG"
assert_status "run through a link, it finds bin/go-tools.txt" 0 "$TEST_TMPDIR/home-bin/go-tools-install"
assert_contains "  ... and installs from it" "$(cat "$GO_LOG")" "install golang.org/x/tools/...@v"

assert_status "a missing file fails the run" 1 "$TOOL" "$TEST_TMPDIR/none.txt"
assert_status "a usage error exits 2" 2 "$TOOL" --except

test_summary
