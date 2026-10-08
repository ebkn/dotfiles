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
# wherever it is missing. It is not on the CI runner, so this runs locally
# (bin/ci-enrollment.test.sh lists it, with that reason).
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
# The directory was resolved before the check, the file was not: a symlink
# sitting INSIDE the tree and pointing out of it passed the check and was read.
t "a symlink inside the tree pointing out of it is refused too" "1" \
  "$(count 'refusing to inline img/link.gif' "$TMP/b.err")"
t "and nothing of the outside file reaches the page" "0" \
  "$(count "$(printf 'GIF89a-secret' | base64 | tr -d '\n')" "$TMP/b.html")"

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
