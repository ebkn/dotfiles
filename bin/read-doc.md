# read-doc

Typeset a document as HTML and open it in the browser. Presentation assets live
in `read-doc/` (`style.css`, `after-body.html`).

## The point is the stylesheet, not the converter

A terminal is a grid of equal-size cells, so a glyph can only land at
`column * cell_width`. That is the model, not a missing feature, which is why
**no** pager (`bat`, `glow`, `mdcat`) can use a proportional face. Long-form
Japanese is much easier to read in one.

**Do not "simplify" this into a terminal pager**; that discards the entire reason
it exists. `read-doc/style.css`'s `:root { --font-body }` is the one knob worth
tuning.

## Why pandoc and not the 1000× smaller cmark-gfm

Syntax highlighting. cmark-gfm emits `<pre><code class="language-zsh">` and
stops, so colouring it means vendoring highlight.js into this repo — a minified
blob under version control costs more than the 266 MB pandoc binary saves.

pandoc highlights server-side via skylighting, so the colours are baked into the
markup and survive with scripting off.

## The page loads nothing

`read-doc/after-body.html` adds one **inline** script (`--include-after-body`)
for the code-block copy buttons and for giving external links `target="_blank"`,
and both degrade to a perfectly readable document if it never runs.

Links are retargeted in script rather than with a one-line
`<base target="_blank">` because `<base>` would also apply to `#fragment` links,
so a table-of-contents entry would open a second copy of the document instead of
scrolling inside this one.

## The input is untrusted

A document arrives here pulled over ssh or forwarded from a remote pane, so
pandoc runs under `--sandbox` (upstream's own advice for untrusted input) and the
page carries a `Content-Security-Policy` `<meta>`:

    default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'

Two consequences, both deliberate:

1. **`--sandbox` blocks `--embed-resources`, which is a *writer-side* fetch.**
   Being named on the command line does **not** exempt `--css` from it (verified:
   the stylesheet is left as a `<link>` and warned about), so `style.css` is read
   by the script and passed in as an inline `<style>` through `header-includes`,
   which the html5 template emits after `$styles.html()$` exactly where `--css`
   used to land. `--include-after-body` is read by the CLI itself and is
   unaffected.
2. **A document-relative image is inlined by the script, not fetched by pandoc**
   — `--sandbox` will not fetch it and `img-src data:` would refuse it anyway.
   So `read-doc` makes a second pass over the rendered HTML and rewrites each
   `<img src>` to a `data:` URI. See "Images" below for what that pass will and
   will not touch.

**The known gap worth stating:** `script-src 'unsafe-inline'` is required by
`after-body.html` and therefore also permits a script the *document* smuggled
through the gfm reader's raw-HTML passthrough. `default-src 'none'` stops that
script exfiltrating anything, but CSP has no directive here against navigating
the top level, so this buys silence, not immobility. Closing it means replacing
`'unsafe-inline'` with a sha256 hash of `after-body.html`'s script.

## The CSS trap that cost two failed attempts — specificity

pandoc puts `class="sourceCode"` on **both** the wrapper div and the `<pre>`, and
its surviving stylesheet says `.sourceCode { overflow: visible }` plus, in
`@media screen`, `div.sourceCode { overflow: auto }`.

A bare `pre { overflow-x: auto }` here is (0,0,1) and loses to (0,1,0) however
late it appears, silently — so `<pre>` was never the scroll container. The outer
div scrolled while the background and border sat on a `<pre>` only as wide as the
column, and a long line simply travelled out of the box.

**Every code-block selector must match the class too** (`pre, pre.sourceCode`).

Then `div.sourceCode` needs `margin: 0`, because its `margin: 1em` does not
collapse with the wrapper's (`overflow: auto` suppresses collapsing) and stacked
18px + 32.4px of dead space around every block.

Secondary but still true: `padding` belongs on `pre > code`, not the scrolling
`pre`, since `padding-right` on a scroll container is not part of its scrollable
overflow area — the inner element takes `width: max-content; min-width: 100%` so
its padding travels with the scroll.

## Four pandoc traps, all verified empirically

1. **`-V document-css=` must be empty, not the documented `false`.** The template
   guard is `$if(document-css)$` and tests for non-emptiness, so the string
   `false` reads as *true* and the default page CSS silently stays.
2. **The stylesheet must land after pandoc's own `<style>`**, which is what lets
   our rules win. The html5 template puts `$styles.html()$` before both
   `$for(css)$` and `$for(header-includes)$`, so the switch from `--css` to
   `header-includes` kept the order — a template that reordered them would break
   the theme with no error.
3. **`tex_math_dollars` and `tex_math_gfm` are on by default in the `gfm`
   reader**, so `${VAR}` and `$PATH` open inline maths and silently swallow the
   text between them. Both are disabled in the reader spec.
4. **`--metadata=title` also injects an `<h1 class="title">`** into the body,
   duplicating the document's own first heading, so `pagetitle` is used instead.

## Source files

Fenced before being handed to the same Markdown reader — one rendering path,
highlighting for free.

**Extensionless files are detected by shebang**, matching how `bin/lint-shell`
discovers its targets; matching on name alone renders `bin/relink` and friends as
prose, which is how this first went wrong.

Unknown extensions deliberately fall through to prose: rendering source without
colour is a milder failure than hiding a document behind a scrollbar.

## Images

`![](./images/a.svg)` is inlined as a `data:` URI by a second pass over the
rendered HTML, because neither pandoc nor the browser will go and fetch it (see
"The input is untrusted" above). Four rules, and why each one is there:

- **Only a document named as a local path.** stdin and `HOST:FILE` are skipped:
  a pulled document's neighbours never crossed the wire, and its source is a
  temp file by then, so `./images/a.svg` would be looked up in `$TMPDIR`.
- **Only inside the document's own directory tree**, resolved with `pwd -P`
  first so `..` and a symlinked directory are both settled before the test. This
  is not a filesystem limitation but a defence against the `unsafe-inline` gap
  above: a smuggled script cannot fetch, but it can navigate the top level, so
  embedding any path the document asks for would hand it `~/.ssh/id_rsa` as
  base64 in the DOM to carry out in a URL. Confined, the secret has to be
  sitting beside the document already. `../images/a.svg` is therefore refused —
  **out loud on stderr**, so it reads as "move it", not as "this is broken".
- **Only inside an `<img>` tag**, tracked across lines because the html5 writer
  wraps at 72 columns and routinely splits one in two. A bare search for the
  attribute would rewrite a `src="./a.svg"` that a document about HTML was
  merely quoting.
- **Only known image extensions** (svg, png, jpg, gif, webp, avif), under
  `READ_DOC_IMAGE_MAX_BYTES` (4 MiB). A wrong MIME renders as nothing with no
  message, so an unknown extension is left as a broken reference rather than
  guessed at.

The SVG stays inside an `<img>` rather than being spliced in as an `<svg>`
element: markup pasted into the DOM would bring its own scripts and its own ids,
and `<img>` renders SVG non-interactively, with scripting off.

## Forward mode: reading a document from inside an ssh session

Inside ssh, `open(1)` launches a browser on the far end where nobody is looking —
the bug this exists to fix, and one easy to inflict on yourself by accident,
since an agent session running over ssh hits it too.

So `read-doc` detects `$SSH_CONNECTION` and writes the document to the terminal
as `OSC 1337 SetUserVar=read_doc`, base64 of `<basename>\n<content>`; the
`read_doc` arm of `user-var-changed` in `wezterm.lua` writes it under
`$TMPDIR/read-doc-inbox/` and runs the **local** `read-doc` on it.

**The source crosses the wire, not the HTML.** That is what lets the remote need
no pandoc, and keeps `read-doc/style.css` on the receiving machine the single
source of truth rather than letting a stale remote checkout pick the typography.
The name travels with the body because it carries the extension, which drives
language detection and the title.

Three constraints, all verified:

1. **Every tmux between the emitter and WezTerm strips exactly one DCS
   passthrough wrapper, and the remote cannot know how many there are.** `$TMUX`
   reveals the local one, never the one next to the terminal (the normal case
   here is two: tmux on the remote *and* tmux beside WezTerm). Guessing wrong
   fails silently, so depths 0/1/2 are all emitted; exactly one survives, a
   wrapper one layer short is eaten by the last tmux, and one too deep reaches
   WezTerm as an unknown DCS and is ignored. Needs `allow-passthrough on`,
   already set.
2. **`/dev/tty` passes `[ -w ]` even with no controlling terminal** and then
   fails at write time with ENXIO — an earlier version exited 0 having emitted
   nothing. Attempt the write and fall back; and brace the redirect
   (`{ …; } 2>/dev/null`), because the "Device not configured" message comes from
   the redirect, not the command, so a bare `2>/dev/null` does not suppress it.
3. **Neither WezTerm nor tmux documents a maximum sequence length**, and tmux has
   a history of truncating long passthrough
   ([tmux#1502](https://github.com/tmux/tmux/issues/1502)), so the payload is
   capped (`READ_DOC_MAX_BYTES`, default 256 KiB) and refuses with the
   `read-doc HOST:FILE` command to run instead — an undocumented ceiling that
   corrupts quietly is worse than a refusal.

**Trust boundary worth stating:** anything that can write to a pane, including
`cat` on a file from elsewhere, can now cause a file write and a browser launch
on the machine you are sitting at. Same class as the OSC 52 clipboard writes tmux
already forwards, but a larger action, so the handler strips `/` and C0 from the
name (not an allow-list of word characters — that would mangle every Japanese
filename) and caps the body independently of the sender.

## Testing

Verified by running it, like `textlint-docs`. `read-doc --print <file>` writes the
HTML to stdout without opening a browser, which is the form to check.

**Assert on the output, not on the exit status** — every failure mode here is
silent:

- pandoc's default page CSS must be **absent** (`max-width: 36em`);
- `read-doc/style.css` must be **present** (`--font-body`);
- external refs must be zero;
- `class="title"` must be zero;
- a source file must produce `class="sourceCode <lang>"`;
- the CSP `<meta>` must be present exactly once;
- a document beside an image must produce `src="data:image/`, and no `src="./`;
- one referring to an image a directory up must say so on stderr and leave the
  reference as written.

A `data:` URI that decodes is still not a picture. Confirm the last two by
measurement, with the headless recipe below and
`[].map.call(document.images, i => i.naturalWidth)` — a wrong MIME, a truncated
payload and a stray newline in the base64 all pass a `grep` and all come back
`0`.

`--sandbox` failing silently looks exactly like success at the exit-status level,
so **check the stylesheet, not the flag**: a rendered page containing
`--font-body` proves `header-includes` carried it, and one containing `<link`
proves it did not.

Check stderr too: pandoc reports a mis-parsed document as a `[WARNING]` and still
exits 0.

**Do not use this file as the test input** — a document that quotes the marker
strings inflates every count, which is exactly how the first version of this
paragraph broke its own instructions.

### Forward mode, without a terminal

From an ssh session, `read-doc FILE` with stdout redirected to a file must emit
three `SetUserVar=read_doc` copies (depths 0/1/2), with stderr carrying only the
`sent <name>` confirmation, and

    grep -ao 'SetUserVar=read_doc=[A-Za-z0-9+/=]*' | head -1 |
      sed 's/^SetUserVar=read_doc=//' | base64 -d

must reproduce `<basename>` then the file verbatim. `od -c` confirms the nesting
— depth 2 is `ESC P tmux ; ESC ESC P tmux ; ESC ESC ESC ESC ]`.

The receiving half needs a real WezTerm and cannot be checked this way.

### Layout, by measurement rather than by eye

Append a script that writes `getComputedStyle` / `scrollWidth` /
`getBoundingClientRect` results into the DOM, then

    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
      --headless --disable-gpu --virtual-time-budget=3000 --dump-dom file://…

and grep them out. That is how the code-block bug above was finally pinned after
two attempts at reasoning about it: the decisive numbers were a computed
`overflow-x: visible` on an element the stylesheet plainly told to scroll, and,
after setting `scrollLeft` to the end,
`code.getBoundingClientRect().right - pre.…right` staying at `-1` instead of
going positive.
