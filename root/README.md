# root/ — home directory agent and tool config

Everything here is symlinked into `$HOME` by `bin/init/links.sh`.

## Global agent instructions: three destinations, all load-bearing

`root/CLAUDE.md` is linked to:

| Link | Reader |
| --- | --- |
| `~/CLAUDE.md` | Claude Code |
| `~/AGENTS.md` | generic `AGENTS.md` readers |
| `~/.codex/AGENTS.md` | Codex |

The third is required because [Codex reads its global layer only from
`$CODEX_HOME`](https://learn.chatgpt.com/docs/agent-configuration/agents-md) —
`AGENTS.override.md`, then the first **non-empty** `AGENTS.md` — while its
project scope walks from the git root down to cwd and therefore never visits
`$HOME`.

**An empty `~/.codex/AGENTS.md` is skipped, not treated as "no instructions", so
the failure is silent**: project-level docs keep loading (Codex is pointed at
`CLAUDE.md` via `project_doc_fallback_filenames` in the machine-local
`~/.codex/config.toml`) and only the global layer goes missing.

Verify with `codex debug prompt-input`, which dumps the exact prompt Codex
builds — grep it for a phrase unique to `root/CLAUDE.md`.

Note the content is Claude-flavoured (tool names like Read/Grep/Edit,
`AskUserQuestion`, the subagent guidance); Codex ignores what it cannot map.

`~/.codex/config.toml` is deliberately **not** version-controlled — Codex writes
per-project `trust_level` and `[notice]` state into it
([upstream issue](https://github.com/openai/codex/issues/14601)).

## This repository is public, and `root/.claude/settings.json` keeps forgetting it

Claude Code's `/config` writes machine-local state straight into the file this
repo tracks, and **`autoMode.environment` is the dangerous one**: it is a
*generated profile of whatever repository you were working in* — org and repo
names, cloud providers, CI secret **names**, which files hold credentials,
branch-protection status, absolute `$HOME` paths.

None of it is a credential, so no secret scanner flags it; all of it is a map for
someone attacking the private repo it describes. One such profile (a work
monorepo, its AWS/Vercel posture and its `.env` locations) sat on `origin/main`
from `9a07263` until it was removed.

**Auto mode's environment profile belongs in the project it describes** — a
`.claude/settings.json` inside that private repo — never here. The same rule
covers any per-project `soft_deny`, trusted-repo path, or `$HOME`-absolute path.

Removing it from HEAD does not unpublish it; forks and clones keep it, which is
exactly why it must not be committed in the first place.

**Test fixtures count too:** `git-guard.test.sh` published a private repo path
purely as a sample argument, now a placeholder.

## curl permissions

**`Bash(curl *)` must stay in `permissions.ask`** — do **not** replace it with
`Bash(curl *<domain>*)` allow rules. Permission patterns match the raw command
string with no URL parsing, so `curl *github.com*` also matches
`curl https://evil.com/?ref=github.com`
([documented as fragile](https://code.claude.com/docs/en/permissions.md)).

Per-domain curl access is instead granted by `root/.claude/hooks/curl-guard.sh`,
which parses the argv and checks the real host against the
`WebFetch(domain:...)` rules in `settings.json` (one source of truth for both).

The hook only ever emits `allow`; anything it cannot verify emits no decision and
falls through to that `ask` rule — so **removing the `ask` rule silently
downgrades every deferral to the auto-mode classifier.**

Run `root/.claude/hooks/curl-guard.test.sh` after touching it.

## Destructive filesystem permissions

`Bash(rm *)` stays in `permissions.ask`; `cp` and `mv` are deliberately not
there.

An `ask` rule is [evaluated before the auto-mode classifier and can never be
auto-approved](https://code.claude.com/docs/en/auto-mode-config#add-a-human-checkpoint),
so listing a command there disables the classifier's far better-informed
judgement for it — worth it only where a false negative is unrecoverable. That is
`rm` (git-untracked files: `.env`, local DBs, `./tmp/` working data), not
`cp`/`mv`, whose worst case is a recoverable clobber.

The rule is also load-bearing outside auto mode: `default` mode prompts for these
anyway, but [`acceptEdits` auto-approves `rm`/`cp`/`mv` inside the working
directory with no classifier at
all](https://code.claude.com/docs/en/permission-modes#auto-approve-file-edits-with-acceptedits-mode),
and `bypassPermissions` skips everything except `ask` rules — so this line is the
only gate on `rm` in those modes.

**Do not carve out exceptions with allow globs like `Bash(rm ./tmp/*)`:**
patterns match the raw string, so that also matches `rm ./tmp/../../important` —
the same fragility documented for curl above. Use an argv-parsing hook modelled
on `curl-guard.sh` instead.

## Codex prefix rules

`root/.codex/rules/default.rules` is linked to `~/.codex/rules` and is the Codex
counterpart to `settings.json` permissions.

`forbidden` rules carry
[`match`/`not_match`](https://learn.chatgpt.com/docs/agent-configuration/rules)
example commands that Codex asserts at load time — the only executable tests the
rules have.

**Run `root/.codex/rules/default.rules.test.sh` after editing.** A violated
assertion makes Codex drop the *entire file* silently (exit 0, empty stderr, no
TUI warning), so one bad example disables every `forbidden` rule at once — **it
fails open.** The test script turns that into a loud failure by asserting known-
allowed prefixes are present, and gated ones absent, in
`codex debug prompt-input`.

It is intentionally **not** in CI: it requires the `codex` CLI and exits 0 with
"skipping" when absent, which would be a permanently green check proving
nothing.

**Patterns match whole argv tokens, never substrings**: `--force` does not match
`--force-with-lease`, `-fd` does not match `-fdx`, `mkfs` does not match
`mkfs.ext4` — each spelling needs its own rule.

`env`/`printenv` are `prompt` rather than `forbidden` because a `forbidden`
decision cannot be overridden in-session, which would block legitimate
shell-environment debugging. Note this does not protect file contents, since
`cat .env` remains allowed — path-level denial requires a permissions profile
(`[permissions.<name>.filesystem]`), not a prefix rule.

## Agent skills

Skills this repo OWNS live once under `root/.agents/skills/<name>/SKILL.md`.

The setup script links each owned skill **individually** into every consumer dir
(`~/.agents/skills` cross-tool standard, `~/.claude/skills` Claude Code,
`~/.codex/skills` Codex) — **never the whole dir as one symlink.**

This is deliberate: a directory symlink lets tools that auto-install skills (e.g.
Cloudflare's installer writing into `~/.agents` or `~/.claude`) create real dirs
straight into this repo through the link, polluting it with untracked skills.
With per-skill links the consumer dirs stay real directories, so tool-installed
skills land beside our symlinks but **outside** the repo (untracked).

Trade-off: adding a new owned skill needs a `relink` to appear (`update-all` runs
relink, so it self-heals). Add one by creating its dir here, then run `relink`.

Note OpenCode reads both `~/.agents/skills` and `~/.claude/skills`, so it may
list each skill twice.

### Ignored means unenforced, which matters for safety

Skills use Claude frontmatter (`effort`, `allowed-tools`) and `!` command
pre-fetch; other tools ignore the extra fields, and `!` lines render as inert
text for them.

[Codex reads only `name` and `description`](https://learn.chatgpt.com/docs/build-skills),
so a read-only skill's `allowed-tools` fence **does not exist there** — and
`default.rules` pre-approves `git add`/`commit -m`/`push` and
`gh pr create`/`edit`, so the very operations such a skill forbids run with no
prompt.

**Any skill whose contract is "read-only" or "never writes/posts" must therefore
state that boundary in the body**, name the concrete commands, and say explicitly
that absence of a prompt is not permission. Frontmatter alone is a Claude-only
guarantee.

This applies to `review-test`, `review-support`, `check-production-readiness`,
and `retrospective`.

`agents/openai.yaml` inside a skill supplies Codex UI metadata and is ignored
elsewhere.

`evals/` inside a skill holds its eval cases, run by `bin/skill-eval` — see
[bin/skill-eval.md](../bin/skill-eval.md). Nothing but that runner reads them,
but because skills are linked as whole directories, the cases do ship to every
machine that runs `relink`.
