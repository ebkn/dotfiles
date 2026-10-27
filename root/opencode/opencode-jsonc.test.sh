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
#   - mcp.servers carries aws-mcp in the V2 shape (a direct mcp.<name> entry
#     is schema-deprecated; the comment in the file says why),
#   - compaction.auto is explicitly false and update is notify.
#
# Run by bin/test (discovery is `git ls-files`, tracked is enough for CI).
set -eo pipefail

# shellcheck source=bin/test-lib.sh
. "$(dirname "$0")/../../bin/test-lib.sh" || exit 2

config=$(cd "$(dirname "$0")" && pwd)/opencode.jsonc

# The whole policy in one node pass: parsing and checking share one process,
# and the assertions land on parsed data, not on strings that could also
# match inside a comment.
# shellcheck disable=SC2016  # the single quotes are the node program; inside it $ is JS, not shell
assert_status "opencode.jsonc policy intact" 0 node -e '
const fs = require("fs");
const raw = fs.readFileSync(process.argv[1], "utf8");
// Whole-line // comments only -- this file never comments to the right of a
// rule; a right-side comment would need a real tokenizer instead.
let s = raw.split("\n").filter((l) => !/^\s*\/\//.test(l)).join("\n");
// JSONC allows trailing commas; JSON.parse does not.
s = s.replace(/,(\s*[\]}])/g, "$1");
const c = JSON.parse(s);

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

const hosts = perms.filter((p) => p.effect === "allow" && p.action === "webfetch" && p.resource.startsWith("https://")).length;
if (hosts !== 118) bad.push(`webfetch https rules = ${hosts}, want 118 (59 hosts, bare + slash)`);

const server = (((c.mcp || {}).servers || {})["aws-mcp"] || {});
if (!Array.isArray(server.command)) bad.push("mcp.servers.aws-mcp.command missing (deprecated direct entry?)");
if (c.compaction?.auto !== false) bad.push(`compaction.auto = ${JSON.stringify(c.compaction?.auto)}, want explicitly false (OpenCode defaults it to true; the jsonc comment explains)`);
if (c.update !== "notify") bad.push(`update = ${JSON.stringify(c.update)}, want notify`);

if (bad.length > 0) {
  process.stdout.write(bad.join("\n") + "\n");
  process.exit(1);
}
console.log(`allowed: policy intact (rules: ${perms.length})`);
' "$config"

test_summary
