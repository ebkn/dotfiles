#!/bin/bash
# Guards opencode.jsonc against silent loss.
#
# Why this exists: the file is hand-maintained and carries the whole OpenCode
# permission policy (the counterpart of root/.claude/settings.json). Nothing
# else reads it before OpenCode does, and a config that fails to parse or a
# rule that lost a character would degrade silently -- an unmatched rule asks,
# so every removal makes the agent prompt more or, for a broken parse, strips
# every deny at once. This suite fails closed instead: one node pass parses
# the JSONC (whole-line // comments and trailing commas are the JSONC
# extension) and asserts, against the PARSED rules rather than the text, that
#
#   - the first rule is the { *, *, ask } catch-all and the question allow
#     follows it (the catch-all is load-bearing for the unmatched-ask
#     posture; the jsonc header says why),
#   - denies form a suffix: only deny rules may follow a deny, and the last
#     rule is a deny -- nothing after them may soften them,
#   - every sentinel deny/allow/ask is present (a dropped tripwire or
#     webfetch host is a red suite, not a config),
#   - mcp.servers carries aws-mcp in the V2 shape, with the pinned version
#     (exact: @1.7.0, raising it is a deliberate edit) and the 7-day hold
#     the file comment rests on,
#   - compaction.auto is explicitly false and update is notify,
#   - and the FULL parity with root/.claude/settings.json holds: every rule
#     here is derivable from a Claude rule via an explicit transformation
#     (Bash/Edit/Read → shell/edit/read strings, WebFetch domains ×2 URL
#     prefixes, LS → glob, Search deduped into Grep, Skill, the Sentry MCP
#     wildcards), plus the FIVE documented fixture rules OpenCode needs and
#     Claude never did (catch-all, question, the .env trio). Editing one
#     side without the other is red, not silently weaker. The deny-rule
#     (119) and webfetch-host (118) counts stay pinned because removing the
#     same rule from BOTH files at once is the drift parity cannot see.
#
# Run by bin/test (discovery is `git ls-files`, tracked is enough for CI).
set -eo pipefail

# shellcheck source=bin/test-lib.sh
. "$(dirname "$0")/../../bin/test-lib.sh" || exit 2

config=$(cd "$(dirname "$0")" && pwd)/opencode.jsonc
# The source of truth this file mirrors: root/.claude/settings.json. The
# parity check in the node program reads it as argument 2; hardcoding one
# path (and failing loudly when it moves) beats quietly skipping the whole
# check.
claudeSet=$(cd "$(dirname "$0")" && pwd)/../.claude/settings.json

# The whole policy in one node pass: parsing and checking share one process,
# and the assertions land on parsed data, not on strings that could also
# match inside a comment.
# ── run ───────────────────────────────────────────────────────────────
# shellcheck disable=SC2016  # the single quotes are the node program; inside it $ is JS, not shell
assert_status "opencode.jsonc policy intact and faithful to settings.json" 0 node -e '
const fs = require("fs");
const raw = fs.readFileSync(process.argv[1], "utf8");
// Whole-line // comments only -- this file never comments to the right of a
// rule; a right-side comment would need a real tokenizer instead.
let s = raw.split("\n").filter((l) => !/^\s*\/\//.test(l)).join("\n");
// JSONC allows trailing commas; JSON.parse does not.
s = s.replace(/,(\s*[\]}])/g, "$1");
const c = JSON.parse(s);

// The Claude settings this file mirrors: one shared parser, because the
// .claude side is plain JSON but the same comment-tolerance cannot hurt.
// If it ever moves, the suite now fails in exactly one place.
const cc = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));

const bad = [];
const perms = c.permissions;
if (!Array.isArray(perms) || perms.length === 0) bad.push("permissions array missing or empty");

const rank = { allow: 0, ask: 1, deny: 2 };
let firstDeny = -1;
// Rule 0 must be the catch-all asking for everything unmatched (the jsonc
// header explains the two readings of the OpenCode defaults it survives);
// rule 1 must keep the build agent able to question the user once every
// other action it takes asks by default.
perms.forEach((r, i) => {
  for (const k of ["action", "resource", "effect"]) {
    if (typeof r[k] !== "string" || r[k] === "") bad.push(`rule ${i}: ${k} is not a non-empty string`);
  }
  if (!(r.effect in rank)) bad.push(`rule ${i}: unknown effect ${JSON.stringify(r.effect)}`);
  // Order is semantic under last-match-wins. Within the allow/ask part,
  // later narrow rules overriding earlier broad ones (git branch*, the .env
  // asks under read *) is the intended translation; what must hold is that
  // the deny rules form a suffix -- nothing after a deny may soften it.
  if (i === 0 && !(r.action === "*" && r.resource === "*" && r.effect === "ask")) {
    bad.push("rule 0 is not the { *, *, ask } catch-all");
  }
  if (i === 1 && !(r.action === "question" && r.resource === "*" && r.effect === "allow")) {
    bad.push("rule 1 is not the { question, *, allow } grant");
  }
  if (r.effect === "deny" && firstDeny === -1) firstDeny = i;
  else if (firstDeny !== -1 && r.effect !== "deny") {
    bad.push(`rule ${i} (${r.effect} ${r.resource}) follows a deny`);
  }
});
if (perms.length > 0 && perms[perms.length - 1].effect !== "deny") {
  bad.push(`last rule is ${perms[perms.length - 1].effect}, not deny`);
}

const has = (eff) =>
  (action, resource) => perms.some((p) => p.effect === eff && p.action === action && p.resource === resource);
const deny = has("deny");
for (const [action, resource] of [
  ["shell", "rm -rf /"],
  ["shell", "rm -rf /*"],
  ["shell", "sudo *"],
  ["shell", "dd *"],
  ["shell", "rm ~/.ssh/*_ed25519"],
  ["shell", "env *"],
  ["shell", "printenv *"],
  ["shell", "git push --force"],
  ["shell", "git push -f*"],
  ["shell", "git reset --hard *"],
  ["shell", "git fetch *--upl*"],
  ["shell", "go test * -exec *"],
  ["shell", "npm publish *"],
  ["edit", "/etc*"],
  ["edit", "/etc/sudoers"],
]) {
  if (!deny(action, resource)) bad.push(`deny sentinel missing: ${action} ${resource}`);
}
for (const resource of ["git status*", "rg *", "yq *", "gh pr view *", "go test*", "yarn install*"]) {
  if (!has("allow")("shell", resource)) bad.push(`shell allow sentinel missing: ${resource}`);
}
if (!has("allow")("edit", "*")) bad.push("allow sentinel missing: edit *");

// The broad allow must sit before the narrow ask for the ask to win.
const idx = (eff) => (action, resource) =>
  perms.findIndex((p) => p.effect === eff && p.action === action && p.resource === resource);
for (const [broad, narrow] of [
  ["git branch*", "git branch -d *"],
  ["git branch*", "git branch -D *"],
  ["git stash*", "git stash drop*"],
  ["git stash*", "git stash clear*"],
]) {
  if (idx("ask")("shell", narrow) < idx("allow")("shell", broad)) bad.push(`${narrow} ask sits before ${broad} allow`);
}
// The .env asks must come after the broad read allow (to override it) and
// before the .env.example allow (which cancels them), as the base policy has it.
if (idx("ask")("read", "*.env") < idx("allow")("read", "*")) bad.push("*.env ask sits before read * allow");
if (idx("allow")("read", "*.env.example") < idx("ask")("read", "*.env.*")) {
  bad.push("*.env.example allow sits before the *.env asks");
}

if (!has("ask")("shell", "git push --force-with-lease*")) bad.push("ask sentinel missing: git push --force-with-lease*");
if (!has("ask")("shell", "git stash drop*")) bad.push("ask sentinel missing: git stash drop*");

// The webfetch host count is the pin for a blind spot full parity and the
// deny count share: parity alone stays green when the same host is
// dropped from BOTH files at once — dropped per-side it goes red. These
// constants turn that shared drop red until the numbers are deliberately
// updated.
const hosts = perms.filter((p) => p.effect === "allow" && p.action === "webfetch" && p.resource.startsWith("https://")).length;
if (hosts !== 118) bad.push(`webfetch https rules = ${hosts}, want 118 (59 hosts, bare + slash)`);

const server = (((c.mcp || {}).servers || {})["aws-mcp"] || {});
if (!Array.isArray(server.command)) bad.push("mcp.servers.aws-mcp.command missing (deprecated direct entry?)");
const cmd = server.command.join(" ");
for (const needle of ["uvx", "--exclude-newer", "7 days"]) {
  if (!cmd.includes(needle)) bad.push(`mcp.servers.aws-mcp.command lost its ${needle} hold — the window the file comment rests on`);
}
if (!server.command.includes("mcp-proxy-for-aws@1.7.0")) {
  // Exact version on purpose: "mcp-proxy-for-aws@" alone would accept the
  // @latest an installer writes, the very relaxation this file forbids.
  // Pointing the pin at a newer release is the one deliberate edit; raise
  // the version here when you do.
  bad.push("mcp.servers.aws-mcp.command is not pinned to mcp-proxy-for-aws@1.7.0 (raise the pin deliberately — never @latest, per the file comment)");
}
// The deny count is the deny-side pin, for the same reason the webfetch
// count above spells out: multiset parity cannot see a rule the same
// commit removes from BOTH files, and a broken deny is the failure that
// runs. Update the number deliberately.
const denyCount = perms.filter((p) => p.effect === "deny").length;
if (denyCount !== 119) bad.push(`deny count = ${denyCount}, want 119 (removals from BOTH files are invisible to parity; update the number on purpose)`);
if (c.compaction?.auto !== false) bad.push(`compaction.auto = ${JSON.stringify(c.compaction?.auto)}, want explicitly false (OpenCode defaults it to true; the jsonc comment explains)`);
if (c.update !== "notify") bad.push(`update = ${JSON.stringify(c.update)}, want notify`);

// ── parity: this file mirrors the Claude settings.json rule set ──
// The sentinels above pin single points; this holds the WHOLE translation
// to that rule set. Every rule here must be derivable from a Claude rule
// (or the named fixture below), and every Claude rule must land
// somewhere: drift in EITHER file is red, instead of the silent
// weakening the README warns about. The dictionary is the translation
// record — a Claude form not recognised here fails loudly.
function toOc(r, eff) {
  if (r === "WebSearch") return [[eff, "websearch", "*"]];
  if (r.startsWith("mcp__plugin_sentry_sentry__")) {
    // OpenCode MCP permission actions are "<server>_<tool>": the plugin
    // server part is unwritten, so the wildcard stands in for it. Pinned
    // fixture until the Sentry MCP server is actually registered here.
    return [[eff, "*" + r.replace("mcp__plugin_sentry_sentry__", "_"), "*"]];
  }
  const m = r.match(/^(.*?)\((.*)\)$/);
  if (m) {
    const [, tool, raw] = m;
    const arg = raw.replace(/^domain:/, "");
    if (tool === "Bash") {
      // ":*" means a bare prefix too; the space spelling covers it but not
      // the no-colon one, so BOTH rules go in (tmux list-panes/-sessions).
      if (arg.endsWith(":*")) return [[eff, "shell", arg], [eff, "shell", arg.slice(0, -2) + " *"]];
      return [[eff, "shell", arg]];
    }
    if (tool === "WebFetch") {
      // Exact-host, two no-leak patterns: a trailing * on a bare host
      // would also match https://host.evil.com; /**-style prefixes leak.
      return [[eff, "webfetch", "https://" + arg], [eff, "webfetch", "https://" + arg + "/*"]];
    }
    // There are four Claude path shapes: "**" (any path) becomes the
    // whole-value "*", a "<p>/**" tree becomes "<p>*", a full path
    // (/etc/passwd) and the ~/.ssh wildcard patterns pass through
    // unchanged. An unknown TOOL name is what throws; these path shapes
    // are all identity or the two wildcard rewrites above.
    if (tool === "Edit") return [[eff, "edit", arg === "**" ? "*" : arg.replace(/\/\*\*$/, "*")]];
    // LS and Search have no OpenCode tools: file discovery is glob ("LS"),
    // content search is grep — and Search is the same content-search role
    // Grep already covers, so its rule is not mirrored twice.
    if (tool === "Read") return [[eff, "read", arg === "**" ? "*" : arg.replace(/\/\*\*$/, "*")]];
    if (tool === "Grep") return [[eff, "grep", arg === "**" ? "*" : arg.replace(/\/\*\*$/, "*")]];
    if (tool === "LS") return [[eff, "glob", arg === "**" ? "*" : arg.replace(/\/\*\*$/, "*")]];
    if (tool === "Search") return [];
    if (tool === "Skill") return [[eff, "skill", arg]];
  }
  throw new Error("unmapped Claude rule " + JSON.stringify(r));
}

const derived = [];
for (const kind of ["allow", "ask", "deny"]) {
  for (const r of cc.permissions[kind] || []) derived.push(...toOc(r, kind));
}
// The five rules OpenCode needs and Claude never did — each load-bearing
// for a companion reason, not filler; the jsonc header documents them.
derived.push(
  ["ask", "*", "*"], // catch-all: unmatched asks under either docs reading
  ["allow", "question", "*"], // the question tool keeps working once catch-all asks
  ["ask", "read", "*.env"], // base policy restated: the read * allow would silently
  ["ask", "read", "*.env.*"], // override these...
  ["allow", "read", "*.env.example"], // ...and this example-file allow cancels them
);
const want = {};
for (const [eff, action, resource] of derived) {
  const key = `${eff}/${action}/${resource}`;
  want[key] = (want[key] || 0) + 1;
}
const extra = [];
for (const r of perms) {
  const key = `${r.effect}/${r.action}/${r.resource}`;
  if (!want[key]) extra.push(`unmirrored rule: ${key}`);
  else want[key]--;
}
if (extra.length > 0) bad.push(...extra);
bad.push(...Object.entries(want).filter(([, n]) => n > 0).map(([key, n]) => `not mirrored (x${n}): ${key}`));


if (bad.length > 0) {
  process.stdout.write(bad.join("\n") + "\n");
  process.exit(1);
}
console.log(`allowed: policy intact and faithful (rules: ${perms.length})`);
' "$config" "$claudeSet"

test_summary
