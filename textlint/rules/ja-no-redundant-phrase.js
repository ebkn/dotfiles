// ja-no-redundant-phrase — 冗長表現を報告する（自動修正はしない）。
//
// textlint-rule-ja-no-redundant-expression の代わりに置く。あちらは段落・箇条書きの
// 境界をまたいでテキストを連結して照合するため、存在しない文字列にマッチし、--fix が
// 無関係な語の途中を書き換える（textlintrc.yml の無効化コメントに再現手順がある）。
// ここでは次の 2 点でその壊れ方を構造的に避ける。
//   - 照合は Str ノード 1 つの中だけで行う。境界をまたぐ連結をしないので、
//     ソースに無い文字列には当たらない
//   - fix を持たない。「読み込むことができる」→「読み込める」のような書き換えは
//     動詞の活用に依存し、文字列置換では正しく作れない。直すのは人である
//
// 一覧は網羅を目指さない。AI 生成文で繰り返し見つかり、かつ省いても意味が変わらない
// ことの多い型だけを置く。正当な用法（引用・強調の意図があるもの）は
// `<!-- textlint-disable ja-no-redundant-phrase -->` で囲む。
"use strict";

const PATTERNS = [
  {
    pattern: /(?:する)?ことができ/g,
    message: "「〜ことができる」は冗長です。「〜できる」「〜（ら）れる」で足ります（例: 読み込むことができる → 読み込める）。",
  },
  {
    pattern: /(?:する)?ことが可能/g,
    message: "「〜ことが可能」は冗長です。「〜できる」で足ります。",
  },
  {
    // 漢語・カタカナ語に続く「を行う」。「設定を行う」→「設定する」
    pattern: /(?<=[\p{Script=Han}\p{Script=Katakana}ー])を行(?:う|い|っ|わ|え|お)/gu,
    message: "「〈名詞〉を行う」は冗長です。「〈名詞〉する」で足ります（例: 設定を行う → 設定する）。",
  },
  {
    pattern: /(?<=[\p{Script=Han}\p{Script=Katakana}ー])を実施(?:する|し|され|でき)/gu,
    message: "「〈名詞〉を実施する」は冗長です。「〈名詞〉する」で足ります。",
  },
];

// 引用・リンク文字列は書き手の文ではないので見ない。コードは Str にならない。
const SKIP_PARENTS = new Set(["BlockQuote", "Link", "LinkReference", "Image"]);

function insideSkipped(node) {
  for (let p = node.parent; p; p = p.parent) {
    if (SKIP_PARENTS.has(p.type)) return true;
  }
  return false;
}

module.exports = function (context) {
  const { Syntax, RuleError, report, getSource, locator } = context;
  return {
    [Syntax.Str](node) {
      if (insideSkipped(node)) return;
      const text = getSource(node);
      for (const { pattern, message } of PATTERNS) {
        pattern.lastIndex = 0;
        for (const m of text.matchAll(pattern)) {
          const range = [m.index, m.index + m[0].length];
          // locator は textlint 13 以降。無い版では旧来の index で位置を渡す。
          const where = locator ? { padding: locator.range(range) } : { index: m.index };
          report(node, new RuleError(message, where));
        }
      }
    },
  };
};
