# lib.sh — the fixture documents the review-design-doc eval cases share.
#
# One design doc -- automatic retries for webhook delivery -- written to be
# good by the standard the skill reviews against: a problem with numbers, goals
# and real non-goals, a proposal from overview to detail, alternatives that
# include doing nothing, drawbacks, cross-cutting concerns, dependencies whose
# owners agreed, open questions. A defect case swaps exactly one section for a
# flawed variant, so the case and clean-doc-no-false-p1 differ in that section
# alone and a finding can be traced to it.
#
# Two documents stand apart: an implementation manual (no decision in it at
# all) and a one-page mini doc for a small change, which leaves out sections
# that would not apply to it.
#
# The doc exists in Japanese and English; only the sections an English case
# uses are translated.
#
# Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

RDD_SECTIONS='header summary context goals proposal alternatives risks crosscutting dependencies open'

# rdd_write_doc <ja|en> <path> [<section>=<variant>...]
# Write the doc to <path>, each section in its base variant unless overridden.
# An override naming a section or variant that does not exist fails, rather
# than silently writing the clean doc under a defect case's name.
rdd_write_doc() {
  local lang="$1" path="$2" section variant override
  shift 2
  for override in "$@"; do
    section="${override%%=*}"
    case " $RDD_SECTIONS " in *" $section "*) ;; *)
      printf 'rdd_write_doc: no section %s\n' "$section" >&2
      return 1
      ;;
    esac
    if ! declare -F "_rdd_${lang}_${section}_${override#*=}" >/dev/null; then
      printf 'rdd_write_doc: no variant %s\n' "$override" >&2
      return 1
    fi
  done
  mkdir -p "$(dirname "$path")"
  {
    for section in $RDD_SECTIONS; do
      variant=base
      for override in "$@"; do
        case "$override" in "$section="*) variant="${override#*=}" ;; esac
      done
      "_rdd_${lang}_${section}_${variant}" || return 1
      printf '\n'
    done
  } >"$path"
}

# rdd_scaffold <ja|en> [<section>=<variant>...]
# The scaffold of every case that reviews the webhook doc: the doc at
# docs/design/webhook-retry.md, committed, so a clean tree afterwards means the
# run wrote nothing. Needs skill-eval-scaffold.sh sourced first.
rdd_scaffold() {
  local lang="$1"
  shift
  rdd_write_doc "$lang" docs/design/webhook-retry.md "$@" || return 1
  skill_eval_init_repo
}

# ============================================================
# Japanese
# ============================================================

_rdd_ja_header_base() {
  cat <<'PART'
# Webhook 配信の自動リトライ

- 著者: 配信チーム
- ステータス: レビュー依頼中（方針そのものへの意見が欲しい）
- 最終更新: 2026-10-20
PART
}

_rdd_ja_summary_base() {
  cat <<'PART'
## 概要

Webhook の配信が一時的に失敗したとき、今は再送せずに捨てている。これを、配信ごとの試行履歴を DB に記録し、指数バックオフで最大 24 時間・8 回まで再送する専用ワーカーに置き換える。一時的な失敗による未達を 0.8% から 0.1% 以下に下げるのが狙いで、配信順序の保証は扱わない。
PART
}

_rdd_ja_summary_vague() {
  cat <<'PART'
## 概要

Webhook の配信が一時的に失敗したとき、今は再送せずに捨てている。これを、配信ごとの試行履歴を DB に記録し、指数バックオフで再送する専用ワーカーに置き換える。未達を大幅に減らすのが狙いで、配信順序の保証は扱わない。
PART
}

_rdd_ja_context_base() {
  cat <<'PART'
## 背景

Webhook は 1 日あたり約 120 万件配信している。直近 30 日の失敗率は 0.8%（1 日約 9,600 件）で、失敗のうち 72% は 5xx かタイムアウトだった。配信ログで再送を模擬すると、その大半は同じ宛先へ 5 分以内に送り直せば成功していた。

今の配信ワーカーは失敗を記録するだけで再送しない。顧客は失敗に気付けず、「イベントが届かない」という問い合わせが月に約 30 件ある。うち 8 割はこの一時的な失敗が原因だった。

今やる理由: 来四半期に請求イベントの Webhook を公開する。請求イベントの取りこぼしは、顧客の会計処理に直接響く。
PART
}

_rdd_ja_context_vague() {
  cat <<'PART'
## 背景

Webhook は大量に配信していて、失敗もかなり多い。失敗の多くは一時的なもので、送り直せば成功するはずだ。

今の配信ワーカーは失敗を記録するだけで再送しない。顧客は失敗に気付けず、「イベントが届かない」という問い合わせも多い。

今やる理由: 来四半期に請求イベントの Webhook を公開する。請求イベントの取りこぼしは、顧客の会計処理に直接響く。
PART
}

_rdd_ja_goals_base() {
  cat <<'PART'
## ゴールと非ゴール

ゴール:

- 一時的な失敗（5xx・タイムアウト・接続エラー）による未達率を 0.1% 以下にする。配信ログで週次に測る。
- 再送を含めた配信の状況を、顧客ごとに運用担当が確認できるようにする。

非ゴール:

- 配信順序の保証。順序が必要な顧客には、イベントに含まれる発生時刻で並べ替えてもらう今の前提を維持する。
- exactly-once 配信。再送により重複は起こりうる。重複は冪等キーで顧客側が除く。
- 顧客が再送設定を変えられる管理画面。要望は聞いているが、本件の後に別途検討する。
PART
}

_rdd_ja_goals_negated() {
  cat <<'PART'
## ゴールと非ゴール

ゴール:

- 一時的な失敗（5xx・タイムアウト・接続エラー）による未達率を 0.1% 以下にする。配信ログで週次に測る。
- 再送を含めた配信の状況を、顧客ごとに運用担当が確認できるようにする。

非ゴール:

- 配信が失敗し続けること。
- システムが不安定になること。
- セキュリティを損なうこと。
PART
}

_rdd_ja_proposal_base() {
  cat <<'PART'
## 提案

### 全体像

配信ワーカーは失敗した配信を delivery_attempts テーブルに記録する。新設する再送ワーカーが 1 分ごとに再送時刻を過ぎた行を取り出して送り直す。8 回失敗した配信はデッドレター状態にして再送をやめ、運用担当が画面から確認できるようにする。

    [イベント発生] → [配信ワーカー] → 顧客エンドポイント
                         │ 失敗
                         ▼
                 delivery_attempts ← [再送ワーカー（1 分ごと）]

### 再送の規則

- 対象は 5xx、タイムアウト（10 秒）、接続エラー。4xx は顧客側の設定誤りとみなし再送しない。ただし 429 は再送の対象とし、Retry-After があればそれに従う。
- 間隔は 1 分を起点に倍々で伸ばし（1, 2, 4, … 分）、±20% のジッターを加える。1 回の間隔は 12 時間で頭打ちにし、8 回目がおよそ 24 時間後になる。
- 配信は at-least-once。各リクエストに配信ごとに一意な Idempotency-Key ヘッダを付け、再送でも同じ値を送る。

### データ

delivery_attempts には配信 ID、宛先、次回の再送時刻、試行回数、最後のステータスを持つ。ペイロード本体は既存のイベントストアを参照し、複製しない。
PART
}

_rdd_ja_proposal_hedged() {
  cat <<'PART'
## 提案

### 全体像

配信ワーカーは失敗した配信を delivery_attempts テーブルに記録する。新設する再送ワーカーが 1 分ごとに再送時刻を過ぎた行を取り出して送り直す。何度か失敗した配信はデッドレター状態にして再送をやめ、運用担当が画面から確認できるようにする。

    [イベント発生] → [配信ワーカー] → 顧客エンドポイント
                         │ 失敗
                         ▼
                 delivery_attempts ← [再送ワーカー（1 分ごと）]

### 再送の規則

- 対象は 5xx、タイムアウト、接続エラー。4xx を再送するかはまだ決めていない。
- 間隔は TBD（おそらく指数バックオフ）。上限の回数も未定。
- 配信は at-least-once。各リクエストに配信ごとに一意な Idempotency-Key ヘッダを付け、再送でも同じ値を送る。

### データ

delivery_attempts には配信 ID、宛先、次回の再送時刻、試行回数、最後のステータスを持つ。ペイロード本体を複製するかどうかは、実装しながら決める。
PART
}

_rdd_ja_alternatives_base() {
  cat <<'PART'
## 検討した代替案

### 何もしない（顧客にポーリング API を案内する）

開発コストはかからない。しかし顧客は失敗に気付く手段がなく、請求イベントでは取りこぼしが会計の不一致になる。問い合わせ対応の工数（月 30 件、1 件平均 40 分）も残る。

### 既存のジョブ基盤（Sidekiq）の自動リトライに任せる

実装は数行で済む。一方で再送の状態がジョブのキューにしか残らず、顧客ごとの配信状況を見せるというゴールを満たせない。リトライの間隔も Sidekiq の既定（最長 21 日）に縛られ、上限を 24 時間にするには結局独自の管理が要る。

### マネージドキュー（SQS）の遅延配信を使う

キューの運用を任せられる。ただし遅延は最大 15 分で、24 時間に及ぶバックオフには再投入を繰り返す仕組みが要る。配信基盤はオンプレミスの DB に閉じており、新たにクラウドへの依存を足すコストに見合わないと判断した。

提案した方式は、DB に状態を持つ分だけ実装量が最も多い。それでも、配信状況を顧客ごとに見せられるのはこの方式だけなので選んだ。
PART
}

_rdd_ja_alternatives_strawman() {
  cat <<'PART'
## 検討した代替案

- Kafka を導入する案: 大がかりすぎるので採用しない。
- 運用担当が手で再送する案: 現実的でないので採用しない。

以上から、提案の方式が最適である。
PART
}

_rdd_ja_risks_base() {
  cat <<'PART'
## 欠点とリスク

- DB への書き込みが増える。失敗 1 件につき最大 8 回の更新で、1 日あたり最大約 8 万件。今の書き込み量（1 日約 400 万件）の 2% にあたる。
- 顧客の受信側が長く落ちていると、復旧直後に再送が集中する。ジッターに加えて、宛先ごとの同時再送数を 5 に制限する。
- at-least-once のため重複が起きる。冪等キーを使っていない顧客は、重複したイベントをそのまま処理してしまう。公開ドキュメントで冪等キーの使い方を案内する。
PART
}

_rdd_ja_risks_vague() {
  cat <<'PART'
## 欠点とリスク

- DB への書き込みは増えるが、負荷は十分に小さい。
- 顧客の受信側が長く落ちていると、復旧直後に再送が集中する。ジッターに加えて、宛先ごとの同時再送数を制限する。
- at-least-once のため重複が起きる。冪等キーを使っていない顧客は、重複したイベントをそのまま処理してしまう。公開ドキュメントで冪等キーの使い方を案内する。
PART
}

_rdd_ja_crosscutting_base() {
  cat <<'PART'
## 横断的な考慮事項

### セキュリティ

再送でも署名（HMAC-SHA256）とタイムスタンプは送るたびに作り直す。古いタイムスタンプのまま送ると、顧客側のリプレイ対策で拒否されるため。

### プライバシー

ペイロードは複製しないので、保持期間は既存のイベントストア（30 日）のまま変わらない。

### 可観測性

再送回数、デッドレター件数、再送の成功率をメトリクスとして出す。デッドレターが 1 時間に 100 件を超えたら当番に通知する。

### ロールアウトとロールバック

顧客単位のフィーチャーフラグで、社内アカウント → 顧客の 5% → 50% → 全体と 1 週間ずつ広げる。問題があればフラグを切れば、すぐに今の挙動（再送しない）に戻る。delivery_attempts に溜まった行は残し、再開時にそのまま使う。
PART
}

_rdd_ja_crosscutting_norollback() {
  cat <<'PART'
## 横断的な考慮事項

### セキュリティ

再送でも署名（HMAC-SHA256）とタイムスタンプは送るたびに作り直す。古いタイムスタンプのまま送ると、顧客側のリプレイ対策で拒否されるため。

### プライバシー

ペイロードは複製しないので、保持期間は既存のイベントストア（30 日）のまま変わらない。

### 可観測性

再送回数、デッドレター件数、再送の成功率をメトリクスとして出す。デッドレターが 1 時間に 100 件を超えたら当番に通知する。

### リリース

リリース日に全顧客へ一斉に適用する。
PART
}

_rdd_ja_dependencies_base() {
  cat <<'PART'
## 依存関係

- イベントストア（自チームの所有）: ペイロードの参照に使う。変更はない。
- 共有 DB（基盤チームの所有）: 新しいテーブルを置く。書き込み量の見積もりを基盤チームに共有し、今の容量の範囲内であることを 10 月 1 日に確認してもらった。
PART
}

_rdd_ja_dependencies_unconfirmed() {
  cat <<'PART'
## 依存関係

- イベントストア（自チームの所有）: ペイロードの参照に使う。変更はない。
- 共有 DB（基盤チームの所有）: 新しいテーブルを置く。書き込みが増えるので、基盤チームにインスタンスを一段大きくしてもらう。
PART
}

_rdd_ja_open_base() {
  cat <<'PART'
## 未解決の問題

- デッドレターになった配信を、運用担当が画面から再送できるようにするか。本件に含めるか後続にするかを決めたい。
- 8 回・24 時間という上限で足りるか。請求イベントだけ長くする必要があるか、経理系の顧客 3 社に確認している。
PART
}

_rdd_ja_open_none() {
  cat <<'PART'
## 未解決の問題

特になし。
PART
}

# A doc with no decision in it: steps and code, no problem, no alternative, no
# trade-off. Google's test: if a design doc reads like this, writing the code
# would have been the better use of the time.
rdd_write_manual_ja() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<'DOC'
# Webhook 配信の自動リトライ

- 著者: 配信チーム
- ステータス: レビュー依頼中

## 手順

1. マイグレーションを追加する。

        CREATE TABLE delivery_attempts (
          delivery_id BIGINT PRIMARY KEY,
          endpoint TEXT NOT NULL,
          next_attempt_at TIMESTAMP NOT NULL,
          attempts INT NOT NULL DEFAULT 0,
          last_status INT
        );

2. 配信ワーカーの失敗時の処理に、次のコードを足す。

        rescue DeliveryError => e
          DeliveryAttempt.create!(delivery_id: d.id, endpoint: d.url,
            next_attempt_at: 1.minute.from_now, attempts: 1, last_status: e.status)

3. RetryWorker を作り、1 分ごとに実行する。

        class RetryWorker
          def perform
            DeliveryAttempt.where("next_attempt_at < ?", Time.now).find_each do |a|
              Deliverer.new(a).call
            end
          end
        end

4. 間隔は attempts に応じて 2 ** attempts 分にする。
5. 8 回失敗したら status を dead にする。
6. デプロイする。
DOC
}

# A one-page doc for a small, easily reverted change. It has no goals section,
# no security or privacy section, no milestones and no monitoring plan, and
# needs none of them: what could go wrong is named, with how to undo it.
rdd_write_mini_ja() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<'DOC'
# 料金表キャッシュの TTL を 5 分から 1 時間に延ばす

- 著者: 料金チーム
- ステータス: レビュー依頼中（この変更で問題ないかだけ見てほしい）

## 概要と背景

料金表 API の応答は CDN で 5 分キャッシュしている。料金表は月に 1〜2 回、管理画面からの更新でしか変わらない。それなのにキャッシュが切れるたびにオリジンへ問い合わせが飛び、1 時間あたり約 2,400 件、オリジン側の負荷の 15% を占めている。

TTL を 1 時間に延ばす。料金表を更新したときは、管理画面の保存処理から CDN のパージ API を呼んで、すぐに反映させる。

## 検討した代替案

- TTL を 1 日にする: 問い合わせはさらに減るが、パージに失敗したとき古い料金が最大 1 日残る。1 時間なら許容できることを営業部門と確認した。
- 何もしない: 今のところ負荷は問題になっていない。ただ来月のキャンペーンで料金表へのアクセスが 3 倍になる見込みで、そのときはオリジンの増強が要る。

## リスク

パージ API の呼び出しが失敗すると、古い料金が最大 1 時間表示される。保存処理はパージの失敗を画面に出し、手動でのパージを促す。戻すときは TTL の設定値を 5 分に戻すだけでよい。
DOC
}

# The discussion notes the proactive case asks the agent to turn into a doc.
rdd_write_notes_ja() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<'DOC'
# Webhook リトライ 議論メモ（10/15）

- 1 日 120 万件配信、失敗率 0.8%。失敗の 72% は 5xx かタイムアウト、5 分以内に送り直せばほぼ成功
- 「届かない」問い合わせ月 30 件、8 割が一時的な失敗
- 来四半期に請求イベントの Webhook を出すので、それまでに再送を入れたい
- 案: 失敗を delivery_attempts テーブルに記録 → 再送ワーカーが 1 分ごとに拾う
- 指数バックオフ 1 分起点、ジッター ±20%、最大 8 回 / 24 時間、超えたらデッドレター
- 4xx は再送しない、429 は Retry-After に従う
- at-least-once、Idempotency-Key ヘッダを再送でも同じ値で
- Sidekiq のリトライ: 楽だが顧客ごとの状況が見えない → 却下
- SQS の遅延配信: 最大 15 分、オンプレに閉じている → 却下
- 何もしない: 請求イベントで会計がずれる → 却下
- 署名とタイムスタンプは送るたびに作り直す
- フィーチャーフラグで 5% → 50% → 全体。フラグを切れば元に戻る
- 未決: デッドレターの手動再送 UI を入れるか
DOC
}

# ============================================================
# English
# ============================================================

_rdd_en_header_base() {
  cat <<'PART'
# Automatic retries for webhook delivery

- Author: Delivery team
- Status: In review (looking for feedback on the approach itself)
- Last updated: 2026-10-20
PART
}

_rdd_en_summary_base() {
  cat <<'PART'
## Summary

When a webhook delivery fails transiently, we drop it today. This replaces that with a dedicated worker that records each delivery's attempts in the database and retries with exponential backoff, up to 8 times over 24 hours. The aim is to bring undelivered events caused by transient failures from 0.8% down to 0.1% or less. Delivery order is out of scope.
PART
}

_rdd_en_context_base() {
  cat <<'PART'
## Context

We deliver about 1.2 million webhooks a day. Over the last 30 days the failure rate was 0.8% (about 9,600 a day), and 72% of the failures were 5xx responses or timeouts. Replaying the delivery log shows that most of them would have succeeded if resent to the same endpoint within 5 minutes.

The current delivery worker records a failure and never retries. Customers cannot tell an event was lost, and we get about 30 "events are not arriving" tickets a month, 80% of them caused by these transient failures.

Why now: next quarter we publish webhooks for billing events, and a lost billing event goes straight into a customer's accounting.
PART
}

_rdd_en_goals_base() {
  cat <<'PART'
## Goals and non-goals

Goals:

- Bring the rate of events left undelivered by transient failures (5xx, timeouts, connection errors) to 0.1% or less, measured weekly from the delivery log.
- Let the operations team see, per customer, the state of every delivery including its retries.

Non-goals:

- Ordering guarantees. Customers who need order keep sorting by the event's timestamp, as they do today.
- Exactly-once delivery. Retries can duplicate an event; customers drop duplicates by the idempotency key.
- A settings page where customers tune retries. It has been asked for, and will be considered separately after this.
PART
}

_rdd_en_proposal_base() {
  cat <<'PART'
## Proposal

### Overview

The delivery worker records a failed delivery in a delivery_attempts table. A new retry worker picks up rows whose retry time has passed, once a minute, and sends them again. A delivery that fails 8 times is moved to a dead-letter state and no longer retried; the operations team can see it on a dashboard.

    [event] → [delivery worker] → customer endpoint
                   │ failure
                   ▼
           delivery_attempts ← [retry worker (every minute)]

### Retry rules

- Retried: 5xx, timeouts (10 seconds), connection errors. A 4xx is taken as a misconfiguration on the customer's side and not retried, except 429, which is retried and honours Retry-After when present.
- The interval starts at 1 minute and doubles (1, 2, 4, … minutes), with ±20% jitter. A single interval is capped at 12 hours, so the 8th attempt falls about 24 hours after the first.
- Delivery is at-least-once. Each request carries an Idempotency-Key header unique to the delivery, and a retry sends the same value.

### Data

delivery_attempts holds the delivery ID, the endpoint, the next retry time, the attempt count and the last status. The payload itself stays in the existing event store and is not copied.
PART
}

_rdd_en_alternatives_base() {
  cat <<'PART'
## Alternatives considered

### Do nothing (point customers to the polling API)

Costs no development. But customers have no way to notice a failure, and for billing events a lost event becomes an accounting mismatch. The support cost stays too: 30 tickets a month at about 40 minutes each.

### Leave it to the job system's retries (Sidekiq)

A few lines of code. But the retry state lives only in the job queue, so we cannot show delivery state per customer, which is a goal. The intervals are also bound to Sidekiq's defaults (up to 21 days), and capping them at 24 hours needs our own bookkeeping anyway.

### Use a managed queue's delayed delivery (SQS)

The queue is operated for us. But the delay is at most 15 minutes, so a backoff spanning 24 hours needs repeated re-enqueueing. Our delivery stack is confined to an on-premises database, and adding a cloud dependency was judged not worth that cost.

The proposed approach is the most code, since it keeps state in the database. It is the only one that can show delivery state per customer, which is why it was chosen.
PART
}

_rdd_en_risks_base() {
  cat <<'PART'
## Drawbacks and risks

- More database writes: up to 8 updates per failure, at most about 80,000 a day, which is 2% of today's write volume (about 4 million a day).
- When a customer's receiver is down for a long time, retries pile up right after it recovers. Besides the jitter, concurrent retries per endpoint are capped at 5.
- At-least-once means duplicates. A customer not using the idempotency key will process a duplicated event twice. The public docs will explain how to use the key.
PART
}

_rdd_en_crosscutting_base() {
  cat <<'PART'
## Cross-cutting concerns

### Security

Every retry re-signs the request (HMAC-SHA256) with a fresh timestamp. Resending the old timestamp would be rejected by the customer's replay protection.

### Privacy

The payload is not copied, so its retention stays that of the existing event store (30 days).

### Observability

Retry count, dead-letter count and retry success rate are exported as metrics. More than 100 dead letters in an hour pages the on-call engineer.

### Rollout and rollback

A per-customer feature flag widens the rollout a week at a time: internal accounts, then 5% of customers, 50%, everyone. Turning the flag off returns to today's behaviour (no retries) at once. Rows already in delivery_attempts are kept and used again when the flag comes back on.
PART
}

_rdd_en_crosscutting_norollback() {
  cat <<'PART'
## Cross-cutting concerns

### Security

Every retry re-signs the request (HMAC-SHA256) with a fresh timestamp. Resending the old timestamp would be rejected by the customer's replay protection.

### Privacy

The payload is not copied, so its retention stays that of the existing event store (30 days).

### Observability

Retry count, dead-letter count and retry success rate are exported as metrics. More than 100 dead letters in an hour pages the on-call engineer.

### Release

It goes live for every customer at once on release day.
PART
}

_rdd_en_dependencies_base() {
  cat <<'PART'
## Dependencies

- Event store (owned by us): read for payloads. No change to it.
- Shared database (owned by the platform team): hosts the new table. We shared the write estimate with the platform team, who confirmed on October 1 that it fits the current capacity.
PART
}

_rdd_en_open_base() {
  cat <<'PART'
## Open questions

- Should the operations team be able to resend a dead-lettered delivery from the dashboard? We need to decide whether that is part of this or a follow-up.
- Are 8 attempts over 24 hours enough? We are asking three customers in accounting whether billing events need a longer window.
PART
}

# ============================================================
# Other fixtures
# ============================================================

# A small shell module with no design doc behind it, for the case that asks
# for a review of code design: the doc in docs/design/ is a distractor.
rdd_write_slug_module() {
  mkdir -p lib
  cat >lib/slug.sh <<'CODE'
# slug.sh -- turn a title into a URL slug.
#
# shellcheck shell=bash

# slugify <title>
# Print <title> lower-cased, with every run of characters other than a-z and
# 0-9 replaced by a single "-", and no "-" at either end.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}
CODE
}
