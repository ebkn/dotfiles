# textlint-docs

Run the `textlint/` rules on any repo. Symlinked to `~/.local/bin`; backs the
`lint-docs` skill.

## The rules are the single source of truth, and they are materialized

`textlint/` holds the rule set, the prh dictionary and the exact package
versions. This wrapper **materializes** config *and* `node_modules` into
`${XDG_CACHE_HOME:-~/.cache}/textlint-docs` and runs from there.

Both halves of that matter:

- **Config and modules must share a directory**, because textlint resolves rule
  packages and prh's `rulePaths` relative to the config file, so splitting them
  breaks resolution from an arbitrary cwd.
- **That directory must sit outside this repo.** `bin/` is symlinked into
  `~/.local/bin` and skill dirs into three agent dirs, so an `npm install` inside
  the checkout would write thousands of untracked files through those links.

The payoff is that the linted project gets no `.textlintrc`, no devDependency and
no `node_modules`, so this runs against repos you do not own or whose toolchain is
not JavaScript.

**Do not "simplify" it by depending on a globally installed `textlint`**: the
global install is per-node-version under volta, so a `volta` node bump silently
removes it.

## The dictionary is split for portability

`prh.yml` has a universal section and a project-dependent one (katakana
long-vowel notation, where the `expected` side is just one repo's measured
majority). The skill measures the target repo before applying the latter, and
that split is the whole reason the dictionary is portable.

Bump versions in `textlint/package.json`, then regenerate the lockfile with
`npm install --prefix textlint --package-lock-only`.

## The rules do not detect language

`sentence-length` and `max-comma` fire on English sentences too, so narrowing the
target set to Japanese files is the **caller's** job. The skill does it by
counting `。` density (measured here: Japanese files 34–87%, all 28 English files
0%; a hiragana test is not enough, since an English doc's frontmatter triggers can
be Japanese).

Skipping that step on this repo's own skill docs yields 345 findings of which 332
are noise.

## Exclusions are overridable per project

textlint's own default for `--ignore-path` is `./.textlintignore`, so the wrapper
passes the bundled list only when the working directory has no such file (and
none was given on the command line). **It is a replacement, not a merge.**

This repo ships its own `/.textlintignore` — **not** linked into `~/` — precisely
because the bundled list drops `**/.agents/**` and `**/CLAUDE.md` as vendored
agent config, which is true for a repo that consumes skills and false for this
one, which authors them. With the bundled list all four Japanese documents here
were silently skipped.

**Findings that come back suspiciously empty are an exclusion problem until
proven otherwise** — check with `--ignore-path /dev/null`.

## Testing

Verified by running it, not by a test script: `textlint-docs <some.md>` on a file
with known violations.

Its failure mode is silent: a misspelled or unknown rule key inside a preset
(`sentence-lenght:`, a rule that no longer exists) is **ignored without any
error** — verified empirically — so the rule quietly runs with its default
settings or not at all, and the only symptom is fewer findings.

After editing `textlint/textlintrc.yml`, **check the rule IDs in the output**
rather than the problem count.
