#!/bin/bash
#
# textlint-docs.test.sh
#
# Pins bin/textlint-docs' own decisions, not textlint's: when it installs the
# toolchain into its cache, that a failed install cannot be mistaken for a
# finished one, which ignore list it hands textlint, and that textlint's exit
# status is the script's. The ignore choice is the one that fails silently --
# a wrong list skips files with no message at all -- so it gets a case per
# branch.
#
# npm is a stub that "installs" a textlint which prints the arguments it got,
# so nothing is downloaded and no rule runs. Whether the RULES say the right
# thing about Japanese prose is checked by using the lint-docs skill, not here.
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

TD="$(cd "$(dirname "$0")" && pwd -P)/textlint-docs"
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

mkdir -p "$TMP/stub" "$TMP/proj"
# `npm --prefix <dir> ci ...`: logs the call; unless $NPM_FAIL is set, writes a
# textlint into <dir>/node_modules/.bin that prints one argument per line and
# exits with $TEXTLINT_EXIT.
cat >"$TMP/stub/npm" <<'STUB'
#!/bin/sh
echo "$*" >>"$NPM_LOG"
[ -n "${NPM_FAIL:-}" ] && exit 1
prefix=$2
mkdir -p "$prefix/node_modules/.bin"
cat >"$prefix/node_modules/.bin/textlint" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done
exit "${TEXTLINT_EXIT:-0}"
EOF
chmod +x "$prefix/node_modules/.bin/textlint"
STUB
chmod +x "$TMP/stub/npm"
export TEXTLINT_DOCS_HOME="$TMP/cache" NPM_LOG="$TMP/npm.log" PATH="$TMP/stub:$PATH"
td() { (cd "$TMP/proj" && "$TD" "$@" 2>"$TMP/err"); }

# --- the install ----------------------------------------------------------------
: >"$NPM_LOG"
out=$(td doc.md)
t "the first run installs the toolchain into the cache, scripts off" "1" \
  "$(grep -c "^--prefix $TMP/cache ci --ignore-scripts" "$NPM_LOG")"
t "and then runs textlint on the target" "doc.md" "$(printf '%s\n' "$out" | tail -n 1)"
: >"$NPM_LOG"
td doc.md >/dev/null
t "a second run does not reinstall" "" "$(cat "$NPM_LOG")"

# The rules and the dictionary are copied on EVERY run, not only on install, so
# an edit to textlint/ applies at once. Moved into the install branch, the
# cache would keep linting with the old rules until the next dependency bump,
# and the only symptom is fewer findings. A stale cached copy stands in for the
# edit, so the repo's own files are never touched.
for cfg in textlintrc.yml prh.yml textlintignore; do
  printf '# stale\n' >"$TMP/cache/$cfg"
done
td doc.md >/dev/null
for cfg in textlintrc.yml prh.yml textlintignore; do
  t "an edited $cfg reaches the cache without a reinstall" "same" \
    "$(cmp -s "$(dirname "$TD")/../textlint/$cfg" "$TMP/cache/$cfg" && echo same || echo stale)"
done

# The local rules travel the same way, as a directory replaced whole: copied
# over the old one, a rule deleted from textlint/rules/ would keep reporting
# from the cache, and the only symptom is findings nobody can find the source of.
mkdir -p "$TMP/cache/rules"
printf '// stale\n' >"$TMP/cache/rules/ja-no-redundant-phrase.js"
printf '// deleted upstream\n' >"$TMP/cache/rules/removed-rule.js"
td doc.md >/dev/null
t "an edited local rule reaches the cache without a reinstall" "same" \
  "$(cmp -s "$(dirname "$TD")/../textlint/rules/ja-no-redundant-phrase.js" \
    "$TMP/cache/rules/ja-no-redundant-phrase.js" && echo same || echo stale)"
t "a rule deleted from textlint/rules/ leaves the cache" "absent" \
  "$([ -e "$TMP/cache/rules/removed-rule.js" ] && echo present || echo absent)"

# A dependency change is what DOES reinstall: the cached manifests are compared
# with textlint/'s, so a bumped version is not silently ignored in favour of the
# toolchain already sitting in the cache.
for manifest in package.json package-lock.json; do
  printf '\n' >>"$TMP/cache/$manifest"
  : >"$NPM_LOG"
  td doc.md >/dev/null
  t "a changed $manifest reinstalls" "1" "$(grep -c ' ci ' "$NPM_LOG")"
done

# A failed install must not leave the manifest behind: the next run decides
# whether to install by comparing it, and would take a half-built tree for a
# finished one.
/bin/rm -rf "$TMP/cache"
NPM_FAIL=1 td doc.md >/dev/null
t "a failed install exits 2" "2" "$?"
t "and says so" "1" "$(grep -c 'install failed' "$TMP/err")"
t "and leaves no manifest in the cache" "absent" \
  "$([ -e "$TMP/cache/package.json" ] && echo present || echo absent)"
: >"$NPM_LOG"
td doc.md >/dev/null
t "so the next run installs again" "1" "$(grep -c ' ci ' "$NPM_LOG")"

# --- the ignore list, one case per branch -----------------------------------------
# The bundled list is a fallback. A project's own .textlintignore, or an explicit
# --ignore-path, states what IT wants excluded, and passing ours as well would
# silently override that: the bundled one drops .claude/ and CLAUDE.md, which in
# a project that authors them are the documents most worth checking.
args=$(td doc.md)
t "with no project ignore file, the bundled one is passed" "$TMP/cache/textlintignore" \
  "$(printf '%s\n' "$args" | grep -A1 -x -- '--ignore-path' | tail -n 1)"
t "with the config from the cache" "$TMP/cache/textlintrc.yml" \
  "$(printf '%s\n' "$args" | grep -A1 -x -- '--config' | tail -n 1)"
# The local rules are not packages, so without --rulesdir they do not exist and
# textlint says nothing about it: their findings just never appear.
t "with the local rules from the cache" "$TMP/cache/rules" \
  "$(printf '%s\n' "$args" | grep -A1 -x -- '--rulesdir' | tail -n 1)"
printf 'vendor/\n' >"$TMP/proj/.textlintignore"
t "the local rules are passed with a project .textlintignore too" "1" \
  "$(td doc.md | grep -c -x -- '--rulesdir')"
/bin/rm -f "$TMP/proj/.textlintignore"
printf 'vendor/\n' >"$TMP/proj/.textlintignore"
t "a project .textlintignore wins: the bundled one is not passed" "0" \
  "$(td doc.md | grep -c -- '--ignore-path')"
/bin/rm -f "$TMP/proj/.textlintignore"
args=$(td --ignore-path=mine doc.md)
t "an explicit --ignore-path=... wins" "--ignore-path=mine" "$(printf '%s\n' "$args" | grep -- '--ignore-path')"
args=$(td --ignore-path mine doc.md)
t "and so does --ignore-path <file>" "1" "$(printf '%s\n' "$args" | grep -c -- '--ignore-path')"

# A local rule named as a key in textlintrc.yml cannot be resolved as a
# package, and textlint then drops every rule in the file without a word --
# measured, 11 findings became 1. Checked statically, since the stub textlint
# here loads no config.
for rule in "$(dirname "$TD")"/../textlint/rules/*.js; do
  name=$(basename "$rule" .js)
  t "textlintrc.yml does not name the local rule $name" "0" \
    "$(grep -cE "^[[:space:]]+\"?$name\"?:" "$(dirname "$TD")/../textlint/textlintrc.yml")"
done

# --- pass-through ------------------------------------------------------------------
TEXTLINT_EXIT=1 td doc.md >/dev/null
t "textlint's exit status is the script's" "1" "$?"
t "flags reach textlint as given" "--fix" "$(td --fix doc.md | grep -x -- '--fix')"

td >/dev/null
t "no target is a usage error, exit 2" "2" "$?"
t "with the usage on stderr" "1" "$(grep -c '^usage: textlint-docs' "$TMP/err")"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
