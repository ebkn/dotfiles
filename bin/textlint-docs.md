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

## Local rules live in textlint/rules/

Rules that are not npm packages, such as `ja-no-redundant-phrase` (redundant
phrasing, report only), sit in `textlint/rules/`. The wrapper replaces the
cache's copy whole on every run and passes it as `--rulesdir`. Replacing it
whole, rather than copying over the old copy, matters: a rule deleted here
would otherwise keep reporting from the cache.

**Do not name a local rule in `textlintrc.yml`.** A rule key textlint cannot
resolve as a package makes it discard *every* rule in the config file. The run
then uses only what `--rulesdir` supplies, says nothing, and keeps the same
exit code. Measured on the eval fixture, 11 findings became 1. A local rule
is therefore enabled by being in the directory, and its options go in the rule
file. The cost is that a missing `--rulesdir` drops the local rule silently,
which is why the test pins that the flag is passed on both ignore branches.

It replaces `ja-no-redundant-expression`, which stays disabled. That rule
joins text across node boundaries, so it matches strings the source does not
contain and its `--fix` corrupts words. The local rule matches inside one
`Str` node and has no fixer, since "読み込むことができる → 読み込める"
depends on conjugation, which string replacement cannot produce.

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

`bin/textlint-docs.test.sh` pins the script's own decisions with npm stubbed:
when the toolchain is installed, that a failed install leaves no manifest behind
(so the next run installs again), that the local rules are refreshed whole and
passed as `--rulesdir`, which ignore list textlint gets in each of the three
cases, and that textlint's exit status passes through. The **rules**
are not in it: they are verified by running `textlint-docs <some.md>` on a file
with known violations.

Its failure mode is silent: a misspelled or unknown rule key inside a preset
(`sentence-lenght:`, a rule that no longer exists) is **ignored without any
error** — verified empirically — so the rule quietly runs with its default
settings or not at all, and the only symptom is fewer findings.

After editing `textlint/textlintrc.yml`, **check the rule IDs in the output**
rather than the problem count.
