// ja-no-ai-phrase — 日本語の AI 生成文に特有の定型句と比喩動詞を報告する（自動修正はしない）。
//
// @textlint-ja/preset-ai-writing の no-ai-hype-expressions が拾う誇張語は、英語の
// 宣伝文句の訳語（ゲームチェンジャー、民主化する等）が中心で、日本語の AI 文に多い
// 「時間を溶かす」「側に倒す」「重要なのは、」「いかがでしたか」は一つも拾わない。
// その穴を埋めるため、yomiyasu の lint（scripts/yomiyasu_lint.py の
// METAPHOR_VERB_PATTERNS と FILLER_PATTERNS）から、語の形だけで決まり誤検知の少ない
// 型を移した。出典と許諾はファイル末尾。
//
// 移さなかったもの:
//   - 「効く」一般と「〜した瞬間」。yomiyasu は文脈の語（薬、冷房、時間の長さ等）で
//     字義どおりの用法を外しており、正規表現だけを写すと「キャッシュが効く」に当たる。
//     ここでは「地味に効く」「じわじわ効く」だけを置く
//   - 語だけの一覧（解像度、土台、実測など）。yomiyasu 自身が info の印として文脈で
//     判断させている語で、lint の指摘にすると正当な用法を大量に拾う
//
// ja-no-redundant-phrase と同じく、照合は Str ノード 1 つの中だけで行い、fix は
// 持たない。どの型も書き直しには文の意味が要り、文字列置換では作れない。
// 正当な用法（引用、この言い回しそのものの説明）は
// `<!-- textlint-disable ja-no-ai-phrase -->` で囲む。
"use strict";

const FIGURATIVE = "比喩動詞";
const FILLER = "定型句";

// どの型も文ごとに照合する。Str ノードは段落全体なので、段落のまま照合すると ^ と $ は
// 段落の頭と終わりにしか当たらない。文の頭か終わりに限る型（yomiyasu と同じ前置き・
// 結び）は、型の側の ^ と $ だけで示す。文の外へ出る型は無い（収斂も [^。！？!?] で
// 文の内側に留まる）ので、文の頭・終わりを問わない型も、段落で照合した場合と同じに当たる。
const PATTERNS = [
  // --- 比喩動詞・直訳（文のどこでも） ---
  {
    kind: FIGURATIVE,
    pattern: /(?:データ|仕様|設計|環境|ビルド|システム|秩序)が(?:静かに)?壊れ/gu,
    hint: "何がどうなるか（不整合が生じる、使えなくなる等）を書いてください",
  },
  {
    kind: FIGURATIVE,
    pattern: /静かに(?:壊れ|落ち|失敗|沈黙)/gu,
    hint: "silently fail の直訳です。気づかないうちに何が起きるかを書いてください",
  },
  {
    kind: FIGURATIVE,
    pattern: /黙って(?:無視|捨て|スキップ|破棄)/gu,
    hint: "直訳です。「通知なく」「エラーを出さずに」など、仕組みが分かる言い方にしてください",
  },
  { kind: FIGURATIVE, pattern: /側に倒[さしすせそ]/gu, hint: "「〜を優先する」「〜に統一する」など判断の中身を書いてください" },
  { kind: FIGURATIVE, pattern: /時間[をに]溶か[さしすせそ]/gu, hint: "「時間を費やす」「時間がかかる」と書いてください" },
  { kind: FIGURATIVE, pattern: /(?:1つずつ|一つずつ)潰[さしすせそ]/gu, hint: "「1つずつ直す」「解決する」と書いてください" },
  {
    kind: FIGURATIVE,
    pattern: /(?:実装|詳細|コード|設計|内部|仕組み|領域|本質)(?:に|まで|へ)踏み込[まみむめもん]/gu,
    hint: "「詳しく調べる」「〜まで説明する」など動作を書いてください",
  },
  { kind: FIGURATIVE, pattern: /動かしながら引き返[さしすせそ]/gu, hint: "何をどの状態へ戻すかを書いてください" },
  { kind: FIGURATIVE, pattern: /代わりに添え[たるて]/gu, hint: "何を何に付けるのか・渡すのかを書いてください" },
  {
    kind: FIGURATIVE,
    pattern: /(?:議論|意見|結論|方向性|価格|話題|検討)が[^。！？!?]*?収斂/gu,
    hint: "「落ち着いた」「決まった」と書いてください",
  },
  { kind: FIGURATIVE, pattern: /(?:前提|基盤)が崩れ[たるて]/gu, hint: "どの前提がどう成り立たなくなるかを書いてください" },
  { kind: FIGURATIVE, pattern: /(?:地味に|じわじわ)効[かきくけい]/gu, hint: "何がどう良くなるかを書いてください" },
  { kind: FIGURATIVE, pattern: /文化が醸成|プロセスが定着|事例が残した/gu, hint: "誰が何をするのかが分かる主語にしてください" },

  // --- 定型句（前置き・結び・自己ラベル）。位置を文の頭か終わりに限るのは ^ か $ を持つ型だけ ---
  { kind: FILLER, pattern: /^(?:まず|ここで)?(?:重要|大切|大事)なのは、?/gu, hint: "前置きを外し、述語で評価を述べてください" },
  { kind: FILLER, pattern: /^結論から(?:言|い)[ういえ]|^結論から申し上げ/gu, hint: "続く結論が具体的なら前置きは要りません" },
  { kind: FILLER, pattern: /^(?:正直に|本音を)言うと、?/gu, hint: "前置きを外してください" },
  { kind: FILLER, pattern: /^避けたいのは、?|^ポイントは、/gu, hint: "前置きを外し、述語で述べてください" },
  { kind: FILLER, pattern: /見落とされがち|面白いのはここ|まさにそこがポイント/gu, hint: "自己ラベルです。中身だけを書いてください" },
  { kind: FILLER, pattern: /いかがでした(?:でしょうか|か)?[？?。]?$/gu, hint: "意味を担わない結びです。削ってください" },
  {
    kind: FILLER,
    pattern: /ぜひ(?:参考にして|試して|活用して)(?:みて)?ください|参考に(?:なれ|な)ば幸い|お役に立て(?:れ)?ば幸い|ぜひご(?:活用|参考に)ください/gu,
    hint: "定型の結びです。書き手が実際に勧めている内容でなければ削ってください",
  },
  { kind: FILLER, pattern: /に(?:他|ほか)なりません/gu, hint: "「〜です」と言い切ってください" },
  {
    kind: FILLER,
    // 文末に限る。「〜と言っても過言ではありませんという言い方」のような言及は拾わない。
    pattern: /と(?:も)?(?:言|い)っても(?:過言|言い過ぎ|言いすぎ)(?:では(?:ありません|ない)|じゃ(?:ありません|ない))(?:です)?(?:でしょう|だろう|かもしれ(?:ません|ない)|と(?:思|おも)(?:います|う)|ね|よ)?(?=[。！？!?]?$)/gu,
    hint: "誇張の枠を外し、事実をそのまま書いてください",
  },
  { kind: FILLER, pattern: /^ご質問ありがとうございます/gu, hint: "チャット応答の名残です。文書の本文なら削ってください" },
  { kind: FILLER, pattern: /見ていきましょう[。！!]?$/gu, hint: "予告だけの文です。中身の文とまとめるか削ってください" },
  { kind: FILLER, pattern: /深掘りしていきます/gu, hint: "予告だけの文です。中身の文とまとめるか削ってください" },
  {
    kind: FILLER,
    pattern: /^(?:必要なら|ご希望があれば|よろしければ)、?(?:次に|続けて|この後(?!の))[^。！？!?]*(?:ます|ましょう)(?:か|よ|ね|よね)?[。！？!?]?$/gu,
    hint: "チャット応答の名残です。書き手が実際に申し出ているのでなければ削ってください",
  },
];

// 句点・感嘆符・疑問符までを 1 文とする。先頭の空白は文に含めない。
const SENTENCE = /[^。！？!?]+[。！？!?]*/gu;

// 引用・リンク文字列は書き手の文ではないので見ない。コードは Str にならない。
// ja-no-redundant-phrase.js に同じ一覧がある。変えるときは両方を変える。
const SKIP_PARENTS = new Set(["BlockQuote", "Link", "LinkReference", "Image"]);

function insideSkipped(node) {
  for (let p = node.parent; p; p = p.parent) {
    if (SKIP_PARENTS.has(p.type)) return true;
  }
  return false;
}

function sentences(text) {
  return [...text.matchAll(SENTENCE)].map((s) => {
    const lead = s[0].length - s[0].trimStart().length;
    return { start: s.index + lead, text: s[0].slice(lead) };
  });
}

// 型を外側、文を内側に回す。重なりの除外は先に出た当たりを残すので、この順が
// 「どの型の報告を残すか」を決める。
function* matches(text) {
  const all = sentences(text);
  for (const { kind, pattern, hint } of PATTERNS) {
    for (const s of all) {
      for (const m of s.text.matchAll(pattern)) yield { kind, hint, start: s.start + m.index, text: m[0] };
    }
  }
}

module.exports = function (context) {
  const { Syntax, RuleError, report, getSource, locator } = context;
  return {
    [Syntax.Str](node) {
      if (insideSkipped(node)) return;
      const text = getSource(node);
      // 「データが静かに壊れ」には型が 2 つ当たる。同じ箇所を 2 件と数えると、
      // 問題が 2 つあるように読めるので、先に当たった範囲と重なる当たりは捨てる。
      const taken = [];
      for (const m of matches(text)) {
        const range = [m.start, m.start + m.text.length];
        if (taken.some(([s, e]) => range[0] < e && s < range[1])) continue;
        taken.push(range);
        const message = `${m.kind}「${m.text}」: ${m.hint}。`;
        // locator は textlint 13 以降。無い版では旧来の index で位置を渡す。
        const where = locator ? { padding: locator.range(range) } : { index: m.start };
        report(node, new RuleError(message, where));
      }
    },
  };
};

// 型の出典: yomiyasu (https://github.com/nanaism/yomiyasu) scripts/yomiyasu_lint.py
//
// MIT License
//
// Copyright (c) 2026 nanaism
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
