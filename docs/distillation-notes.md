# Distillation notes

What was extracted, from where, and how much confidence each part carries. This is provenance for the skill, not a claim of endorsement.

## Source

| Item | Value |
|---|---|
| Product | DeepSeek Harness (desktop application) |
| Runtime package | `@deepseek-ai/dsh-desktop-runtime` |
| Version observed | `0.2.1-rc.5` |
| Observation date | 2026-11-03 |
| Local host versions used for porting checks | Claude Code 2.1.289, Codex CLI 0.162.1 (Windows) |

The upstream repository (`github.com/deepseek-ai/deepseek-harness`) was referenced as the project of origin. At distillation time this environment had no outbound HTTP access, so the installed application's packaged documentation and code were the primary evidence; no upstream source files were copied.

## Method

1. **Indexed the installed application.** Parsed the Electron `app.asar` archive header and extracted its application subtree: 2,953 files / 26.65 MB across 240 `@deepseek-ai` packages, excluding client UI bundles, editor assets, and LibreOffice binaries. Kept `README.md`, `package.json`, `lib/index.js`, `lib/types/*`, and skill assets per package.
2. **Read the packaged contracts.** Each package's README documents four things consistently: usage and configuration, implementation internals, the "Model Experience" (what the model sees and its token/cache effect), and known limitations. These sections were the backbone.
3. **Mined the model-visible strings.** Compiled ESM still contains the real prompt sections (`ctx.systemPrompt.section({...})`), runtime contexts, tool descriptions, guards, and result templates. These were grepped per domain to recover precise rules (caps, error codes, ordering, thresholds).
4. **Captured a rendered prompt.** A live session log (`session.v4.jsonl.zstd`, 122 concatenated zstd frames) was decompressed and its `system/message` event extracted, confirming the assembled prompt, plus runtime context (working directory, sandbox mode, approval policy, time).
5. **Distilled to host-agnostic doctrine.** Mechanisms were rewritten as capability-level rules, then mapped to Claude Code and Codex primitives. The mapping was checked against the locally installed CLIs (`claude --help`, `claude plugin --help`, `codex --help`, `codex features list`, `codex exec --help`), including a real local-marketplace plugin install.
6. **Independent QA.** A separate reviewer spot-checked claims against the same sources and reviewed usability and packaging. See [qa-review.md](qa-review.md).

## Evidence classes

| Class | Meaning | Used for |
|---|---|---|
| **A — verified triple** | Package README + `lib/index.js` string/constant + live rendered prompt (where applicable) | Core loop, compaction, sandbox/approval, tool caps, delegation |
| **B — documented** | Package README contract, not independently reproduced | Thresholds, configuration defaults, orchestration semantics |
| **C — inferred** | Cross-package composition or host-behavior inference, labelled in the reference | Porting equivalents, degraded-mode advice |
| **U — unverified** | Mentioned with an explicit "unverified" marker | A few host-specific claims and runtime details |

## Reference map

| Reference | Primary DSH sources | Central idea |
|---|---|---|
| `00-porting-guide.md` | All domains + host CLI inspection | Fidelity per mechanism; how to compensate when the host is weaker |
| `01-loop.md` | `dsh-agent-loop`, `dsh-agent`, `dsh-tools`, cancellation/timeout/repeat-reminder packages | One step = assemble → call → execute tools → persist; parallel-safe vs exclusive; recover instead of looping |
| `02-context-budget.md` | `dsh-compaction*`, `dsh-spill*`, `dsh-output-retention`, `dsh-token-meter`, `dsh-fs-observation-policy` | Bound outputs, spill to files, keep a recent tail, summarize oldest span, re-anchor after compaction |
| `03-plan-goals.md` | `dsh-plan-mode`, `dsh-goal*`, `dsh-tool-todo`, `dsh-schedule` | Plan/approve gate, durable goals, one in-progress todo, explicit reminders |
| `04-delegation.md` | `dsh-subagent*`, `dsh-tool-subagent*` | Delegate self-contained work with a complete brief; collect results; don't redo running work |
| `05-tools.md` | `dsh-tool-fs*`, `dsh-tool-pwsh`/`bash`/`terminal`, `dsh-jobs*`, `dsh-tool-web`, `dsh-mcp-client`, `dsh-tool-present` | File tools over shell for files; batch independent calls; job hygiene; web is untrusted data |
| `06-safety.md` | `dsh-sandbox*`, `dsh-user-approval`, `dsh-permission-presets`, `dsh-fs-sandbox`, `dsh-pwsh-sandbox`, `dsh-sandbox-windows-acl` | Structural confinement; one-shot escalation; never route around a denial; verify destructive targets |
| `07-skills.md` | `dsh-skill*`, `dsh-tool-skill`, `dsh-agent-preset/skills/*` | Progressive disclosure; discriminating descriptions; references over bloat; validate behavior |
| `08-prompt-architecture.md` | `dsh-system-prompt`, `dsh-persona`, `dsh-agent-instructions`, `agent-experience` skill | Ordered sections, runtime-context snapshots, instruction budget, prompt/cache stability |
| `09-orchestration.md` | `dsh-experimental-agent-team*`, `dsh-workflow*`, `dsh-tool-ralph`, `dsh-tool-present` | Shared filesystem + task board, disjoint write scopes, workflow scripting, lead review |

## What was deliberately not distilled

- **Client/UI surface:** layout, sidebar, settings, chat rendering, themes — not agent behavior.
- **Runtime internals that do not port:** Cordis plugin composition, session persistence formats, projection caches, LLM provider/adapter routing, telemetry.
- **Desktop-app features:** speech-to-text, translation, inspector, plugin market, office/LibreOffice integration (except as a pattern: skills may bundle scripts/assets).
- **Verbatim prompt text:** only short, attributed fragments are used. The long-form guidance was rewritten from observed behavior, both to avoid copying proprietary text and because the wording is host-specific anyway.
- **PTC `run_code` execution, ralph loop internals, DSH scheduling engine:** the *ideas* are described in references; the mechanisms are marked as not portable.

## Known gaps

- No upstream repository access during distillation, so file-level citations point to the installed package paths and README sections, not to upstream git paths.
- DSH is moving quickly (0.2.x release candidates). Thresholds and defaults may drift; each reference cites its source package so a re-check is cheap.
- Host mapping is a snapshot. Claude Code / Codex features listed in the porting guide should be re-verified with the local CLI when they matter.

## Reproduction

The extraction itself is reproducible on any machine with the DSH desktop app installed: read the Electron `app.asar` header, extract the `@deepseek-ai/*` package subtree, read each package's README and `lib/index.js`, then decompress a session log (`zstd`, concatenated frames) to inspect the rendered prompt. The scripts that performed this are analysis tooling and are intentionally not shipped in this repository.
