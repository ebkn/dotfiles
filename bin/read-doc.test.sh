#!/bin/bash
#
# read-doc.test.sh
#
# The contract pinned here is read-doc's image pass, the one part of it that is
# a security boundary: an <img> is inlined as a data: URI only when the file it
# names really lives inside the document's own directory tree, and only for a
# document named as a local path. Anything else is left as written, and a
# refusal says so on stderr. Inlining a file from outside the tree would put it,
# base64-encoded, in a page whose 'unsafe-inline' gap lets a smuggled script
# carry it off (bin/read-doc.md, "Images").
#
# pandoc is stubbed with cat, so the document's own raw <img> markup is the
# "rendered" HTML the second pass works on. That is deliberate: what pandoc
# makes of Markdown is pandoc's contract, and the typography checks in
# read-doc.md still need the real one. This suite needs only coreutils, so it
# runs on the CI runner, which has no pandoc.

set -u

DIR=$(mktemp -d)
SCRIPT="$(cd "$(dirname "$0")" && pwd)/read-doc"
fails=0
trap 'rm -rf "$DIR"' EXIT

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  [ -z "${2-}" ] || printf '     %s\n' "$2"
  fails=$((fails + 1))
}
has() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) fail "$1" "missing: $3" ;;
  esac
}
lacks() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) fail "$1" "present: $3" ;;
    *) ok "$1" ;;
  esac
}
b64() { base64 <"$1" | tr -d '\n'; }

mkdir -p "$DIR/stub"
printf '#!/bin/sh\nexec cat\n' >"$DIR/stub/pandoc"
chmod +x "$DIR/stub/pandoc"

# The document's tree, and a directory beside it holding what must never be
# inlined. The secret is named like a key, the way ~/.ssh/id_rsa would be.
doc="$DIR/doc"
outside="$DIR/outside"
mkdir -p "$doc/images" "$outside"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' >"$doc/a.svg"
printf 'PNGDATA-inside\n' >"$doc/images/b.png"
printf 'PNGDATA-outside\n' >"$outside/c.png"
printf 'SECRET-KEY-MATERIAL\n' >"$outside/id_rsa"
ln -s "$outside" "$doc/linked"
ln -s "$outside/id_rsa" "$doc/logo.png"
ln -s "$doc/images/b.png" "$doc/alias.png"

cat >"$doc/page.md" <<'MD'
<img src="a.svg">
<img src="images/b.png">
<img src="../outside/c.png">
<img src="linked/c.png">
<img src="logo.png">
<img src="alias.png">

A document about HTML may quote src="a.svg" outside any tag.
MD

run() { # <args...>; stdout to $DIR/out, stderr to $DIR/err
  PATH="$DIR/stub:$PATH" "$SCRIPT" --print "$@" >"$DIR/out" 2>"$DIR/err"
}

# --- a document named as a local path ---------------------------------------
if run "$doc/page.md"; then
  ok "--print exits 0"
else
  fail "--print exits 0" "$(cat "$DIR/err")"
fi
out=$(cat "$DIR/out")
err=$(cat "$DIR/err")

has "an image beside the document is inlined with its MIME type" \
  "$out" "src=\"data:image/svg+xml;base64,$(b64 "$doc/a.svg")\""
has "an image in a subdirectory of the document is inlined" \
  "$out" "src=\"data:image/png;base64,$(b64 "$doc/images/b.png")\""
# images/b.png and alias.png both become this URI, so two lines carry it.
n=$(grep -cF "src=\"data:image/png;base64,$(b64 "$doc/images/b.png")\"" "$DIR/out")
if [ "$n" -eq 2 ]; then
  ok "a symlink to an image inside the tree is inlined as that image"
else
  fail "a symlink to an image inside the tree is inlined as that image" "lines with b.png's URI: $n, want 2"
fi

has "an image a directory up is left as written" "$out" '<img src="../outside/c.png">'
has "and the refusal is said on stderr" "$err" "refusing to inline ../outside/c.png"
lacks "and its bytes appear nowhere" "$out" "$(b64 "$outside/c.png")"

has "an image through a symlinked directory is left as written" "$out" '<img src="linked/c.png">'
has "and that refusal is said on stderr" "$err" "refusing to inline linked/c.png"

has "a symlinked file pointing outside the tree is left as written" "$out" '<img src="logo.png">'
has "and that refusal is said on stderr" "$err" "refusing to inline logo.png"
lacks "and the file it points at appears nowhere" "$out" "$(b64 "$outside/id_rsa")"

has "a src quoted outside an <img> is left as written" "$out" 'may quote src="a.svg" outside'

# --- stdin: no neighbours to resolve -----------------------------------------
# Run from inside the tree, so a relative lookup would find a.svg if stdin were
# (wrongly) resolved against the working directory.
if (cd "$doc" && PATH="$DIR/stub:$PATH" "$SCRIPT" --print <page.md >"$DIR/out" 2>"$DIR/err"); then
  ok "--print from stdin exits 0"
else
  fail "--print from stdin exits 0" "$(cat "$DIR/err")"
fi
out=$(cat "$DIR/out")
has "a document from stdin keeps its image reference as written" "$out" '<img src="a.svg">'
lacks "and nothing from stdin is inlined" "$out" "src=\"data:"

# --- HOST:FILE: a pulled document's neighbours never crossed the wire ---------
# ssh runs the remote command here, so the fetch reads the real page.md. The
# fetched copy lands in $TMPDIR, so an a.svg is planted there: resolving the
# pulled document's references against its temp path is the failure to catch.
printf '#!/bin/sh\nshift\nexec sh -c "$*"\n' >"$DIR/stub/ssh"
chmod +x "$DIR/stub/ssh"
mkdir -p "$DIR/tmp"
cp "$doc/a.svg" "$DIR/tmp/a.svg"
if TMPDIR="$DIR/tmp" PATH="$DIR/stub:$PATH" "$SCRIPT" --print "somehost:$doc/page.md" >"$DIR/out" 2>"$DIR/err"; then
  ok "--print of HOST:FILE exits 0"
else
  fail "--print of HOST:FILE exits 0" "$(cat "$DIR/err")"
fi
out=$(cat "$DIR/out")
has "a pulled document keeps its image reference as written" "$out" '<img src="a.svg">'
lacks "and nothing from a pulled document is inlined" "$out" "src=\"data:"

# --- what a local document's own images still cannot be ---------------------
printf 'BMPDATA\n' >"$doc/d.bmp"
printf '<img src="d.bmp">\n<img src="a.svg">\n' >"$doc/limits.md"
READ_DOC_IMAGE_MAX_BYTES=1 run "$doc/limits.md"
out=$(cat "$DIR/out")
err=$(cat "$DIR/err")
has "an unknown image type is left as written" "$out" '<img src="d.bmp">'
has "and the refusal names it on stderr" "$err" "not an inlinable image type: d.bmp"
has "an image over READ_DOC_IMAGE_MAX_BYTES is left as written" "$out" '<img src="a.svg">'
has "and the refusal names the cap on stderr" "$err" "over the 1-byte inlining cap"

if [ "$fails" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$fails failure(s)"
  exit 1
fi
