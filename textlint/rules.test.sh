#!/bin/bash
#
# rules.test.sh — pins the local textlint rules in textlint/rules/ without
# textlint itself.
#
# bin/textlint-docs.test.sh stubs textlint, so no rule ever runs there, and CI
# installs no textlint. A rule is a plain function of a context, though, so
# this hands it a fake one -- Syntax, RuleError, report, getSource, locator --
# and Str nodes with the parent chain textlint gives them.
#
# What it pins of ja-no-redundant-phrase is why the rule exists: it matches
# inside one Str node only, so the upstream ja-no-redundant-expression's
# failure -- joining two paragraphs and reporting text the source lacks -- has
# no way to happen; and it carries no fixer, since the rewrite depends on
# conjugation. What it cannot pin is how textlint's Markdown parser cuts nodes;
# the repro in textlintrc.yml was checked against the real toolchain.
#
# The test lives outside textlint/rules/ on purpose: --rulesdir loads every .js
# file there as a rule.
set -uo pipefail

dir="$(cd "$(dirname "$0")" && pwd -P)"

if ! command -v node >/dev/null 2>&1; then
  printf 'FAIL node not found; the rules cannot be tested\n'
  exit 1
fi

# RULE may point at a mutated copy, to show a case can fail without touching
# the real rule.
RULE="${RULE:-$dir/rules/ja-no-redundant-phrase.js}" node <<'JS'
"use strict";
const rule = require(process.env.RULE);

let fails = 0;
function t(name, expected, actual) {
  const e = JSON.stringify(expected), a = JSON.stringify(actual);
  if (e === a) {
    console.log(`ok   ${name}`);
  } else {
    console.log(`FAIL ${name}\n       expected: ${e}\n       actual:   ${a}`);
    fails++;
  }
}

class RuleError {
  constructor(message, where) {
    this.message = message;
    Object.assign(this, where);
  }
}
const withLocator = { range: (r) => ({ range: r }) };

// lint <locator|null> <node...> -> [{ node, text, at, error }]
function lint(locator, ...nodes) {
  const reports = [];
  const handlers = rule({
    Syntax: { Str: "Str" },
    RuleError,
    report: (node, error) => {
      const [s, e] = error.padding ? error.padding.range : [error.index, error.index];
      reports.push({ node, text: node.value.slice(s, e), at: s, error });
    },
    getSource: (node) => node.value,
    locator: locator || undefined,
  });
  for (const node of nodes) handlers.Str(node);
  return reports;
}
// str <value> [<ancestor types, nearest first>]
function str(value, ancestors = ["Paragraph"]) {
  let parent = { type: "Document" };
  for (const type of [...ancestors].reverse()) parent = { type, parent };
  return { type: "Str", value, parent };
}
const texts = (reports) => reports.map((r) => r.text);

// --- what it reports ---
t("ことができる, from the word on", ["ことができ"], texts(lint(withLocator, str("読み込むことができる。"))));
t("することができる includes する", ["することができ"], texts(lint(withLocator, str("実装することができる。"))));
t("することが可能", ["することが可能"], texts(lint(withLocator, str("変更することが可能である。"))));
t("を行う after a kanji noun", ["を行う"], texts(lint(withLocator, str("初回に設定を行う。"))));
t("を行う after a katakana noun", ["を行っ"], texts(lint(withLocator, str("デプロイを行った。"))));
t("を実施する", ["を実施する"], texts(lint(withLocator, str("移行を実施する前に確かめる。"))));
t("two in one node are two reports", 2, lint(withLocator, str("読むことができ、書くことができる。")).length);

// --- what it leaves alone ---
t("を行う after hiragana is not a noun phrase", 0, lint(withLocator, str("すすめを行う。")).length);
t("行うべき without を", 0, lint(withLocator, str("行うべき作業を書き出す。")).length);
t("できる on its own", 0, lint(withLocator, str("読み込める。設定できる。")).length);
for (const ancestors of [["Paragraph", "BlockQuote"], ["Link", "Paragraph"], ["LinkReference", "Paragraph"], ["Image", "Paragraph"]]) {
  t(`nothing inside ${ancestors[ancestors.length - 1] === "Paragraph" ? ancestors[0] : ancestors[1]}`, 0,
    lint(withLocator, str("読み込むことができる。", ancestors)).length);
}

// --- the upstream failure, structurally excluded ---
// textlintrc.yml's repro: two paragraphs, upstream joined them and reported
// "することができるWeb", then --fix wrote into the second one.
const first = str("ドメインロジックを安全に実装することができる");
const second = str("Web アプリケーションを提供する");
const repro = lint(withLocator, first, second);
t("the repro: one report", 1, repro.length);
t("in the first paragraph", true, repro[0] && repro[0].node === first);
t("of text that paragraph holds", "することができ", repro[0] && repro[0].text);
t("nothing in the second", 0, repro.filter((r) => r.node === second).length);

// --- no fixer ---
const all = lint(withLocator, str("読むことができ、設定を行い、移行を実施する。"));
t("no report carries a fix", 0, all.filter((r) => "fix" in r.error).length);

// --- state between nodes ---
// The patterns are global regexes held by the module: a lastIndex left over
// from one node would skip the start of the next.
const twice = lint(withLocator, str("読むことができる。"), str("書くことができる。"));
t("each node is matched from its start", ["ことができ", "ことができ"], texts(twice));

// --- older textlint, without locator ---
t("without locator the index is passed", [2], lint(null, str("読むことができる。")).map((r) => r.at));

if (fails > 0) {
  console.log(`\n${fails} failure(s)`);
  process.exit(1);
}
console.log("PASS");
JS
