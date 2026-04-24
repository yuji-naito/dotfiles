---
name: issue-pr-flow
description: 指定したIssueに対する一連の作業（worktree作成 → exec-issue → commit → create-pr）を自動実行するスキル。新規worktree上でIssue対応から PR 作成までを一気通貫で行いたい時に使用する。
disable-model-invocation: true
---

# Issue PR Flow Skill

指定した Issue に対して、新規 worktree を作成し、Issue 対応・コミット・PR 作成までを一気通貫で実行する。

## 引数

`<issue番号> <ブランチ名> [<ディレクトリ名>]`

- `issue番号` (必須): 対応対象の GitHub Issue 番号
- `ブランチ名` (必須): 新規作成するブランチ名
- `ディレクトリ名` (任意): worktree のディレクトリ名。省略時はブランチ名を使用

引数がパースできない・不足している場合は、ユーザーに確認してから進めること。

## 実行手順

### Step 1: 引数パース

引数からリポジトリルートを基点とする worktree パス `./.worktrees/<ディレクトリ名>` を決定する。以降の説明では：

- `<ISSUE>` = 引数1（Issue 番号）
- `<BRANCH>` = 引数2（ブランチ名）
- `<DIR>` = 引数3 または `<BRANCH>`
- `<WORKTREE_PATH>` = `./.worktrees/<DIR>`

### Step 2: worktree 作成

Bash ツールで以下を実行する：

```bash
git worktree add ./.worktrees/<DIR> -b <BRANCH>
```

- 既に同名のブランチ・ディレクトリが存在する場合はエラーになる。エラー内容をユーザーに報告し中断する
- ベースブランチは現在の HEAD（通常 `main`）

### Step 3: worktree に入る

`EnterWorktree` ツールを `path` パラメータで呼び出し、作成した worktree に移動する：

- `path`: Step 2 で作成したパス（`git worktree list` で確認可能な絶対パス）

以降のツール呼び出しは worktree 内の CWD で実行される。

### Step 4: /exec-issue 実行

`Skill` ツールで `exec-issue` スキルを呼び出す：

- `skill`: `exec-issue`
- `args`: `<ISSUE>`

`exec-issue` はユーザーとの確認ステップを含むため、完了まで待機する。途中でユーザーが中断を指示した場合はフローを停止する。

### Step 5: /commit 実行

`exec-issue` の実装後、**ユーザーに以下の承認を求める**：

- 変更内容（`git status` / `git diff --stat` 程度）を提示
- 「コミットしてよいか」を明示的に確認
- 承認が得られた場合のみ次に進む。否認・修正指示があった場合はそれに従い、再度承認を求める

承認後、`Skill` ツールで `commit` スキルを呼び出す：

- `skill`: `commit`

変更が無い場合（コミット対象無し）はユーザーに報告した上でスキップして Step 6 に進む。

### Step 6: /create-pr 実行

コミット完了後、**ユーザーに以下の承認を求める**：

- 作成予定の PR の対象ブランチ（`<BRANCH>` → `main`）と関連 Issue 番号（`#<ISSUE>`）を提示
- 「PR を作成してよいか」を明示的に確認
- 承認が得られた場合のみ次に進む

承認後、`Skill` ツールで `create-pr` スキルを呼び出す：

- `skill`: `create-pr`
- `args`: `<ISSUE>`

同じ Issue 番号を渡すことで、PR 本文の `関連するIssue` に `Closes #<ISSUE>` が記載される。

### Step 7: 結果報告

以下を含む簡潔なサマリをユーザーに報告する：

- 作成したworktreeパスとブランチ名
- 作成された PR の URL
- worktree は削除せずそのまま残している旨

**重要**: worktree は `ExitWorktree` で終了しない。セッション終了時までそのまま留まる。ユーザーが明示的に離脱を求めた場合のみ `ExitWorktree(action: "keep")` を呼ぶ。

## エラーハンドリング

| エラー箇所                      | 対応                                                                   |
| ------------------------------- | ---------------------------------------------------------------------- |
| `git worktree add` が失敗       | エラー出力をそのままユーザーに報告し中断                               |
| `EnterWorktree` が失敗          | worktree は作成されている可能性があるためパスを報告した上で中断        |
| `exec-issue` 中にユーザーが停止 | 以降のステップを実行しない                                             |
| `commit` 対象が無い             | 警告を表示し `create-pr` に進む（PR は作成するが空コミット化はしない） |
| `create-pr` が失敗              | エラー内容をユーザーに報告。worktree とコミットは保持                  |

## 注意事項

- worktree 作成先 `.worktrees/` は対象プロジェクトの `.gitignore` に追加されている前提
- PR 作成後も worktree は残るため、不要になったら `git worktree remove ./.worktrees/<DIR>` で手動削除する
- `exec-issue` は長時間実行・複数回のユーザー確認を伴うため、途中経過を適宜ユーザーに共有する
