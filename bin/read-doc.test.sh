#!/bin/bash
#
# read-doc.test.sh
#
# Pins the half of bin/read-doc that has to hold for UNTRUSTED input, which
# read-doc.md says every failure of is silent: the page loads nothing, an image
# is inlined only from the document's own directory tree, `$` is text, and the
# ssh forward mode refuses rather than corrupts. The typesetting itself -- the
# reason the script exists -- stays a thing to look at in a browser.
#
# Everything goes through --print, which writes exactly the HTML the browser
# would get, so nothing is opened. pandoc is REQUIRED and its absence fails the
# run: a suite that skipped without it would be a permanently green check
# wherever it is missing. The runner has none, so CI installs a pinned one for
# this suite (see read-doc.md, "Testing").
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RD="$ROOT/bin/read-doc"
command -v pandoc >/dev/null || {
  echo "read-doc.test.sh: pandoc is required (brew install pandoc)" >&2
  exit 1
}

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
count() { grep -c -- "$1" "$2" || true; } # count <fixed-ish pattern> <file>

# --- the page loads nothing -------------------------------------------------------

doc="$TMP/doc"
mkdir -p "$doc/img" "$TMP/outside"
cat >"$doc/a.md" <<'EOF'
# Title

Set $PATH and ${VAR}, and $x$ is not maths.

<img src="https://example.com/track.png">
EOF
env -u SSH_CONNECTION "$RD" --print "$doc/a.md" >"$TMP/a.html" 2>"$TMP/a.err"
t "--print exits 0" "0" "$?"
t "the page carries exactly one Content-Security-Policy" "1" \
  "$(count 'http-equiv="Content-Security-Policy"' "$TMP/a.html")"
t "whose default is to load nothing" "1" "$(count "content=\"default-src 'none'; img-src data:" "$TMP/a.html")"
t "and no stylesheet is linked rather than inlined" "0" "$(count '<link' "$TMP/a.html")"
# The theme arrives inlined through header-includes; pandoc's own page CSS is
# dropped (an empty document-css), or its 36em measure overrides ours.
t "the theme's stylesheet is inlined" "yes" "$(grep -q -- '--font-body' "$TMP/a.html" && echo yes || echo no)"
t "pandoc's default page styling is not" "0" "$(count 'max-width: 36em' "$TMP/a.html")"
# $ opens no maths: in documents about software, ${VAR} and $PATH are far
# commoner than LaTeX, and a mismatched pair swallows the text between.
# shellcheck disable=SC2016 # the dollars are the literal text under test
t "\$PATH and \${VAR} stay text" "yes" \
  "$(grep -qF 'Set $PATH and ${VAR}, and $x$ is not maths.' "$TMP/a.html" && echo yes || echo no)"
t "a remote image is left as a URL for the CSP to refuse, not fetched or inlined" "1" \
  "$(count 'src="https://example.com/track.png"' "$TMP/a.html")"

# --- images: inlined from the document's own tree only ------------------------
# A script the document smuggles in can carry out whatever is in the DOM, so an
# image path must not be able to reach anything that is not already beside the
# document -- ../../.ssh/id_rsa least of all.
printf 'GIF89a-beside' >"$doc/img/ok.gif"
printf 'GIF89a-secret' >"$TMP/outside/secret.gif"
ln -s "$TMP/outside/secret.gif" "$doc/img/link.gif"
cat >"$doc/b.md" <<'EOF'
![ok](img/ok.gif)

![up](../outside/secret.gif)

![link](img/link.gif)
EOF
env -u SSH_CONNECTION "$RD" --print "$doc/b.md" >"$TMP/b.html" 2>"$TMP/b.err"
t "an image beside the document is inlined as a data: URI" "1" \
  "$(count "src=\"data:image/gif;base64,$(printf 'GIF89a-beside' | base64 | tr -d '\n')\"" "$TMP/b.html")"
t "a ../ path out of the document's tree is refused" "1" \
  "$(count 'refusing to inline ../outside/secret.gif' "$TMP/b.err")"
# Matched on the src alone: pandoc adds alt= to a Markdown image.
t "and its reference is left as written" "1" "$(count 'src="../outside/secret.gif"' "$TMP/b.html")"
# The directory was resolved before the check, the file was not: a symlink
# sitting INSIDE the tree and pointing out of it passed the check and was read.
t "a symlink inside the tree pointing out of it is refused too" "1" \
  "$(count 'refusing to inline img/link.gif' "$TMP/b.err")"
t "and that reference is left as written" "1" "$(count 'src="img/link.gif"' "$TMP/b.html")"
t "and nothing of the outside file reaches the page" "0" \
  "$(count "$(printf 'GIF89a-secret' | base64 | tr -d '\n')" "$TMP/b.html")"

# The other edges of the same pass, in raw <img> markup, which pandoc passes
# through as written. A resolution too eager refuses legitimate images; one too
# loose follows a symlinked directory out; a regex too loose rewrites a src= the
# document only quotes.
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' >"$doc/a.svg"
ln -s "$doc/img/ok.gif" "$doc/alias.gif"
ln -s "$TMP/outside" "$doc/linked"
printf 'BMPDATA\n' >"$doc/d.bmp"
cat >"$doc/c.md" <<'EOF'
<img src="a.svg">

<img src="alias.gif">

<img src="linked/secret.gif">

<img src="d.bmp">

A document about HTML may quote src="a.svg" outside any tag.
EOF
env -u SSH_CONNECTION "$RD" --print "$doc/c.md" >"$TMP/c.html" 2>"$TMP/c.err"
t "an image is inlined with its own MIME type" "1" \
  "$(count "src=\"data:image/svg+xml;base64,$(base64 <"$doc/a.svg" | tr -d '\n')\"" "$TMP/c.html")"
t "a symlink to an image inside the tree is inlined as that image" "1" \
  "$(count "src=\"data:image/gif;base64,$(printf 'GIF89a-beside' | base64 | tr -d '\n')\"" "$TMP/c.html")"
t "an image through a symlinked directory out of the tree is refused" "1" \
  "$(count 'refusing to inline linked/secret.gif' "$TMP/c.err")"
t "and is left as written" "1" "$(count '<img src="linked/secret.gif"' "$TMP/c.html")"
t "an unknown image type is refused, and named" "1" "$(count 'not an inlinable image type: d.bmp' "$TMP/c.err")"
t "and is left as written too" "1" "$(count '<img src="d.bmp"' "$TMP/c.html")"
t "a src= quoted outside an <img> is left as written" "1" \
  "$(count 'may quote src="a.svg" outside' "$TMP/c.html")"
printf '<img src="a.svg">\n' >"$doc/cap.md"
env -u SSH_CONNECTION READ_DOC_IMAGE_MAX_BYTES=1 "$RD" --print "$doc/cap.md" >"$TMP/cap.html" 2>"$TMP/cap.err"
t "an image over READ_DOC_IMAGE_MAX_BYTES is refused, naming the cap" "1" \
  "$(count 'over the 1-byte inlining cap' "$TMP/cap.err")"
t "and is not inlined" "0" "$(count 'src="data:' "$TMP/cap.html")"
t "but left as written" "1" "$(count '<img src="a.svg"' "$TMP/cap.html")"

# --- a document with no local tree inlines nothing -----------------------------
# Only a document this machine named on the command line has neighbours. A
# pulled one is read from a temp file, so a relative image would resolve into
# $TMPDIR; one on stdin, into whatever directory read-doc was run from. Both
# would hand the page files the document never shipped.
mkdir -p "$TMP/tmpd" "$TMP/cwd" "$TMP/stub"
printf 'GIF89a-neighbour' >"$TMP/tmpd/secret.gif"
printf 'GIF89a-neighbour' >"$TMP/cwd/secret.gif"
printf '![x](secret.gif)\n' >"$TMP/pulled.md"
cat >"$TMP/stub/ssh" <<STUB
#!/bin/sh
printf '%s\n' "\$@" >"$TMP/ssh.argv"
cat "$TMP/pulled.md"
STUB
chmod +x "$TMP/stub/ssh"
neighbour_b64=$(printf 'GIF89a-neighbour' | base64 | tr -d '\n')
env -u SSH_CONNECTION TMPDIR="$TMP/tmpd" PATH="$TMP/stub:$PATH" \
  "$RD" --print "farhost:notes/doc's.md" >"$TMP/pulled.html" 2>/dev/null
t "a pulled document is fetched with the path quoted for the remote shell" \
  "$(printf '%s\n' farhost "cat -- 'notes/doc'\\''s.md'")" "$(cat "$TMP/ssh.argv")"
t "and inlines nothing from beside its temp file" "0" "$(count "$neighbour_b64" "$TMP/pulled.html")"
(cd "$TMP/cwd" && env -u SSH_CONNECTION "$RD" --print <"$TMP/pulled.md" >"$TMP/stdin.html" 2>/dev/null)
t "a document on stdin inlines nothing from the current directory" "0" \
  "$(count "$neighbour_b64" "$TMP/stdin.html")"
t "while both still render" "2" "$(cat "$TMP/pulled.html" "$TMP/stdin.html" | grep -c '<img')"

# --- source files are fenced by their shebang ------------------------------------
# Extensionless executables are the norm in bin/, and matching on the name alone
# rendered them as prose.
printf '#!/bin/bash\necho hi\n' >"$doc/tool"
env -u SSH_CONNECTION "$RD" --print "$doc/tool" >"$TMP/tool.html" 2>/dev/null
t "an extensionless #!/bin/bash file is highlighted as bash" "1" \
  "$(count 'class="sourceCode bash"' "$TMP/tool.html")"

# --- forward mode refuses over its cap ---------------------------------------------
# Inside ssh the SOURCE is shipped to the terminal's machine; nothing documents a
# ceiling for that escape sequence, and one that truncated would corrupt in
# silence. Over the cap it must refuse, say what to run instead, and write
# nothing anywhere -- checked before any write to the terminal is attempted.
out=$(SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' READ_DOC_MAX_BYTES=10 "$RD" "$doc/a.md" 2>&1)
rc=$?
t "over the forwarding cap it exits 2" "2" "$rc"
t "and says it is over the cap" "1" "$(printf '%s\n' "$out" | grep -c 'over the 10-byte forwarding cap')"
t "and names the command to run from the terminal's machine" "1" \
  "$(printf '%s\n' "$out" | grep -c "read-doc .*:$doc/a.md")"

# --- usage ---------------------------------------------------------------------------
out=$("$RD" --print "$doc/a.md" "$doc/b.md" 2>&1)
t "two files are refused with exit 2" "2" "$?"
out=$("$RD" --bogus "$doc/a.md" 2>&1)
t "an unknown option is refused with exit 2" "2" "$?"
out=$("$RD" --print "$TMP/no-such-file.md" 2>&1)
t "an unreadable file is refused with exit 2" "2" "$?"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
