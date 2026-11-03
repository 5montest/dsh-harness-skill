# DeepSeek Harness Skill — ハーネスの運用ドクトリンをClaude Code / Codexへ

DeepSeek Harness（DSH）から**「ハーネス部分」＝エージェントの進め方**だけを抽出し、Claude Code と Codex でそのまま使える [Agent Skills](https://docs.claude.com/en/docs/claude-code/skills) 形式のスキルに蒸留したものです。

DSHの強さはモデルではなく、**回し方**にあります。計画を明示し、コンテキストを節約し、ツールを統制し、委譲を限定し、検証してから完了を宣言する。このリポジトリはその運用パターンを、特定のランタイムに依存しない形で再構成したものです。

> 本リポジトリはDeepSeek公式ではなく、DeepSeek Harnessの挙動と公開情報を独立に分析・蒸留したものです。詳細は [NOTICE](NOTICE) を参照してください。

## 何が入っているか

```
dsh-harness-skill/
├── skills/dsh-harness/            # スキル本体（Claude Code / Codex 共通）
│   ├── SKILL.md                   # 入口：原則・ループ・委譲・検証（英語）
│   ├── references/                # 状況別の詳細（必要なときだけ読む）
│   │   ├── 00-porting-guide.md    # DSH ↔ Claude Code ↔ Codex の対応表
│   │   ├── 01-loop.md             # エージェントループ、並列/排他、失敗回復
│   │   ├── 02-context-budget.md   # コンテキスト節約、spill、compaction
│   │   ├── 03-plan-goals.md       # 計画、plan mode、ゴール、TODO、スケジュール
│   │   ├── 04-delegation.md       # サブエージェント委譲
│   │   ├── 05-tools.md            # ツール選択と実行規律
│   │   ├── 06-safety.md           # サンドボックス、承認、破壊的操作
│   │   ├── 07-skills.md           # スキル設計・プログレッシブディスクロージャ
│   │   ├── 08-prompt-architecture.md  # プロンプト/コンテキストの設計思想
│   │   └── 09-orchestration.md    # チーム、タスクボード、workflow
│   ├── agents/openai.yaml         # Codex用UIメタデータ
│   └── .claude-plugin/plugin.json # Claude Codeプラグイン定義
├── .claude-plugin/marketplace.json
├── install.ps1 / install.sh       # Codex/Claude Code へのコピー導入
├── docs/                          # 蒸留メモ・品質レビュー
├── LICENSE / NOTICE
└── README.en.md
```

`SKILL.md` は短い入口です。エージェントは起動時に `name` と `description` だけを見て、必要になったときだけ本文と該当する `references/` を読みます（プログレッシブ・ディスクロージャ）。

## インストール

### Claude Code

マーケットプレイス経由（推奨）:

```text
/plugin marketplace add 5montest/dsh-harness-skill
/plugin install dsh-harness@dsh-harness-marketplace
```

CLIでも同じです:

```bash
claude plugin marketplace add 5montest/dsh-harness-skill
claude plugin install dsh-harness@dsh-harness-marketplace
```

スキルディレクトリを直接置く方法（次回セッションで `dsh-harness@skills-dir` として自動ロード）:

```powershell
# Windows
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\dsh-harness" `
  -Target "<path-to>\dsh-harness-skill\skills\dsh-harness"
```

```bash
# macOS / Linux
ln -s <path-to>/dsh-harness-skill/skills/dsh-harness ~/.claude/skills/dsh-harness
```

プロジェクト単位で使う場合は `<repo>/.claude/skills/dsh-harness/` にコピーします。

### Codex

```powershell
git clone https://github.com/5montest/dsh-harness-skill
cd dsh-harness-skill
.\install.ps1                 # Codex (~/.codex/skills)
.\install.ps1 -Target both    # Claude Code にも同時に入れる
```

実行ポリシーで止まる場合: `pwsh -ExecutionPolicy Bypass -File .\install.ps1 -Target both`

```bash
./install.sh                  # Codex
./install.sh --both           # Claude Code にも
```

Codex標準のスキルインストーラを使う場合:

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo 5montest/dsh-harness-skill --path skills/dsh-harness
```

導入後は `$dsh-harness` で明示的に呼び出せます（説明文から自動選択もされます）。

### その他のエージェント

`skills/dsh-harness/` をそのエージェントのスキル置き場にコピーするか、`SKILL.md` を instructions に、`references/` を隣に置いてください。本文はホスト非依存で、ツール名だけ読み替えれば動きます。

## 使い方

スキルは「長い作業」で自動的に効きます。明示的に呼ぶ場合は次のように:

- 「このリポジトリの不具合を直して。**計画→実装→検証**で進めて」
- 「大きめの機能追加。まず調査して計画を出して、承認後に実装して」
- 「サブエージェントに調査を並列で投げて、本体は実装を進めて」
- 「コンテキストがきついので、状態をファイルに残しながら進めて」
- 「終わったら diff とテスト結果を見せて」

スキルが教えるのは、たとえば次のような規律です。

- 書く前に読む／競合したら読み直してから編集し直す
- 出力は有限にする（長いログはファイルへ、必要部分だけ読む）
- 計画はTODOに落とし、同時に1つだけ進行中にする
- 委譲は「自己完結・検証可能・十分大きい」仕事だけ。ブリーフは完結に書く
- 許可されていない操作は別ルートで回避しない
- 検証していないものを「完了」と言わない

## 設計方針

- **運用に効く情報だけ**を残す。モデルが既にできる一般論は書かない。
- **入口は短く**、詳細は `references/` に分割し、状況に応じて読む。
- **ホストの用語に依存しない**。DSH固有のツール名ではなく、必要な能力（読む・書く・検索・実行・委譲・承認）で記述する。
- **劣化を隠さない**。Claude Code / Codex に無い機能は [00-porting-guide.md](skills/dsh-harness/references/00-porting-guide.md) で「Native / Adaptable / Degraded / Skip」を明示する。
- **逐語コピーをしない**。DSHのプロンプト文面ではなく、観測した挙動から運用パターンを再構成する。

## 制限

- DSHのランタイム（Cordisプラグイン、workflow実行系、セッション保存形式、UI）は含みません。移植できるのは**進め方**です。
- チーム／workflow／スケジュールなどDSH固有機能は、ホスト側の primitive で近似します。完全な再現はできません（ポーティングガイド参照）。
- Claude Code / Codex の機能は更新が速いため、対応表は検証時点（Claude Code 2.1.x / Codex CLI 0.162.x）のものです。`claude --help`、`codex features list` で確認してください。
- 本文は英語、READMEは日本語です（スキル本文はモデルが読むため英語が慣例）。

## 検証

- `claude plugin validate` でプラグイン／マーケットプレイス定義を検証済み。
- ローカルのマーケットプレイスからの `plugin install` を実機確認済み。
- 内容の独立QAレビュー: [docs/qa-review.md](docs/qa-review.md)（ソースとの突合、ポータビリティ、一貫性）。
- 蒸留の根拠と範囲: [docs/distillation-notes.md](docs/distillation-notes.md)。

## ライセンスと帰属

- コードと文章: [MIT](LICENSE)
- 帰属・商標・非公式である旨: [NOTICE](NOTICE)
- 元プロダクト: [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)

DeepSeek Harness の設計と公開ドキュメントに感謝します。
