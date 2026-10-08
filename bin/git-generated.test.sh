#!/bin/bash
#
# git-generated.test.sh
#
# Pins bin/git-generated against a real repository in a temp dir: which
# patterns it reads out of .gitattributes, the managed block it writes into
# $GIT_DIR/info/attributes, and what git then does with a diff. The last part
# is the contract -- a block in the right file that git does not honour hides
# nothing -- so it is asserted on `git diff` itself.
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

GG="$(cd "$(dirname "$0")" && pwd -P)/git-generated"
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap '/bin/rm -rf "$TMP"' EXIT

fails=0
t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# The caller's global config is not the subject: an external diff driver, as
# this repo's own .gitconfig sets, would change what `git diff` prints.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
repo="$TMP/repo"
git init -q "$repo"
cd "$repo" || exit 1
git config user.email t@e
git config user.name t
cat >.gitattributes <<'EOF'
# a comment naming linguist-generated must not count
gen/*.js linguist-generated
api.pb.go linguist-generated=true
keep.js linguist-generated=false
hand.js -linguist-generated
EOF
mkdir -p gen
for f in gen/out.js api.pb.go keep.js hand.js; do printf 'one\n' >"$f"; done
git add -A
git commit -qm init
for f in gen/out.js api.pb.go keep.js hand.js; do printf 'two\n' >>"$f"; done
attr="$(git rev-parse --git-path info/attributes)"
mkdir -p "$(dirname "$attr")"
printf 'mine.txt text\n' >"$attr" # a line of the user's own, outside the block

out=$("$GG" 2>&1)
t "hide exits 0 and reports the count" "git-generated: hidden 2 pattern(s) via $attr" "$out"
t "the managed block holds exactly the generated patterns, as -diff" \
  "$(printf '%s\n' '# >>> git-generated managed (do not edit) >>>' 'gen/*.js -diff' 'api.pb.go -diff' '# <<< git-generated managed <<<')" \
  "$(sed -n '/^# >>> git-generated/,/^# <<< git-generated/p' "$attr")"
t "the user's own line outside the block survives" "1" "$(grep -cx 'mine.txt text' "$attr")"
# What the block is for: git now treats those paths as binary.
t "a generated file's diff collapses to one line" "1" \
  "$(git diff -- gen/out.js | grep -c '^Binary files .* differ$')"
t "an =false entry is not hidden" "1" "$(git diff -- keep.js | grep -c '^+two$')"
t "a -linguist-generated entry is not hidden" "1" "$(git diff -- hand.js | grep -c '^+two$')"

# Idempotent: a second hide replaces its own block rather than appending one.
"$GG" >/dev/null 2>&1
t "a second hide leaves one block" "1" "$(grep -c '^# >>> git-generated' "$attr")"

out=$("$GG" status 2>&1)
t "status says hidden" "1" "$(printf '%s\n' "$out" | grep -c '^state: HIDDEN')"

"$GG" show >/dev/null 2>&1
t "show removes only the block" "mine.txt text" "$(cat "$attr")"
t "after which the diff is back" "1" "$(git diff -- gen/out.js | grep -c '^+two$')"

out=$("$GG" bogus 2>&1)
rc=$?
t "an unknown command exits 1" "1" "$rc"
cd "$TMP" || exit 1
out=$("$GG" 2>&1)
t "outside a work tree it says so" "1" "$(printf '%s\n' "$out" | grep -c 'not inside a git work tree')"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
