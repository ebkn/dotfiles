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
# Of ja-no-ai-phrase it pins the sentence anchoring -- an opening or closing
# formula is found in any sentence of a paragraph, not only the first, and not
# mid-sentence -- one report where two patterns overlap, and no fixer. Which
# patterns are worth carrying is a measurement on real text, not a test: see
# bin/textlint-docs.md.
#
# The test lives outside textlint/rules/ on purpose: --rulesdir loads every .js
# file there as a rule.
set -uo pipefail

dir="$(cd "$(dirname "$0")" && pwd -P)"

if ! command -v node >/dev/null 2>&1; then
  printf 'FAIL node not found; the rules cannot be tested\n'
  exit 1
fi

# RULES_DIR may point at a mutated copy of textlint/rules/, to show a case can
# fail without touching the real rules.
RULES_DIR="${RULES_DIR:-$dir/rules}" node <<'JS'
"use strict";
const path = require("path");
const load = (name) => require(path.join(process.env.RULES_DIR, `${name}.js`));
const redundant = load("ja-no-redundant-phrase");

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

// lint <rule> <locator|null> <node...> -> [{ node, text, at, error }]
function lint(rule, locator, ...nodes) {
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

// ===== ja-no-redundant-phrase =====

// --- what it reports ---
t("ことができる, from the word on", ["ことができ"], texts(lint(redundant, withLocator, str("読み込むことができる。"))));
t("することができる includes する", ["することができ"], texts(lint(redundant, withLocator, str("実装することができる。"))));
t("することが可能", ["することが可能"], texts(lint(redundant, withLocator, str("変更することが可能である。"))));
t("を行う after a kanji noun", ["を行う"], texts(lint(redundant, withLocator, str("初回に設定を行う。"))));
t("を行う after a katakana noun", ["を行っ"], texts(lint(redundant, withLocator, str("デプロイを行った。"))));
t("を実施する", ["を実施する"], texts(lint(redundant, withLocator, str("移行を実施する前に確かめる。"))));
t("two in one node are two reports", 2, lint(redundant, withLocator, str("読むことができ、書くことができる。")).length);

// --- what it leaves alone ---
t("を行う after hiragana is not a noun phrase", 0, lint(redundant, withLocator, str("すすめを行う。")).length);
t("行うべき without を", 0, lint(redundant, withLocator, str("行うべき作業を書き出す。")).length);
t("できる on its own", 0, lint(redundant, withLocator, str("読み込める。設定できる。")).length);
for (const ancestors of [["Paragraph", "BlockQuote"], ["Link", "Paragraph"], ["LinkReference", "Paragraph"], ["Image", "Paragraph"]]) {
  t(`nothing inside ${ancestors[ancestors.length - 1] === "Paragraph" ? ancestors[0] : ancestors[1]}`, 0,
    lint(redundant, withLocator, str("読み込むことができる。", ancestors)).length);
}

// ... and what it still reads. Skipping too much fails silently -- fewer
// findings, nothing else -- and list items are where generated prose puts
// the most of it.
for (const ancestors of [["ListItem", "List"], ["Header"], ["Strong", "Paragraph"], ["Emphasis", "Paragraph"], ["TableCell", "TableRow", "Table"]]) {
  t(`reported inside ${ancestors[0]}`, 1, lint(redundant, withLocator, str("読み込むことができる。", ancestors)).length);
}

// --- the upstream failure, structurally excluded ---
// textlintrc.yml's repro: two paragraphs, upstream joined them and reported
// "することができるWeb", then --fix wrote into the second one.
const first = str("ドメインロジックを安全に実装することができる");
const second = str("Web アプリケーションを提供する");
const repro = lint(redundant, withLocator, first, second);
t("the repro: one report", 1, repro.length);
t("in the first paragraph", true, repro[0] && repro[0].node === first);
t("of text that paragraph holds", "することができ", repro[0] && repro[0].text);
t("nothing in the second", 0, repro.filter((r) => r.node === second).length);

// --- no fixer ---
const all = lint(redundant, withLocator, str("読むことができ、設定を行い、移行を実施する。"));
t("no report carries a fix", 0, all.filter((r) => "fix" in r.error).length);

// --- state between nodes ---
// The patterns are global regexes held by the module: a lastIndex left over
// from one node would skip the start of the next.
const twice = lint(redundant, withLocator, str("読むことができる。"), str("書くことができる。"));
t("each node is matched from its start", ["ことができ", "ことができ"], texts(twice));

// --- older textlint, without locator ---
t("without locator the index is passed", [2], lint(redundant, null, str("読むことができる。")).map((r) => r.at));

// ===== ja-no-ai-phrase =====
const ai = load("ja-no-ai-phrase");
const aiTexts = (...values) => texts(lint(ai, withLocator, ...values.map((v) => str(v))));

// --- what it reports: one of each kind ---
t("a figurative verb", ["時間を溶かし"], aiTexts("調査で時間を溶かした。"));
t("a translated idiom", ["黙って無視"], aiTexts("設定は黙って無視される。"));
t("an opening filler", ["重要なのは、"], aiTexts("重要なのは、順番を守ることです。"));
t("a closing formula", ["いかがでしたか？"], aiTexts("いかがでしたか？"));
t("a chat-reply remnant", ["ご質問ありがとうございます"], aiTexts("ご質問ありがとうございます。"));

// --- sentence anchors ---
// The filler patterns hold only at the start or end of a sentence, and a Str
// node is a whole paragraph: anchoring to the node instead would miss every
// sentence but the first, and nothing would say so.
t("an opening filler after a period", ["重要なのは、"], aiTexts("手順は三つある。重要なのは、順番を守ることだ。"));
t("an opening filler mid-sentence is not one", [], aiTexts("最も重要なのは順番だと書いた。"));
t("a closing formula before another sentence", ["いかがでしたか？"], aiTexts("いかがでしたか？次の節へ進みます。"));
t("a closing formula mid-sentence is not one", [], aiTexts("いかがでしたかと聞かれた。"));
// A wrapped paragraph puts a newline after the period; the sentence starts
// after it, or ^ never holds and the filler is missed without a word.
t("an opening filler after a line break", ["重要なのは、"], aiTexts("手順は三つある。\n重要なのは、順番だ。"));
t("a sentence ends at a half-width ?", ["重要なのは、"], aiTexts("順番は守れていますか?重要なのは、順番だ。"));
t("a sentence ends at !", ["重要なのは、"], aiTexts("できた！重要なのは、順番だ。"));
t("過言 holds at the end of a sentence", ["と言っても過言ではありません"],
  aiTexts("障害の多くは設定の誤りと言っても過言ではありません。"));
t("過言 mid-sentence is not one", [], aiTexts("と言っても過言ではありませんという言い方を避ける。"));

// --- one report where patterns overlap ---
// 「データが静かに壊れ」 is matched by two patterns; two reports of one phrase
// would read as two problems.
t("overlapping patterns are one report", ["データが静かに壊れ"], aiTexts("データが静かに壊れる。"));
// ... and only overlapping ones: separate phrases in one paragraph are each
// reported. textlint sorts reports by position, so that is the order compared.
const byPosition = (reports) => [...reports].sort((a, b) => a.at - b.at).map((r) => r.text);
t("separate phrases in one node are each reported", ["重要なのは、", "時間を溶かさ", "いかがでしたか？"],
  byPosition(lint(ai, withLocator, str("重要なのは、時間を溶かさないことです。いかがでしたか？"))));

// --- the message: the only thing a reader of the report sees ---
t("the message names the kind, the phrase and the hint",
  ["比喩動詞「時間を溶かし」: 「時間を費やす」「時間がかかる」と書いてください。"],
  lint(ai, withLocator, str("時間を溶かした。")).map((r) => r.error.message));

// --- what it leaves alone ---
t("the literal verb", [], aiTexts("時計が壊れた。ジャガイモを潰す。"));
// The skip list is this module's own copy, so the redundant-phrase cases above
// do not cover it.
for (const ancestors of [["Paragraph", "BlockQuote"], ["Link", "Paragraph"], ["LinkReference", "Paragraph"], ["Image", "Paragraph"]]) {
  t(`nothing inside ${ancestors[ancestors.length - 1] === "Paragraph" ? ancestors[0] : ancestors[1]}`, 0,
    lint(ai, withLocator, str("いかがでしたか？", ancestors)).length);
}
t("reported inside a list item", 1, lint(ai, withLocator, str("いかがでしたか？", ["ListItem", "List"])).length);

// --- no fixer: every rewrite needs the sentence's meaning ---
t("no report carries a fix", 0,
  lint(ai, withLocator, str("重要なのは、時間を溶かさないことです。いかがでしたか？")).filter((r) => "fix" in r.error).length);

// --- state between nodes ---
t("each node is matched from its start", ["時間を溶かし", "時間を溶かし"], aiTexts("時間を溶かした。", "時間を溶かした。"));

// --- older textlint, without locator ---
t("without locator the index is passed", [6], lint(ai, null, str("手順は三つ。重要なのは、順番だ。")).map((r) => r.at));
t("the index skips the line break", [7], lint(ai, null, str("手順は三つ。\n重要なのは、順番だ。")).map((r) => r.at));

if (fails > 0) {
  console.log(`\n${fails} failure(s)`);
  process.exit(1);
}
console.log("PASS");
JS
