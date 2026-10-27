# root/ — home directory agent and tool config

Everything here is symlinked into `$HOME` by `bin/init/links.sh`.

## OpenCode global config mirrors `root/.claude/settings.json`

`root/opencode/opencode.jsonc` is linked to `~/.config/opencode/opencode.jsonc`
and carries the OpenCode counterpart of the Claude permission policy. Both
files are hand-maintained in parallel; neither tool reads the other, so a rule
added to one is private to that tool until the other is edited too. The
comment block at the bottom of the OpenCode file records what could not be
translated (hooks, modes, plugin marketplaces) and at what point a plugin
would have to pick it up.

The translation is not mechanical, because the matchers differ:

- **One ordered array, last match wins.** Claude's `allow` / `ask` / `deny`
  object with hard `deny` precedence becomes a single `permissions` array,
  written allow-first, then ask, then deny. Ordering is load-bearing: the ask
  rules for `git branch -d` sit after the broad `git branch*` allow, the deny
  rules sit last, and nothing matching a deny may follow them.
- **Unmatched means ask, not a classifier.** Claude's `defaultMode: auto`
  judged everything not listed; OpenCode asks — made explicit by the first
  rule, a `{ "*", "*", ask }` catch-all. It is load-bearing because the
  OpenCode docs state two different defaults, both current: "If no rule
  matches, OpenCode uses ask", and, under Defaults, a base policy every agent
  starts with whose first rule is `{ *, *, allow }`. Under the base-policy
  reading an unmatched action would run silently, which is not the posture
  this file carries from Claude; the catch-all asks under either reading and
  overrides nothing an explicit rule grants. Anything the agent must run
  unattended therefore *needs* an allow rule here, not just absence of a deny
  rule. (The `{ question, *, allow }` rule after it keeps the build agent
  able to ask the user its questions the moment everything else asks.)
- **WebFetch domains are URL prefix rules, raw string matched** — the same
  lesson as curl: `https://github.com*` would also match
  `https://github.com.evil.com`, so each domain is two no-leak patterns (bare
  host, host plus path) instead of a trailing wildcard. No subdomain behavior
  was traded away: Claude's `domain:` rule is also an exact-host match
  (subdomains need their own `*.host` rule), and the OpenCode list carries the
  same host entries `settings.json` names.
- **Claude's `:*` prefix rules** (tmux list-panes) get both spellings:
  `cmd:*` and `cmd *`.

The permission *hooks* still live in Claude only (`root/.claude/hooks/`); in
OpenCode their equivalent would be a plugin using `permission.evaluate` /
`shell.create.before` hooks, and until that exists the losses are concrete:

- **curl and `rm`** lose only the hooks' convenience layer — their guard
  scripts auto-approved the safe shapes — and protection rests on the deny
  literals and the default ask, as recorded in the jsonc.
- **`git -C` loses the deny layer outright.** Claude's git-guard.sh applied
  deny and ask rules to `git -C x <subcommand>` over the raw string, which no
  `git <subcommand>` rule matches. The same command in OpenCode matches no
  rule at all and asks, instead of the refusal Claude gave `git -C x push
  --force`. A plugin is the only way to restore it.

That last gap is also why the rules are **tripwires, not boundaries**, in both
tools: the raw-string matchers never understood a path, so `rm /etc/../etc/x`
with a variable, or a symlinked ancestor, walked past them before this
translation too.

`root/opencode/opencode-jsonc.test.sh` guards the file against silent loss:
it parses the JSONC (whole-line comments and trailing commas stripped) and
asserts in a single pass that every rule is well-formed, rule 0 is the ask
catch-all and rule 1 the question allow, the deny rules form a suffix (only
denies may follow a deny) and the last rule is a deny, sentinel denies,
allows and asks are present, and the `mcp.servers` shape is the V2 one.
It also reads `root/.claude/settings.json` and asserts the FULL parity:
every rule here is derivable from a Claude rule via the transformation
recorded in the suite (Bash/Edit/Read strings, WebFetch domains as two
URL prefixes, LS→glob, Search deduped into Grep, Skill, the Sentry MCP
wildcards), plus the five documented rules OpenCode needs and Claude never
did — so editing one side without the other is a red suite, not silently
weaker policy.

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

Do **not** grant curl with `Bash(curl *<domain>*)` allow rules. Permission
patterns match the raw command string with no URL parsing, so `curl *github.com*`
also matches `curl https://evil.com/?ref=github.com`
([documented as fragile](https://code.claude.com/docs/en/permissions.md)).

Per-domain curl access is instead granted by `root/.claude/hooks/curl-guard.sh`,
which parses the argv and checks the real host against the
`WebFetch(domain:...)` rules in `settings.json` (one source of truth for both).

**`Bash(curl *)` must not be in `permissions.ask`.** A hook `allow` does not
override an `ask` rule — [the rule still
prompts](https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks)
— so with that rule present the hook approves nothing and is dead code. It sat
there, doing nothing, until that was noticed.

The hook only ever emits `allow`; anything it cannot verify emits no decision and
falls through to the mode: `default` mode prompts (curl is not in `allow`), auto
mode hands it to the classifier. **Know what that trades away** — the same trade
recorded for `rm` below: an unverified curl in auto mode is no longer a
guaranteed prompt, and `bypassPermissions`, which honours only `ask` rules, now
runs any curl unchecked. `wget`, `nc` and friends stay in `ask`; they have no
guard to be shadowed.

Run `root/.claude/hooks/curl-guard.test.sh` after touching it.

## Destructive filesystem permissions

`rm`, `cp` and `mv` are **not** in `permissions.ask`. `deny` holds the
catastrophic literals (`rm -rf /`, `~`, `/*`, `--no-preserve-root`,
`sudo rm *`, `rm -rf .git`) plus an `rm` mirror of every path the `Edit` rules
deny — the system trees (`/etc`, `/usr`, `/var`, `/opt`, `/bin`, `/sbin`,
`/lib`, `/lib64`, `/boot`, `/proc`, `/sys`, `/dev`) and the ssh private keys.
Anything else is left to the auto-mode classifier.

**The `rm` mirror is a tripwire, not a boundary.** `Edit(/etc/**)` is matched
against a resolved file path; `Bash(rm …)` is matched against the **raw command
string**, so `rm /etc/../etc/passwd`, a variable, or a `cd /etc` beforehand all
walk past it. Each path therefore needs two patterns — `Bash(rm /etc*)` for the
bare form and `Bash(rm * /etc*)` for anything with a flag or an earlier operand —
and even then it only catches the spelling a model would actually write by
accident. Path-level denial requires a permissions profile
(`[permissions.<name>.filesystem]`), the same limitation recorded for `cat .env`
below. Do not read the mirror as making these paths unreachable.

`Bash(rm *)` was in `ask` until it was removed deliberately. The reasoning that
put it there: an `ask` rule is [evaluated before the auto-mode classifier and can
never be
auto-approved](https://code.claude.com/docs/en/auto-mode-config#add-a-human-checkpoint),
which is worth disabling the classifier's far better-informed judgement for only
where a false negative is unrecoverable — and `rm` of a git-untracked file
(`.env`, a local DB, `./tmp/` working data) is exactly that. The reasoning that
took it out: it fired on **every** `rm`, and the hook below could only ever
recover 28% of them, so the checkpoint was mostly friction rather than review.

**Know what that trades away.** `default` mode still prompts for an `rm` the
classifier does not approve, but [`acceptEdits` auto-approves `rm`/`cp`/`mv`
inside the working directory with no classifier at
all](https://code.claude.com/docs/en/permission-modes#auto-approve-file-edits-with-acceptedits-mode),
and `bypassPermissions` skips everything except `ask` rules. That line was the
only gate on `rm` in those two modes, so in them there is now **nothing** between
a model mistake and an unrecoverable delete beyond the `deny` literals. Restoring
the rule is a one-line revert if that turns out to bite.

**Do not carve out exceptions with allow globs like `Bash(rm ./tmp/*)`:**
patterns match the raw string, so that also matches `rm ./tmp/../../important` —
the same fragility documented for curl above. That holds whether or not an `ask`
rule is present, because an `allow` glob would over-approve in `default` mode
too. Scratch-dir cleanup is instead
auto-approved by `root/.claude/hooks/rm-guard.sh`, which parses the argv and
resolves each operand's *parent* physically (`cd -P`), so a symlinked ancestor
cannot smuggle the target elsewhere. The final component stays unresolved on
purpose: `rm` unlinks the name, and `rm -r` on a symlink removes the link rather
than descending into it — **unless the operand ends in `/`**, which makes `rm`
resolve the link: GNU `rm -rf link/` deletes the target's contents and exits 0
(BSD `rm` on macOS only unlinks it, so a Mac cannot show the difference). Such
an operand is resolved whole.

Two scratch roots qualify: `<cwd>/tmp` (the dir `CLAUDE.md` mandates for temp
files, removable whole) and anything at least two levels under
`/tmp/claude-<uid>/` (Claude Code's scratchpad tree, laid out as
`<project>/<session>/…` — never the tree root, which holds every project, nor a
`<project>` dir, which holds every session of it).

Like `curl-guard.sh` the hook only ever emits `allow`. A glob, a redirection, a
shell expansion, an unknown flag or a non-`rm` segment all defer — and with the
`ask` rule gone, **a deferral now lands on the auto-mode classifier rather than
on a prompt.** The hook is kept anyway: it is the only thing that keeps scratch
cleanup prompt-free in `default` mode, and in auto mode it decides those calls
outright instead of paying for a classifier round-trip whose answer could vary.

**It deliberately does not cover compound commands.** A hook `allow` approves the
whole tool call, so `rm -rf tmp; git status --short` would approve the second
segment too; every segment must therefore be a verifiable `rm` on its own.
Measured over 30 days of transcripts (39,282 Bash calls, 253 leading `rm`), that
covers **72 calls — 28%** of them, the rest being compound. Recovering more would
mean reimplementing the allow-list matcher inside the hook, where being looser
than Claude Code's own matcher means over-approving; not worth it. (For `git -C`
that judgement was reversed, for a narrower matcher — see below.)

Run `root/.claude/hooks/rm-guard.test.sh` after touching it.

## git permissions

**No git allow rule may put a `*` before the subcommand.** `Bash(git -C * status*)`
also matched `git -C . -c core.fsmonitor=<cmd> status`, and `-c` makes git run a
program of the caller's choosing; Claude Code warns about the shape at startup
("has a wildcard before the rest of the command"). The 33 `git -C *` allow rules
were removed for that, and because their path reached any repository on the
machine — whose own `.git/config` runs a program on `git status` just as well.
**No git rule names `-C` at all, deny and ask included.** Write a git rule once,
for `git <subcommand>`, and the hooks below give it the same effect on
`git -C <dir> <subcommand>`: an allow rule through `git-dash-c-allow.sh`, a
deny or ask rule through `git-guard.sh`. The 13 `git -C *` copies of deny and
ask rules were removed for that; the suite fails on a git rule naming `-C`.

Three hooks now cover git, with different jobs:

- **`git-dash-c-allow.sh`** approves `git -C <dir> <rest>` when the `-C` lands
  physically inside `$CLAUDE_PROJECT_DIR` and `git <rest>` matches a git allow
  rule from **`~/.claude/settings.json` only** — never project settings, which
  Claude Code ignores until its trust dialog is accepted, and which a cloned repo
  could otherwise use to approve itself. See
  [git-dash-c-allow.md](.claude/hooks/git-dash-c-allow.md).
- **`approve-multiline-commands.sh`** accepts a `-C` on the same terms, through
  the same `git_dash_c_in_project` (`git-workdir.lib.sh`).
- **`git-guard.sh`** denies a dangerous option before the subcommand. A
  PreToolUse `deny` outranks another hook's `allow`, so it is the backstop for a
  bug in either allow hook, and it refuses such a command before the auto mode
  classifier has to judge it. It also applies every settings layer's git
  **deny and ask** rules to a git with an option before its subcommand —
  `git -C x push --force` under `Bash(git push --force*)` — which Claude Code's
  matcher, reading the command as written, does not (`git-rules.lib.sh`).
  Because those rules now live nowhere else, it is registered with
  `"onFailure": "block"` (Claude Code ≥ 2.1.295): a failed hook otherwise lets
  the call through. The price is that a broken git-guard — a syntax error, no
  `jq`, a missing link — blocks **every** Bash call until it is fixed.

**An allow rule's trailing `*` lets every option after the subcommand in,** and
some of those run or write: `git fetch --upload-pack=<cmd>` runs `<cmd>`, and
`--output=<file>` on log, diff and show writes anywhere. Each is a deny rule,
written for the spellings git accepts — `--upload-pack` abbreviates down to
`--upl`, `--output` not at all (every shorter prefix is ambiguous). Verified
against git 2.55 and pinned in `git-guard.test.sh`; recheck them when an allow
rule for another subcommand is added.

**`git grep` has no allow rule, and must not get one back.** `git grep
-O<cmd>` runs `<cmd>`, and so does the bundled short form `-iO<cmd>`. A deny
rule is a glob over the whole command, so it cannot say "an `O` inside a
short-option word": `*-*O*` also refuses `git grep -n TODO`, and anything
narrower misses a bundle. `rg` covers the searching, and a `git grep` asks.
`git-guard.test.sh` fails on an allow rule for it.

**This reverses the rm section's "not worth reimplementing the matcher"**, for a
narrower matcher: only rules whose single `*` is trailing are used, compared word
by word against the argv, so a rule approves nothing through the hook that it
would not approve as written. It can under-approve — a prompt — but not over.

**Know what it costs.** A git -C outside the project, `git -C x remote add`
(`remote*` was wider than the plain `remote` rules), and a compound command that
pairs a git -C with a non-git segment no longer pass silently; in auto mode they
go to the classifier. And git-guard leaves one shape it cannot split — a `case`
inside a quoted substitution — to that classifier rather than refusing it. That
shape also skips the deny and ask rules for a `-C`: `git -C x branch -D "$(echo
case)"` reaches the classifier rather than a prompt. Why that is acceptable, and
the conditions it rests on, are argued at the status 3 exit in `git-guard.sh`.

Run `root/.claude/hooks/git-guard.test.sh`, `git-dash-c-allow.test.sh`,
`approve-multiline-commands.test.sh` and `segment-scan.lib.test.sh` after
touching any of them, or `git-rules.lib.sh`.

### Force push and discarded changes ask; they are not denied

`git push --force-with-lease`, `git checkout -- <path>` and
`git stash drop`/`clear` are `ask` rules (Codex: `prompt`, `git restore`
included). A bare `--force` and `-f` stay `deny`. Both were `deny` until
transcripts showed what refusing them did:

- **A refused undo became a hand-written `sed`.** About 25 `git checkout --`
  refusals in 90 days, most of them the model restoring its *own* temporary
  edit — a mutation to prove a test fails. Refused, it rewrote the line back
  with `sed -i`, which leaves the mutation in place when the pattern misses. A
  path rule cannot tell that edit from the user's uncommitted work, so the gate
  is a prompt, where the user can.
- **A refused lease push was re-issued in other spellings**, `2>&1 | tail`
  dropped one piece at a time, and once not reported at all: a PR was opened
  from the unrebased remote branch. A lease refuses to overwrite a remote that
  moved since the last fetch, so on a feature branch it is a reviewable step.
- **A discarding spelling left open makes the gate one synonym away.**
  `git stash*` is an allow rule, so `git stash drop` was open while
  `git checkout --` was denied. An `ask` outranks an `allow`, which is what
  makes it prompt.

**`git restore` left `ask`, as `rm` did**, and the auto-mode classifier decides
it. It is the undo `root/CLAUDE.md` names for the model's own temporary edit,
and a prompt on every such undo was friction on exactly the case the first
bullet set out to make cheap. A hook cannot recover the safe ones instead: an
`ask` rule is still evaluated whatever a PreToolUse hook returns, and the safe
case is defined by *who wrote the diff*, which no path check can see.

**Know what that trades away.** `git checkout -- <path>` still asks, so for
discarding the prompt is now one synonym away on purpose. In `default` mode a
restore the classifier does not approve still prompts, but under
`bypassPermissions` nothing stands between a model mistake and discarded
uncommitted work. Codex keeps its `prompt` rule, as it keeps `rm`'s. Restoring
the rule is a one-line revert.

The deny rules spell `--force` as a whole word (`git push --force` and
`git push --force *`), because `--force*` also matches `--force-with-lease`.
A refspec with a leading `+` (`git push origin +topic`) also forces and matches
no rule; that gap is older than this change.

**A project's own settings can still deny these**, and a deny in any layer
wins: a work repository that keeps `Bash(git push --force*)` in its
`.claude/settings.json` refuses the lease push there regardless.

## Subagent models are chosen, never inherited

Left to itself, a subagent that names no model runs on the session's model —
Opus, in fast mode, here — and [Claude Code's own workflow
guidance](https://code.claude.com/docs/en/workflows) tells the model to leave it
out ("the agent inherits the main-loop model … almost always correct"), while
ultracode adds that token cost is no constraint. Against that, the old
`CLAUDE.md` line "match the model to the task" lost: under ultracode every
workflow agent ran on Opus, and the token budget went in minutes.

**`agent-model-guard.sh` denies an `Agent` call with no `model`**, and its reason
— which the model reads — lists the tiers, so the retry carries a choice. Those
tiers repeat the `root/CLAUDE.md` rule "Name a model for every subagent";
retune both together. It
deliberately does not fill one in: a fixed model written by a hook is just
another default. It lets through the types that ignore or need no per-call
model (`fork`, `claude-code-guide`, `statusline-setup`); a new built-in with a
fixed cheap model belongs in that list, or it pays a refused round-trip for
nothing.

It fails open — no `jq`, bad input — because a missed choice costs tokens and a
blocked spawn costs the task.

**What gets past the hook lands on Sonnet**, through
`env.CLAUDE_CODE_SUBAGENT_MODEL` in `settings.json`. Since Claude Code 2.1.251
that variable is only a default — a per-call `model`, a script's `agent()`
`model`, or a definition's `model:` still wins — and it covers workflow agents,
whose `agent()` calls the docs never say reach PreToolUse. Two things it does
**not** do: it leaves the built-in `Explore` and `Plan` on the parent's model
(the hook catches those), and it is not `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`,
which would pin every subagent to one tier and remove the choice this section
exists to keep.

The default would have moved `review-test` and `review-design`, forked
`general-purpose` skills, from Opus to Sonnet without anyone deciding it, so
their frontmatter names `model: opus`. A new forked skill should name its tier
the same way.

Run `root/.claude/hooks/agent-model-guard.test.sh` after touching it.

## Claude Code and its plugins update on a delay

Everything else this repo installs waits 7 days before taking a release
([bin/init/pins.md](../bin/init/pins.md)). Claude Code and its plugins would
otherwise be the exception, and they are the most privileged code on the
machine: a plugin's hooks and MCP servers run with the session's rights.

- **`autoUpdatesChannel` is `"stable"`**, which follows a build [typically
  about a week old that skips releases with major
  regressions](https://code.claude.com/docs/en/settings-reference#autoupdateschannel).
  The hooks here depend on Claude Code internals read out of specific builds
  (`agent-state.md`, `git-guard.sh`'s `onFailure` needs ≥ 2.1.295). A feature
  that lands on `latest` reaches this machine about a week later.
- **Plugins are not held.** They come from `claude-plugins-official`, a git
  clone of its default branch that auto-updates, and every installed plugin
  moves with it. A marketplace source cannot be pinned to a commit: its `ref`
  takes a branch or tag ([fields by
  type](https://code.claude.com/docs/en/plugins/marketplace-reference.md#fields-by-type)),
  and that repository has no tags. A commit `sha` is accepted only on a plugin
  entry inside a marketplace. Re-declaring the plugins in an inline
  (`"source": "settings"`) marketplace with their own `sha` worked, and was
  tried and dropped (2026-10).

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

This applies to `review-test`, `review-design`, `review-design-doc`, `review-support`,
`check-production-readiness`, `retrospective`, and `session-summary`. Of these, `review-design` is
the one whose `allowed-tools` pre-approves git — the reading commands only, since the
range under review is the input of every run — so its body also forbids
`--output`, the flag that makes `git diff` and `git log` write a file.

`agents/openai.yaml` inside a skill supplies Codex UI metadata and is ignored
elsewhere.

`evals/` inside a skill holds its eval cases, run by `bin/skill-eval` — see
[bin/skill-eval.md](../bin/skill-eval.md). Nothing but that runner reads them,
but because skills are linked as whole directories, the cases do ship to every
machine that runs `relink`.
