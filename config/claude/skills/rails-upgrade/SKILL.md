---
name: rails-upgrade
description: Upgrades the Ruby on Rails version of a Rails project by exactly one step, following the official upgrade guide. This skill should be used when the user asks to upgrade, bump, or update Rails (the rails gem / framework version) in a Rails project — e.g. "Railsを上げて", "upgrade Rails", "Railsのバージョンアップ". It detects the current version from Gemfile.lock, computes the next target (next minor, or next major .0 if no newer minor, always the latest patch), and runs the mechanical upgrade steps while pausing for human judgment on deprecation fixes and risky overwrites.
---

# Rails Upgrade

## Overview

このスキルは Rails プロジェクトの Rails バージョンを **1ステップだけ** 安全に上げる。
現行バージョンを検出し、ターゲットバージョンを決定論的に算出したうえで、公式アップグレード
ガイドに沿った手順を抜け漏れなく実行する。機械的な作業（Gemfile 編集・`bundle update`・
`bin/rails app:update`・テスト実行）は自動で進め、判断が必要な箇所では停止してユーザーに確認する。

## バージョン選定ポリシー（このスキルの核）

現行バージョン `X.Y.Z` に対し、ターゲットは次のルールで決める:

1. **次のマイナーが存在すれば、マイナーを1つだけ上げる**（`X.Y` → `X.(Y+1)`）。
   いくつ先のマイナーがあっても、必ず1つだけ。
2. **次のマイナーが存在しなければ、メジャーを1つ上げ、マイナーは 0 から**（`(X+1).0`）。
3. **パッチは常にそのターゲットマイナー系列の最新**にする。

加えて、ターゲットへ上げる前に **現行マイナー系列の最新パッチへ先に移動する**（Rails 推奨）。
この算出は `scripts/select_rails_version.py` が行う。手で判断しない。

## ワークフロー

### ステップ 0: 実行環境（コマンドランナー）を検出する ← 最初に行う

`bundle` / `bin/rails` をホストで直接実行できるとは限らない。Docker などラッパ経由でしか
動かないプロジェクトでは、ホストで `bundle exec` すると gem 未インストールで即失敗する。
**最初に実行環境を検出し、以降の全コマンド（算出スクリプトを除く）をそのランナー経由で実行する。**

- `Makefile` に `docker compose exec ... rspec/rails` を包んだターゲット（`make test` 等）→ 最優先で利用。
- compose 定義（`compose.yml` 等）に app サービス → `docker compose exec -T <service> <cmd>`（非対話は `-T` 必須）。
  停止していれば先に `docker compose up -d`。
- `bin/` ラッパが環境を吸収するならそれを利用。無ければホストで直接実行。

詳細と環境変数の渡し方（`-e RUBYOPT=...`）は `references/upgrade-procedure.md` 冒頭の
「ステップ -1: 実行環境の検出」を参照。

### ステップ A: ターゲットバージョンを算出する

プロジェクトルートで算出スクリプトを実行する（RubyGems API を参照、stdlib のみ・依存なし）:

```bash
python3 <skill_dir>/scripts/select_rails_version.py        # 人間可読
python3 <skill_dir>/scripts/select_rails_version.py --json  # 機械可読
```

出力には `current`（現行）、`current_latest_patch`（現行マイナーの最新パッチ）、
`target`（ターゲット）、`step`（minor/major）、`target_ruby_min`（必要 Ruby）が含まれる。
ターゲットがユーザーの想定と合うか、最初に提示して確認する。

### ステップ B: 手順を実行する

`references/upgrade-procedure.md` を読み、その順序どおりに実行する。要点:

1. 準備（ブランチ作成・テストカバレッジ確認・`RUBYOPT=-W:deprecated` でベースライン警告を記録）
2. 周辺 gem の整理（`bundle outdated` → グループ別更新 → 一括更新）
3. Ruby のアップグレード（`target_ruby_min` を満たさない場合のみ、Rails より先に）
4. 現行マイナーの最新パッチへ（`current_latest_patch`）→ `bundle update rails` → テスト
5. ターゲットへ（Gemfile 編集 → `bundle update rails`）
6. `bin/rails app:update`（対話的・差分は `git diff` で確認）
7. `new_framework_defaults_X_Y.rb` を段階的に有効化
8. `config.load_defaults` をターゲットへ切り替え、defaults ファイルを削除
9. deprecation 警告の解消 / gem 互換性確認
10. 動作確認（console・server・全テスト・手動）
11. **ユーザー承認のうえで** コミット・PR 作成・デプロイ（プロジェクトのコミット/PR 規約に従う）

各ステップの正確なコマンド・注意点・Ruby 要求バージョン表は
`references/upgrade-procedure.md` にある。**必ず参照すること。**

## 停止して確認するポイント（判断が必要な箇所）

機械的作業は自動で進めてよいが、以下では一度止めてユーザーに確認する:

- 算出したターゲットバージョンの提示（着手前）。
- `bundle update` が依存解決で失敗し、他 gem のメジャー更新やバージョン固定が必要なとき。
- `bin/rails app:update` で独自設定を上書きしうるファイル（diff を示して判断を仰ぐ）。
- `bin/rails app:update` が**新規生成した opt-in スキャフォールド**の採否（例: Rails 8.1 の
  `config/ci.rb`+`bin/ci`）。既存の CI/テストランナーと競合しうるので、削除可否をユーザーに確認する。
- deprecation 警告の解消にアプリコードの変更が必要なとき（方針を確認してから修正）。
- `config.load_defaults` の切り替え（本番挙動が変わるため、新デフォルト全確認後に実施）。
- **コミット・push・PR 作成・デプロイ**（外部に影響する操作）。承認を得たうえで、プロジェクトの
  コミット/PR 規約（`/commit`・`/create-pr` 等のスラッシュコマンド、メッセージ形式、PR テンプレート）に
  従って実行する。詳細は `references/upgrade-procedure.md` ステップ 11。

## 注意

- **必ず1ステップずつ。** ユーザーが「最新まで一気に」と言っても、バージョンは飛ばさない。
  複数ステップ必要なら、1ステップ完了・テスト通過ごとに次へ進む。
- Rails プロジェクトでない（`Gemfile` に rails が無い）場合は、その旨を伝えて中止する。
- コミットは細かく分け、後から差分を追えるようにする。
