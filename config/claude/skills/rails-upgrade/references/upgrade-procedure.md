# Rails アップグレード詳細手順

公式ガイド（https://railsguides.jp/upgrading_ruby_on_rails.html）と実践記事
（https://qiita.com/jnchito/items/0ee47108972a0e302caf）を統合した、抜け漏れのない
チェックリスト。各ステップはこの順序で実施する。

## ステップ -1: 実行環境（コマンドランナー）の検出 ← 最初に必ず行う

`bundle` / `bin/rails` をホストで直接実行できるとは限らない。多くのプロジェクトは Docker や
各種ラッパ経由でしか動かず、gem がホスト未インストールだと `bundle exec` は
`Bundler::GemNotFound` で即失敗する。**何よりも先に実行環境を検出し、以降の全コマンドを
そのランナー経由で実行する。** ここを飛ばすと手順全体が最初のコマンドで詰まる。

検出の手がかり（上から優先）:

1. **`Makefile`** に `docker compose exec ... bundle`/`rspec`/`rails` を包んだターゲットがある
   → `make test` `make console` `make rubocop` などの既存ターゲットを最優先で使う
   （プロジェクトが意図した正規の実行経路）。`make help` でターゲット一覧を確認できる。
2. **compose 定義**（`compose.yml`/`compose.yaml`/`docker-compose.yml`）に app 系サービスがある
   → `docker compose exec -T <service> <cmd>`。**非対話実行では `-T` が必須**（TTY 無効化）。
   先に `docker compose ps` で稼働を確認し、停止していれば `docker compose up -d`。
3. **`bin/` ラッパ**（`bin/rails` 等）が環境を吸収するなら、そのまま利用。
4. いずれも無ければホストで直接 `bundle`/`bin/rails` を実行。

**以降の本文中のコマンド例はネイティブ表記（`bundle exec ...`）で書く。実環境では先頭に検出した
ランナー（例: `docker compose exec -T app`）を前置すること。** 本文ではこれを `RUN` と表記する。

環境変数を渡すコマンド（`RUBYOPT=-W:deprecated` など）の注意:
- ホストの `VAR=値 cmd` プレフィックスは**コンテナには伝わらない**。
  Docker では `docker compose exec -T -e RUBYOPT=-W:deprecated app bundle exec rspec` と `-e` で渡す。

## 大原則

- **1ステップずつ上げる。** バージョンを飛ばさない（例: 5.0 → 6.0 ではなく 5.0 → 5.1 → 5.2 → 6.0）。
  マイナー間でも public API の破壊的変更が起こりうる。
- **まず現行マイナーの最新パッチへ。** 目的バージョンへ上げる前に、現行マイナー系列の
  最新パッチに移動し、テストを通しておく。
- **Ruby と Rails は別々に上げる。** 先に Ruby を必要バージョンへ、その後 Rails を上げる。
- **コミットを細かく分ける。** 「周辺gem更新」「Ruby更新」「Railsパッチ更新」「Railsバージョン更新」
  「app:update差分」「new_framework_defaults有効化」などを別コミットにし、後から差分を追える状態にする。

## ステップ 0: 事前準備

1. アップグレード用ブランチを作成する（例: `git checkout -b rails-8-1-upgrade`）。
2. テストカバレッジを確認する。カバレッジが薄い領域は手動確認の対象としてメモするか、テストを追加する。
3. ベースラインのテストを deprecation 警告つきで実行し、現状の警告を把握する。
   - RSpec: `RUBYOPT=-W:deprecated bundle exec rspec`（Docker: `RUN -e RUBYOPT=-W:deprecated <service> bundle exec rspec`）
   - minitest: `RUBYOPT=-W:deprecated bin/rails test`
   - **structured logger（rails_semantic_logger 等）でログが大量に出る場合は、出力をファイルに退避して
     抽出する。** 警告がログノイズに埋もれて見落とすのを防ぐ:
     `... bundle exec rspec > /tmp/baseline.log 2>&1; grep -c "DEPRECATION WARNING" /tmp/baseline.log`
     さらに `grep "DEPRECATION WARNING" /tmp/baseline.log | sort -u` で種類を一覧化する。
   - テスト本数・成否（例: `N examples, 0 failures`）と警告件数を**数値で記録**しておく。
     アップグレード後に同じ数値を取り、差分（増えた警告・新たな失敗）だけを対象にする。

## ステップ 1: 周辺 gem の整理（Rails を上げる前）

1. `bundle outdated` で更新可能な gem と、最新版に未対応の gem を把握する。
2. 安全な側から段階的に更新する: `bundle update -g development -g test`。
3. メジャーバージョンが上がる gem は **1つずつ** 更新し、各ステップでテストを実行する。
   更新前にその gem の CHANGELOG で破壊的変更を確認する。
4. 最後に `bundle update` で残りを更新する。
5. 区切りごとにコミットする。

## ステップ 2: Ruby のアップグレード（必要な場合）

1. 目的の Rails が要求する Ruby バージョンを確認する（`version-requirements` セクション参照）。
2. 現行 Ruby が満たしていれば、このステップはスキップ。
3. 不足していれば Ruby を先に上げる:
   - バージョン管理ファイルを更新（`.ruby-version` / `rbenv local X.Y.Z` など）。
   - `bundle install` を実行。
   - `RUBYOPT=-W:deprecated` 付きでテストを実行し、Ruby 起因の警告・エラーを潰す。
4. 別コミットにする。

## ステップ 3: 現行マイナーの最新パッチへ

1. `gem 'rails', '<現行マイナーの最新パッチ>'` に変更（例: 5.2.1 → 5.2.3）。
   - 算出スクリプトの `current_latest_patch` を使う。
2. `bundle update rails` を実行。
3. テストを実行して通す。
4. コミットする。

## ステップ 4: 目的バージョンへ上げる

1. Gemfile を編集する。
   - **原則としてバージョンを固定しない**（後のアップデートを容易にするため）。
     固定する特別な理由がある場合は、コメントで理由（issue の URL など）を残す。
   - 目的バージョンへ更新（例: `gem 'rails', '~> 8.1.0'` あるいは固定が必要なら `'8.1.3'`）。
2. `bundle update rails` を実行（依存解決でエラーが出たら、原因 gem を特定して個別対応）。
3. JS パッケージを使っている場合は対応する Rails JS パッケージも更新する。
   - `jsbundling-rails` 利用時: `bin/rails javascript:install` など。
   - `package.json` の `@rails/*` のバージョンを Rails に合わせる。

## ステップ 5: `bin/rails app:update`（対話的）

新しいアプリ構造に合わせて設定ファイルを更新する。**既存ファイルに差分があると対話的に
上書き確認が出る。** 対話で手作業すると `n`（残す）を選ぶ場面がほとんどなので、自動化時は
**全件 `n`（既存を残す）で流し、あとから差分をレビューする**のが安全で確実。

```bash
# ネイティブ
bin/rails app:update
# 非対話で「既存ファイルは一切上書きしない」（新規ファイルだけ生成される）
yes n | bin/rails app:update
# Docker（-T で非TTY。これをしないとプロンプトでハングする）
yes n | docker compose exec -T <service> bin/rails app:update
```

対話で手作業する場合の各選択肢:
- `Y` … 上書きする / `n` … 上書きしない / `a` … 以降すべて上書き / `q` … 中断
- `d` … 差分を表示（**判断に迷ったら必ず d で差分確認**）
- `THOR_DIFF` / `THOR_MERGE` 環境変数で diff/merge ツールを指定できる。

**app:update 後は必ず 2 種類の差分をレビューする**（`git status` で全体を俯瞰）:

1. **上書き衝突（conflict）した既存ファイル**
   - `yes n` で残した場合、新デフォルトに必要な設定変更が**反映されていない**可能性がある。
     生成側との差分を `git diff`／`bin/rails app:update` の `d` で確認し、必要な変更だけ手で取り込む。
   - 逆に `Y` で上書きしてしまい独自設定（initializer・puma・environments 等）が消えたら git で復元。

2. **新規生成（create）されたファイル ← 見落とし注意**
   - app:update は衝突しない新規ファイルを**プロンプト無しで生成する**（`yes n` でも生成される）。
     `git status` の untracked に現れる。
   - これらは**そのプロジェクトに不要な opt-in スキャフォールドのことがある**。例: Rails 8.1 は
     `config/ci.rb` + `bin/ci`（`ActiveSupport::ContinuousIntegration`）を生成するが、中身は
     `bin/rails test` 前提で、**RSpec 採用や独自 CI（Makefile 等）を持つプロジェクトには合わない**。
   - 各新規ファイルが「本当に必要か・既存ツールと競合しないか」を確認し、不要なら削除する
     （**このスキルの停止ポイント。採否はユーザーに確認する**）。
   - 例外として `config/initializers/new_framework_defaults_X_Y.rb` は**必須の成果物**。次のステップで使う。

- `http://railsdiff.org` で「そのバージョン間で新規追加・変更された設定ファイルや gem」を確認できる。
- `app:update` 末尾で `active_storage:update` 等が走り、新規マイグレーションが生成されることがある。
  `git status` の `db/migrate/` を確認し、生成されていれば内容を読んでから `RUN bin/rails db:migrate`。

## ステップ 6: `new_framework_defaults_X_Y.rb` の段階的有効化

`app:update` で `config/initializers/new_framework_defaults_X_Y.rb` が生成される
（X_Y は目的バージョン）。これは新デフォルトをコメントアウト状態で列挙したファイル。

1. **いきなり全部有効化しない。** コメントを1つずつ（または数個ずつ）外し、その都度テスト・動作確認する。
2. この作業は複数回のデプロイに分割できる。各段階で本番含め動作確認しながら進められる。
3. すべての項目を有効化し、動作確認が取れるまでは `config.load_defaults` は **まだ上げない**。

## ステップ 7: `config.load_defaults` の切り替え

新デフォルトすべてで問題なく動くことを確認できたら:

1. `config/application.rb` の `config.load_defaults` を目的バージョンに変更。
2. `config/initializers/new_framework_defaults_X_Y.rb` を削除。
3. テストを実行して通す。
4. コミットする。

## ステップ 8: deprecation 警告の解消

1. `RUBYOPT=-W:deprecated` 付きでテストを実行し、DEPRECATION WARNING を洗い出す。
2. 警告メッセージの「詳細ページ URL」と「該当行番号」をまず読む。
3. ステップ0で把握した「元からあった警告」と切り分け、**今回増えた警告を優先して潰す**。
4. 次のバージョンで削除される API は今のうちに置き換える。

## ステップ 9: gem 互換性の確認

目的バージョンで非互換になりやすい gem に注意する:

- `spring`: Rails 7.0+ では 3.0.0 以上が必要。
- `sprockets-rails`: Rails 7.0 で任意化。必要なら Gemfile に明示追加。
- Active Storage 利用時: `image_processing` gem が必須になる場合あり。
- その他、`bundle outdated` と各 gem の CHANGELOG で破壊的変更を確認する。

## ステップ 10: 動作確認

1. コンソール: `bin/rails console` で `User.count` など基本操作を確認。
2. サーバー: `bin/rails server` を起動し、主要画面を複数開いて確認。
3. テスト全実行: `bundle exec rspec` / `bin/rails test`（Rails 7.1+ は実行前に `test:prepare` が走る）。
4. 手動確認: デザイン崩れ・複雑な機能・外部連携（S3 / 外部 API など）を目視確認。

## ステップ 11: コミット・PR 作成・デプロイ（ユーザー承認のうえで）

コミット・push・PR 作成・デプロイは**外部に影響する操作**。**必ずユーザーの承認を得てから実行する**
（このスキルの停止ポイント）。承認が得られたら、以下を順に実行する。

1. **コミット**（大原則どおり粒度を分ける）。
   - プロジェクトに**コミット規約**（メッセージ形式、`/commit` のようなスラッシュコマンド、
     CONTRIBUTING 等）があれば必ずそれに従う。無ければ
     `feat: Upgrade Rails from X.Y to X.(Y+1)` のような簡潔な形式にする。
   - 分割例: 「周辺gem更新」「Railsバージョン更新（Gemfile/Gemfile.lock）」「app:update 差分」
     「load_defaults 切替」。各コミットでテストが通る状態にしておく。
2. **PR 作成**。
   - プロジェクトに**PR 規約**（`/create-pr` のようなコマンド、PR テンプレート、宛先ブランチ）が
     あれば従う。無ければ `gh pr create` 等で作成する。
   - 本文には最低限「概要／変更内容／確認内容」を含める。**確認内容**にはステップ 10 で取った
     検証結果（テスト本数・`0 failures`・新規 deprecation 件数・`zeitwerk:check` 等）を数値で書く。
   - 関連 Issue があれば紐付ける。
3. **デプロイ**（同じく承認のうえで）。
   - ステージング環境へデプロイし、外部連携を含めて数日監視する。
   - 本番デプロイ後も数日はログ・リソースを監視する。

## version-requirements（Rails が要求する最小 Ruby）

| Rails | 最小 Ruby |
|-------|-----------|
| 8.1   | 3.2.0     |
| 8.0   | 3.2.0     |
| 7.2   | 3.1.0     |
| 7.1   | 2.7.0     |
| 7.0   | 2.7.0     |
| 6.1   | 2.5.0     |
| 6.0   | 2.5.0     |
| 5.2   | 2.2.2     |

表にないバージョンや最新情報は必ず公式ガイドで確認する。
