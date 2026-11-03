# DeepSeek Harness Skill — the harness doctrine, distilled for Claude Code and Codex

DeepSeek Harness (DSH) is strong not because of its model but because of **how it runs one**: an explicit plan, a lean context budget, guarded tools, bounded delegation, and verification before any success claim. This repository distills that operating pattern into a portable [Agent Skills](https://docs.claude.com/en/docs/claude-code/skills) package that works in Claude Code, Codex, and any agent that can read files, run commands, and delegate work.

> This is an independent distillation based on the observed behavior and public materials of DeepSeek Harness. It is not an official DeepSeek project. See [NOTICE](NOTICE).

## What's inside

```
dsh-harness-skill/
├── skills/dsh-harness/            # the skill (shared by Claude Code and Codex)
│   ├── SKILL.md                   # entry: principles, loop, delegation, verification (English)
│   ├── references/                # situation-specific depth; loaded only when needed
│   │   ├── 00-porting-guide.md    # DSH ↔ Claude Code ↔ Codex capability map
│   │   ├── 01-loop.md             # agent loop, parallel/exclusive calls, failure recovery
│   │   ├── 02-context-budget.md   # context saving, output spill, compaction
│   │   ├── 03-plan-goals.md       # planning, plan mode, goals, todos, schedules
│   │   ├── 04-delegation.md       # subagent delegation
│   │   ├── 05-tools.md            # tool selection and execution discipline
│   │   ├── 06-safety.md           # sandbox, approvals, destructive operations
│   │   ├── 07-skills.md           # skill authoring and progressive disclosure
│   │   ├── 08-prompt-architecture.md  # prompt/context design rationale
│   │   └── 09-orchestration.md    # teams, task boards, workflow scripts
│   ├── agents/openai.yaml         # Codex UI metadata
│   └── .claude-plugin/plugin.json # Claude Code plugin manifest
├── .claude-plugin/marketplace.json
├── install.ps1 / install.sh       # copy installers for Codex / Claude Code
├── docs/                          # distillation notes and QA review
├── LICENSE / NOTICE
└── README.md                      # Japanese README
```

`SKILL.md` is a short entry point. The host shows only `name` + `description` up front; the body and the matching `references/` file load when the situation actually occurs.

## Install

### Claude Code

Marketplace (recommended):

```text
/plugin marketplace add 5montest/dsh-harness-skill
/plugin install dsh-harness@dsh-harness-marketplace
```

CLI equivalent:

```bash
claude plugin marketplace add 5montest/dsh-harness-skill
claude plugin install dsh-harness@dsh-harness-marketplace
```

Or symlink the skill directory (auto-loads as `dsh-harness@skills-dir` next session):

```bash
ln -s /path/to/dsh-harness-skill/skills/dsh-harness ~/.claude/skills/dsh-harness
```

### Codex

```bash
git clone https://github.com/5montest/dsh-harness-skill
cd dsh-harness-skill
./install.sh                 # Codex (~/.codex/skills)
./install.sh --both          # also install for Claude Code
```

Windows:

```powershell
.\install.ps1
.\install.ps1 -Target both
```

If execution policy blocks the script: `pwsh -ExecutionPolicy Bypass -File .\install.ps1 -Target both`

Or with Codex's own skill installer:

```bash
python ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo 5montest/dsh-harness-skill --path skills/dsh-harness
```

Invoke explicitly with `$dsh-harness`, or let the description trigger discovery.

### Any other agent

Copy `skills/dsh-harness/` into the agent's skill location, or paste `SKILL.md` into its instructions and keep `references/` alongside. The content is host-agnostic; only tool names need translation.

## Using it

The skill activates on long work. Typical prompts:

- "Fix this bug and **plan → implement → verify**."
- "Large feature: investigate first, give me a plan, and implement after approval."
- "Send subagents to research in parallel while I start the implementation."
- "Context is tight — keep a state file and continue from it."
- "Show me the diff and the test output when you are done."

What it enforces, among other things:

- Read before write; on a conflict re-read, rebase, retry.
- Bound every output; spill long logs to files and read slices.
- Turn the plan into todos with exactly one in progress.
- Delegate only self-contained, verifiable, worthwhile subtasks; write a complete brief.
- Never route around a denied operation.
- Never call something complete without verifying it.

## Design

- **Only information that changes decisions.** No generic capability restatements.
- **Short entry, progressive disclosure.** Detail lives in `references/` and loads on demand.
- **Host-agnostic language.** Capabilities, not host tool names; tool names only in the porting guide.
- **Honest degradation.** [00-porting-guide.md](skills/dsh-harness/references/00-porting-guide.md) labels every DSH mechanism Native / Adaptable / Degraded / Skip.
- **No verbatim reproduction.** The doctrine is reconstructed from observed behavior, not copied prompt text.

## Limitations

- No DSH runtime: no Cordis plugins, workflow engine, session storage format, or UI. The *operating pattern* is what ports.
- Team/workflow/schedule behavior is approximated with host primitives; full parity is impossible (see the porting guide).
- Host features move fast; the mapping reflects Claude Code 2.1.x and Codex CLI 0.162.x at distillation time. Check `claude --help` and `codex features list`.
- English skill body, Japanese primary README.

## Validation

- Plugin and marketplace manifests pass `claude plugin validate`.
- Local marketplace `plugin install` was verified end-to-end.
- Independent QA review: [docs/qa-review.md](docs/qa-review.md) (source spot-checks, portability, consistency).
- Extraction scope and evidence: [docs/distillation-notes.md](docs/distillation-notes.md).

## License and attribution

- Code and prose: [MIT](LICENSE)
- Attribution, trademarks, non-affiliation: [NOTICE](NOTICE)
- Upstream product: [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
