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
# would get, so nothing is opened; forward mode writes to READ_DOC_TTY, so
# nothing reaches the real terminal either. pandoc is REQUIRED and its absence fails the
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
# The whole value, closing quote included: a prefix match still passed with
# `img-src data: https:` (the tracking image above would load) or a trailing
# `connect-src *`.
t "whose policy is exactly: load nothing but data: images and our own inline code" "1" \
  "$(count "content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'\"" "$TMP/a.html")"
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

# YAML front matter is the document's to write, and pandoc reads it as template
# variables: `css:` becomes a <link> placed BEFORE the CSP <meta>, which a CSP
# delivered by <meta> cannot reach, and `title:` brings back the <h1> that
# pagetitle exists to avoid. gfm reads only a block at the very top.
cat >"$doc/fm.md" <<'MD'
---
css: https://example.com/x.css
title: Injected
---

# Real heading
MD
env -u SSH_CONNECTION "$RD" --print "$doc/fm.md" >"$TMP/fm.html" 2>"$TMP/fm.err"
t "front matter: --print exits 0" "0" "$?"
t "front matter links no stylesheet" "0" "$(count '<link' "$TMP/fm.html")"
t "and sets no title heading" "0" "$(count 'class="title"' "$TMP/fm.html")"
# Still readable, since SKILL.md and most notes start with one: shown as YAML.
t "the leading block is shown as YAML source" "1" \
  "$(count '<code class="sourceCode yaml">' "$TMP/fm.html")"
# Each value once, which is inside that block: `Injected` alone would also be
# found in the <h1 class="title"> this exists to prevent.
t "with every line of it kept: the css value" "1" "$(count 'example.com/x.css' "$TMP/fm.html")"
t "and the title value" "1" "$(count 'Injected' "$TMP/fm.html")"
# And the document after it. Every check above holds for a filter that stops
# at the closing line, which leaves nothing but the front matter on the page.
t "the body after the block is still rendered" "1" "$(count 'Real heading</h1>' "$TMP/fm.html")"
# Nor does the closing --- leak through as a rule of its own.
t "and the closing line is not left behind as a rule" "0" "$(count '<hr' "$TMP/fm.html")"

# The other ways in: stdin (`ssh host cat doc.md | read-doc`), and YAML's own
# `...` as the closing line.
printf -- '---\ntitle: Piped\n...\n\n# Real\n' |
  env -u SSH_CONNECTION "$RD" --print >"$TMP/fm-stdin.html" 2>/dev/null
t "from stdin, a block closed by ... is shown as YAML too" "1" \
  "$(count '<code class="sourceCode yaml">' "$TMP/fm-stdin.html")"
t "and sets no title heading" "0" "$(count 'class="title"' "$TMP/fm-stdin.html")"
t "with the body after it" "1" "$(count 'Real</h1>' "$TMP/fm-stdin.html")"

# A block that never closes is not front matter. Every line must still be there:
# the filter holds them back while it waits for the closing line.
printf -- '---\nfirst line\nlast line\n' >"$doc/open.md"
env -u SSH_CONNECTION "$RD" --print "$doc/open.md" >"$TMP/open.html" 2>/dev/null
t "an unclosed block is not fenced" "0" "$(count '<code class="sourceCode yaml">' "$TMP/open.html")"
t "and loses none of its lines" "yes" \
  "$(grep -q 'first line' "$TMP/open.html" && grep -q 'last line' "$TMP/open.html" && echo yes || echo no)"

# The reader spec on its own. CRLF line endings get past the filter, whose
# `---` match is exact, so here nothing but the disabled yaml_metadata_block
# stands between the block and pandoc's template.
printf -- '---\r\ncss: https://example.com/x.css\r\ntitle: Injected\r\n---\r\n\r\n# Real\r\n' >"$doc/crlf.md"
env -u SSH_CONNECTION "$RD" --print "$doc/crlf.md" >"$TMP/crlf.html" 2>/dev/null
t "precondition: a CRLF block is not fenced, so the filter is not what stops it" "0" \
  "$(count '<code class="sourceCode yaml">' "$TMP/crlf.html")"
t "a CRLF block links no stylesheet" "0" "$(count '<link' "$TMP/crlf.html")"
t "and sets no title heading" "0" "$(count 'class="title"' "$TMP/crlf.html")"

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

# pandoc's html5 writer wraps at 72 columns, and a long alt splits the tag:
# `<img src="..."` on one line and `alt="..." />` on the next. The collection
# flattens newlines first; without that, only images with a short alt and path
# were inlined, and every long one silently was not.
printf '![a diagram of the reconnect sequence between the client and the remote host, with every retry](img/ok.gif)\n' \
  >"$doc/wrap.md"
env -u SSH_CONNECTION "$RD" --print "$doc/wrap.md" >"$TMP/wrap.html" 2>/dev/null
# The precondition, so this case cannot quietly stop testing the wrap if
# pandoc's output changes.
t "pandoc does split this <img> across lines" "0" "$(count '<img .*/>' "$TMP/wrap.html")"
t "and the split <img> is still inlined" "1" \
  "$(count "src=\"data:image/gif;base64,$(printf 'GIF89a-beside' | base64 | tr -d '\n')\"" "$TMP/wrap.html")"

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

# A leading ~ must reach the remote shell unquoted, or it looks for a directory
# literally named "~" there.
env -u SSH_CONNECTION TMPDIR="$TMP/tmpd" PATH="$TMP/stub:$PATH" \
  "$RD" --print "farhost:~/notes/a.md" >/dev/null 2>&1
t "a ~/ path keeps its tilde outside the quotes" \
  "$(printf '%s\n' farhost "cat -- ~/'notes/a.md'")" "$(cat "$TMP/ssh.argv")"

# A local file whose name looks like HOST:FILE is still a local file.
/bin/rm -f "$TMP/ssh.argv"
printf '# local, not pulled\n' >"$TMP/cwd/farhost:x.md"
(cd "$TMP/cwd" && env -u SSH_CONNECTION PATH="$TMP/stub:$PATH" \
  "$RD" --print "farhost:x.md" >"$TMP/colon.html" 2>/dev/null)
t "an existing local file named like HOST:FILE is read locally" "1" "$(count 'local, not pulled' "$TMP/colon.html")"
t "and ssh is never run" "absent" "$([ -e "$TMP/ssh.argv" ] && echo present || echo absent)"

# A failed fetch must stop there: carried on, it renders the empty temp file
# and exits 0 with a blank page.
mkdir -p "$TMP/stub-fail"
printf '#!/bin/sh\nexit 255\n' >"$TMP/stub-fail/ssh"
chmod +x "$TMP/stub-fail/ssh"
out=$(env -u SSH_CONNECTION TMPDIR="$TMP/tmpd" PATH="$TMP/stub-fail:$PATH" \
  "$RD" --print "farhost:notes/a.md" 2>"$TMP/fetch.err")
t "a failed fetch exits 2" "2" "$?"
t "and says what it could not fetch" "1" "$(count 'failed to fetch farhost:notes/a.md' "$TMP/fetch.err")"
t "and renders nothing" "" "$out"

# --- source files are fenced by their shebang ------------------------------------
# Extensionless executables are the norm in bin/, and matching on the name alone
# rendered them as prose.
printf '#!/bin/bash\necho hi\n' >"$doc/tool"
env -u SSH_CONNECTION "$RD" --print "$doc/tool" >"$TMP/tool.html" 2>/dev/null
t "an extensionless #!/bin/bash file is highlighted as bash" "1" \
  "$(count 'class="sourceCode bash"' "$TMP/tool.html")"
# The extension is the ordinary route, and `read-doc main.go` the usage line's
# own example. An unknown extension falls back to prose, deliberately: fencing
# a document hides it behind a scrollbar, which is worse than uncoloured code.
# The `#` line opens a line and follows a blank one, so read as prose it WOULD
# be a heading; a `// #` comment would not be, and the next check could not fail.
cat >"$doc/main.go" <<'EOF'
package main

var s = `

# not a heading
`
EOF
env -u SSH_CONNECTION "$RD" --print "$doc/main.go" >"$TMP/go.html" 2>/dev/null
t "a .go file is highlighted as go" "1" "$(count 'class="sourceCode go"' "$TMP/go.html")"
t "and its # is code, not a heading" "0" "$(count '<h1' "$TMP/go.html")"
printf '# A heading\n\nprose\n' >"$doc/notes.xyz"
env -u SSH_CONNECTION "$RD" --print "$doc/notes.xyz" >"$TMP/xyz.html" 2>/dev/null
t "an unknown extension is rendered as prose" "1" "$(count '<h1' "$TMP/xyz.html")"
# Matched on the element: the inlined stylesheet quotes class="sourceCode" in
# its comments.
t "and is not fenced" "0" "$(count '<pre class="sourceCode' "$TMP/xyz.html")"

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

# --- forward mode, under the cap -------------------------------------------------
# What wezterm.lua decodes is the whole contract of this half, and every way of
# breaking it is silent: a wrong payload, a missing depth or an ESC not doubled
# just means no page opens. READ_DOC_TTY stands in for /dev/tty, which from a
# real terminal would reach the real WezTerm.
#
# The expected bytes are spelt out rather than rebuilt the way read-doc builds
# them, so a mistake in that construction cannot be copied into the check. Each
# tmux layer strips one `ESC P tmux; ... ESC \` and halves the ESCs inside it.
printf '# Forwarded\n\nbody\n' >"$doc/fwd.md"
P=$(printf 'fwd.md\n# Forwarded\n\nbody' | base64 | tr -d '\n')
printf '\033]1337;SetUserVar=read_doc=%s\007' "$P" >"$TMP/fwd.expected"
# \134 is the backslash of the `ESC \` terminator.
printf '\033Ptmux;\033\033]1337;SetUserVar=read_doc=%s\007\033\134' "$P" >>"$TMP/fwd.expected"
printf '\033Ptmux;\033\033Ptmux;\033\033\033\033]1337;SetUserVar=read_doc=%s\007\033\033\134\033\134' \
  "$P" >>"$TMP/fwd.expected"

SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' READ_DOC_TTY="$TMP/fwd.tty" \
  "$RD" "$doc/fwd.md" >"$TMP/fwd.out" 2>"$TMP/fwd.err"
t "forwarding exits 0" "0" "$?"
t "the terminal gets depths 0, 1 and 2, byte for byte" "same" \
  "$(cmp -s "$TMP/fwd.expected" "$TMP/fwd.tty" && echo same || echo differs)"
t "and the payload decodes to the name, then the source" \
  "$(printf 'fwd.md\n# Forwarded\n\nbody')" \
  "$(grep -ao 'SetUserVar=read_doc=[A-Za-z0-9+/=]*' "$TMP/fwd.tty" | head -1 |
    sed 's/^SetUserVar=read_doc=//' | base64 -d)"
t "nothing goes to stdout when the terminal can be written" "0" "$(wc -c <"$TMP/fwd.out" | tr -d ' ')"
t "stderr confirms what was sent" "read-doc: sent fwd.md to the terminal's machine" "$(cat "$TMP/fwd.err")"

# An earlier version tested -w first, which /dev/tty passes with no controlling
# terminal, and exited 0 having emitted nothing. Unwritable, it falls back to
# stdout -- the same bytes, so whatever reads that stream still gets them.
SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' READ_DOC_TTY="$TMP/no-such-dir/tty" \
  "$RD" "$doc/fwd.md" >"$TMP/fwd-fallback.out" 2>"$TMP/fwd-fallback.err"
t "with no writable terminal it still exits 0" "0" "$?"
t "and the same bytes go to stdout instead" "same" \
  "$(cmp -s "$TMP/fwd.expected" "$TMP/fwd-fallback.out" && echo same || echo differs)"
t "and the failed write leaves nothing on stderr but the confirmation" \
  "read-doc: sent fwd.md to the terminal's machine" "$(cat "$TMP/fwd-fallback.err")"

# --print is how a caller asks for HTML inside ssh; forwarding instead would
# hand it escape sequences where it expected a page.
SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' READ_DOC_TTY="$TMP/print.tty" \
  "$RD" --print "$doc/fwd.md" >"$TMP/print-ssh.html" 2>/dev/null
t "--print inside ssh renders instead of forwarding" "1" "$(count '<html' "$TMP/print-ssh.html")"
t "and writes nothing to the terminal" "absent" \
  "$([ -e "$TMP/print.tty" ] && echo present || echo absent)"

# --- local mode: the default, which opens a browser ---------------------------
# `open` is stubbed on PATH, so nothing is launched; it records what it was asked
# to open. The page is a file under $TMPDIR/read-doc, keyed on the document's
# absolute path so a re-render reuses one tab, and it goes through the image
# pass as well -- a separate call from --print's, which every other case uses.
mkdir -p "$TMP/open-stub" "$TMP/local-tmp"
cat >"$TMP/open-stub/open" <<STUB
#!/bin/sh
printf '%s\n' "\$@" >"$TMP/open.argv"
STUB
chmod +x "$TMP/open-stub/open"
local_rd() { env -u SSH_CONNECTION -u READ_DOC_BROWSER TMPDIR="$TMP/local-tmp" PATH="$TMP/open-stub:$PATH" "$RD" "$@"; }

local_rd "$doc/b.md" 2>"$TMP/local.err"
t "local mode exits 0" "0" "$?"
page=$(cat "$TMP/open.argv")
t "it opens one page under \$TMPDIR/read-doc, named for the document" "yes" \
  "$(printf '%s' "$page" | grep -qE "^$TMP/local-tmp/read-doc/[0-9a-f]{8}-b\.html$" && echo yes || echo no)"
t "and says where on stderr" "read-doc: file://$page" "$(cat "$TMP/local.err" | grep -v '^read-doc: refusing')"
t "the page it opens is the rendered document" "1" "$(count '<html' "$page")"
t "with its images inlined" "1" \
  "$(count "src=\"data:image/gif;base64,$(printf 'GIF89a-beside' | base64 | tr -d '\n')\"" "$page")"
# Cleared first, so the page compared is the one this run opened.
/bin/rm -f "$TMP/open.argv"
local_rd "$doc/b.md" 2>/dev/null
t "a re-render exits 0" "0" "$?"
t "a re-render of the same document opens the same page" "$page" "$(cat "$TMP/open.argv" 2>/dev/null)"
mkdir -p "$TMP/other"
/bin/cp "$doc/b.md" "$TMP/other/b.md"
local_rd "$TMP/other/b.md" 2>/dev/null
t "a same-named document elsewhere gets a page of its own" "different" \
  "$([ "$(cat "$TMP/open.argv")" != "$page" ] && echo different || echo same)"
env -u SSH_CONNECTION READ_DOC_BROWSER=Firefox TMPDIR="$TMP/local-tmp" PATH="$TMP/open-stub:$PATH" \
  "$RD" "$doc/b.md" 2>/dev/null
t "READ_DOC_BROWSER picks the browser" "$(printf '%s\n' -a Firefox "$page")" "$(cat "$TMP/open.argv")"

# --here is how to render on the far end of ssh on purpose.
/bin/rm -f "$TMP/open.argv"
env -u READ_DOC_BROWSER SSH_CONNECTION='10.0.0.1 1 10.0.0.2 22' READ_DOC_TTY="$TMP/here.tty" \
  TMPDIR="$TMP/local-tmp" PATH="$TMP/open-stub:$PATH" "$RD" --here "$doc/b.md" 2>/dev/null
t "--here inside ssh renders and opens locally" "$page" "$(cat "$TMP/open.argv" 2>/dev/null)"
t "and forwards nothing" "absent" "$([ -e "$TMP/here.tty" ] && echo present || echo absent)"

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
