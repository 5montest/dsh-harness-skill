# Independent QA review — dsh-harness skill package

Reviewer: qa-reviewer (independent of the authoring task)
Date: 2026-11-03
Scope: `skills/dsh-harness/` (SKILL.md + references/00–09), `README.md`, `README.en.md`, `docs/distillation-notes.md`, install scripts, `.claude-plugin` manifests, `agents/openai.yaml`, LICENSE, NOTICE.
Ground truth: installed DSH package READMEs + `lib/index.js` under `...\dsh-harness-src\dsh\node_modules\@deepseek-ai\`, the rendered prompt in `...\_session-dump\parsed\system-prompt-0.md` / `request-header.json`, and the locally installed Claude Code 2.1.289 and Codex CLI 0.162.1.

## Verdict

**PASS-WITH-FIXES** — the deliverable is unusually accurate and directly usable. Of ~39 sampled factual claims spread across all ten references, 36 match the ground-truth sources (several exactly, including line numbers and a live 38-tool request header); the core doctrine in SKILL.md is sound, the frontmatter and JSON manifests validate, the installers and Codex metadata match real host formats, and no scaffolding placeholders remain. It is not PASS because three fixable defects remain: (1) three repository-relative links point at a `docs/qa-review.md` that the package does not contain; (2) the Claude Code mapping asserts that the tested version has "no native task board", while Claude Code 2.1.289 ships native TaskCreate/TaskGet/TaskList/TaskUpdate tools and an experimental agent-teams mode; (3) `03-plan-goals.md` says Codex has "no native todo/goal/reminder tool", contradicting the porting guide and the installed Codex `goals` feature. All three are one-to-few-line edits; no structural rework is needed.

## Blocking issues

### B1 — Broken relative links to the QA review (packaging)
- `README.md:135` — `[docs/qa-review.md](docs/qa-review.md)` does not exist (the review is delivered at `review/qa-review.md`).
- `README.en.md:126` — same broken target.
- `docs/distillation-notes.md:24` — `[qa-review.md](qa-review.md)` resolves to `docs/qa-review.md`, which does not exist.
- Also update the directory trees that promise the report under `docs/`: `README.md:30`, `README.en.md:28`.

**Why blocking:** the review criterion is that every relative link resolves; a shipped README pointing at a missing QA report is a packaging defect and the link is checked by users. **Minimal fix:** either move/copy the final report to `docs/qa-review.md`, or change the three links to `review/qa-review.md` (from `docs/` use `../review/qa-review.md`) and add `review/` to the tree listings.

### B2 — Claude Code host mapping is outdated on tasks/agent teams (portability, accuracy)
- `references/00-porting-guide.md:27` — "Agent Teams: … Claude Code: Subagents + shared filesystem; **no native task board** … Degraded".
- `references/00-porting-guide.md:24` — Todo tracking row names only `TodoWrite` and labels the mapping Adaptable.
- `references/09-orchestration.md:107-109` — "There is no team domain: emulate it with the `Task` tool plus a board file (`TASKS.md` …)"; likewise `03-plan-goals.md:124` assumes no host task board.

**Evidence that the claim is wrong for the version the guide claims to be tested against (2.1.289):** the installed `claude.exe` (2.1.289) contains model-facing tool descriptions for `TaskCreate`, `TaskGet`, `TaskUpdate` and `TaskList` (subject/description/status/`blocks`/`blockedBy`/owner/metadata; "Create a new task in the task list", "Task completed. Call TaskList now to find your next available task or see if your work unblocked others"), plus a team protocol ("You are a teammate in this session's agent team", "Team Leader … team-lead", `TeamCreate`/`TeamDelete`, structured shutdown/resume messages) gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` (and task gating via `CLAUDE_CODE_ENABLE_TASKS` / `CLAUDE_CODE_TASK_LIST_ID`). At minimum the guide must stop asserting flatly that no native task board exists.

**Minimal fix:** reword 00:24/00:27 and the Claude Code subsections of 03/09 to: "Claude Code 2.1.x ships native task tools (TaskCreate/TaskGet/TaskUpdate/TaskList) and an experimental agent-teams mode behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; verify on your install and fall back to a board file when the feature is unavailable." Keep the `TASKS.md` fallback.

### B3 — Contradictory Codex capability claim (internal consistency)
- `references/03-plan-goals.md:130` — "There is no native todo/goal/reminder tool (**unverified**); use the state file …".
- `references/00-porting-guide.md:25` — the same skill maps Codex's "`goals` feature (enable/verify)" for persistent goals.

**Evidence:** on the installed Codex CLI 0.162.1, `codex features list` reports `goals  stable  true` (also `agent_message_board  under development  false`, matching 00:27). The two references therefore disagree with each other, and the 03 statement is wrong for goals. The explicit "(unverified)" hedge is honest, but the contradiction remains. **Minimal fix:** replace 03:130 with "Codex has a `goals` feature (verify with `codex features list`); plan/todo tracking and reminders are version-dependent — use the state file and an external scheduler where no tool exists."

## Non-blocking suggestions

1. **Duplicated subagent brief template** — `SKILL.md:105-128` and `references/04-delegation.md:68-95` are near-verbatim copies (and already drifting: 04 has a separate `## If blocked` section that SKILL folds into Deliverable). Keep one canonical template and have SKILL.md link to it.
2. **Two different "compaction summary template"s** — `SKILL.md:66-86` (Objective/Constraints/Done/In progress/Key files/Open questions) vs `references/02-context-budget.md:96-125` (the DSH 8-section checkpoint: Primary Request and Intent … Critical Context). Both are legitimate, but the same name for different schemas is confusing; rename the SKILL one ("state summary") or link to 02's checkpoint template.
3. **SKILL.md length vs its own advice** — 168 lines / 12.8 KB; `07-skills.md:60` says keep SKILL.md "roughly one screen". It is still small in absolute terms, but trimming the loop/rules into 01 would honour the doctrine and reduce duplicate maintenance.
4. **Invalid Claude Code permission-mode name** — `06-safety.md:123` lists `default`/`acceptEdits`/`plan`/`bypassPermissions`; `claude --help` in 2.1.289 lists choices `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan` (no `default`). Update the enumeration.
5. **"Native" sandbox fidelity for Claude Code** — `00-porting-guide.md:33` marks DSH's three file-effect modes Native for Claude Code; Claude Code has permission modes plus sandbox settings but not those three named modes. Consider Adaptable or a clarifying clause (the row's "what to do" advice is already sound).
6. **Codex subagent flag** — `00-porting-guide.md:26` names `multi_agent_v2`; the installed CLI reports `multi_agent stable true` and `multi_agent_v2 stable false`. Cite the flag actually required on the user's version, or say "verify with `codex features list`".
7. **Minor citation imprecisions** — `07-skills.md:147` cites `dsh-tool-skill/lib/index.js:789` for the `<skill_content>` result (789 is the tool description; the block render is ~979); `04-delegation.md:15` cites `dsh-subagent/lib/index.js:363` for the child delegation-scope statement (the constant is at 362); `09-orchestration.md:28,143` writes `tool-agent-team` where the package is `dsh-experimental-tool-agent-team`. README-section citations checked resolved cleanly.
8. **Windows execution policy** — `.\install.ps1` is unsigned; on this machine (RemoteSigned) it fails until the policy is bypassed. Verified it works when allowed. Add a one-line fallback (`pwsh -ExecutionPolicy Bypass -File .\install.ps1`) to the README install notes.
9. **Claude Code / Codex sections now verifiable** — several sections are labelled "(unverified)" broadly (e.g. `04-delegation.md:109`, `07-skills.md:111`, `09-orchestration.md:105`) although the CLIs are installed locally; narrowing those labels to the genuinely unverified bullets would raise trust.
10. **`$schema` URLs in the two manifests** are not part of the validated contract (validate passes and ignores them). Harmless; only worth removing if they 404 in a browser.

## Spot-check evidence table

Sample: 39 claims across references 00–09 (thresholds, defaults, error codes, ordering, caps, host CLI behavior). Result legend: PASS = matches source; FAIL = wrong/misattributed; MINOR = accurate but imprecise.

| # | Claim (file:line) | Ground-truth source | Result |
|---|---|---|---|
| 1 | `maxParallelToolCalls` default 10, `1` = serial (01:22) | `dsh-agent-loop` README config table; `lib/index.js:1554` | PASS |
| 2 | Retry: 5 retries for EMPTY_RESPONSE/RATE_LIMIT/SERVER/TIMEOUT/TRANSPORT, 500 ms→10 s, 10% jitter (01:47) | `dsh-llm-retry` README "Use this package" | PASS |
| 3 | Repeat thresholds default 3, 5, 8; gentle then detailed reminder (01:55-57) | `dsh-repeat-tool-reminder/lib/index.js:2118-2126`, `2233-2241` | PASS |
| 4 | Only web tools declare 30,000 ms; bash/read/write/edit declare none (01:50) | `dsh-tool-call-timeout-policy` README "Setting it up" | PASS |
| 5 | Pre-step reject=blocked, empty first batch=completed; cited lines (01:10, refs) | `dsh-agent-loop/lib/index.js:953-968` | PASS |
| 6 | Read caps: 2000 lines / 2000 chars per line / 51,200 bytes / stream ≥10 MiB (02:9, 05:16) | `dsh-tool-fs` README config; `lib/index.js:16-19`, `217` | PASS |
| 7 | glob 100 paths, grep 250 matches, 2000-byte previews, 30 s timeout (02:12, 05:26-27) | `dsh-tool-fs-search` README config; `lib/index.js:537`, `884`, `1220-1221` | PASS |
| 8 | Compaction threshold `floor(min(W×0.8, W−O−65536))`, retain 16% (02:37) | `dsh-compaction-basic` README "Tuning when condensation starts" | PASS |
| 9 | Pruner 8192/4096/1024 code points; only after a compaction trigger (02:27-28) | `dsh-compaction-tool-result-pruner` README | PASS |
| 10 | Compaction summary structure: 8 exact sections, every section, `(none)`, merge prior checkpoint (02:47-58) | `dsh-compaction-basic/lib/index.js:243-278` | PASS |
| 11 | Token meter: 4 chars/token heuristic; `totalTokens`/`surfaceTokens`/`node` prices; projections (02:62-65) | `dsh-token-meter` README "Measuring pressure"/"Session projections" | PASS |
| 12 | Todo success text `Updated todo list: …` (03:12) | `dsh-tool-todo/lib/index.js:167` | PASS |
| 13 | `defaultMaxGoalRounds` 256 (03:34) | `dsh-goal` README config table; `lib/index.js:588` | PASS |
| 14 | `blockedAfterConsecutiveRounds` default 3 (03:37) | `dsh-tool-goal/lib/index.js:115` | PASS |
| 15 | Plan-mode section at first-party order 500 (03:20) | `dsh-plan-mode` README "Model Experience" | PASS |
| 16 | Schedule: title ≤120 chars, exactly one selector, `after_seconds` create-only, 5-field Vixie (03:46-47) | `dsh-schedule` README; `dsh-tool-schedule` README "The four tools" | PASS |
| 17 | `maxDepth` default 1; `maxActiveSubagents` default 8; ACTIVATION_LIMIT_REACHED at capacity (04:13-14) | `dsh-subagent` README; `lib/index.js:82`, `1047` | PASS |
| 18 | Fork seed = completed turns only; in-flight turn never included (04:20) | `dsh-subagent-fork-in-process` README "Seed boundary" | PASS |
| 19 | ACP/SDK/Codex/Claude Code children execute once, no follow-ups (04:12) | `dsh-subagent` README §Local and external children, §Known Limitations | PASS |
| 20 | Live request header: 38 tools, lexicographic, `ask_user_question` first, `write` last (05:11, 08:67) | `_session-dump/parsed/request-header.json` | PASS (exact) |
| 21 | Jobs: `wait: true` default 30,000 ms, model wait capped at 600,000 ms; `<id> [<kind>] <status> — <label>` (05:44-45) | `dsh-tool-jobs` README config + §The three tools | PASS |
| 22 | `present`: existing regular files only, absolute paths, `maxFiles` 8 (05:57, 09:48) | `dsh-tool-present` README | PASS |
| 23 | web_search 1–4 queries, 8-result cap, dedupe+round-robin, one failing query aborts batch (05:51) | `dsh-tool-web` README | PASS |
| 24 | Default sandbox mode `read-only`; precedence grant → session event → deployment default (06:21) | `dsh-sandbox-policy` README config/resolution | PASS |
| 25 | Presets: workspace-write→(workspace-write, ask), danger-full-access→(danger-full-access, never) (06:53) | `dsh-permission-presets` README | PASS |
| 26 | One-shot approvals only; no allow-always/grant store; no `on-failure` policy (06:41,47) | `dsh-user-approval` README §Known Limitations | PASS |
| 27 | Windows: ConstrainedLanguage under read-only, named-pipe EPERM in both modes, hard-link alias, AppContainer `S-1-15-2` ACE, repair needs unconfined caller (06:59-66) | `dsh-sandbox-windows-acl` README §Known Limitations; `dsh-tool-pwsh` README | PASS |
| 28 | Skill roots/ranks 100/200/300/400/500/600; nested `**/SKILL.md` not discovered (07:16-27) | `dsh-skill-filesystem` README; `lib/index.js:553`, `559` | PASS |
| 29 | Catalog cap `catalogDescriptionMaxLength` 500; `whenToUse` never rendered (07:34,40) | `dsh-tool-skill` README config + §Known Limitations | PASS |
| 30 | Bundled `office` router is a 15-line skill naming per-format skills (07:51) | `dsh-skill-office/assets/office/SKILL.md` (exactly 15 lines) | PASS |
| 31 | First-party section orders −1000/0/500/600/800/900/1000-3100/5000/9000/9900/10000/10100/10200 (08:13-27) | `dsh-system-prompt/lib/index.js:10-43` | PASS (exact) |
| 32 | Context orders 100/110/115/120/125/200/210 (08:38-46) | `dsh-system-prompt/lib/index.js:44-52` | PASS (exact) |
| 33 | Instruction chain: global then project broad→specific; `maxBytes` 65,536 (bundle) / `maxSourceBytes` 1 MiB; content-based dedupe; touch-driven refresh; symlinks followed (08:78-83) | `dsh-agent-instructions` README §What the agent gets, §Main flow, §Known Limitations | PASS |
| 34 | Team limits: `maxMembers` 16, `maxTasks` 256, `maxMessageBytes` 65,536; `task-<n>` ids; TEAM_TASK_STALE_REVISION / TEAM_TASK_LIMIT (09:21) | `dsh-experimental-agent-team` README config; `lib/index.js:1221-1278` | PASS |
| 35 | Workflow engine caps: maxConcurrentAgents 0, maxTotalAgents 1000, maxItemsPerCall 4096, syncTimeoutMs 5000 (09:43) | `dsh-workflow-ptc` README §Config | PASS |
| 36 | Ralph maxRounds 256, maxHandoffChars 16384; `wait_agent` 10 s–1 h, noProgress (09:28,47) | `dsh-tool-ralph` README; `dsh-experimental-agent-team` README §Waiting and interruption | PASS |
| 37 | Host snapshot: Claude Code 2.1.289 / Codex CLI 0.162.1; `claude --bg`, `--append-system-prompt`, `claude plugin marketplace add/install/validate`; `codex resume/agents/features list`, `-s read-only\|workspace-write\|danger-full-access` (00:5, 21-39) | Installed CLIs (`claude --help`, `claude plugin --help`, `codex --help`, `codex features list`) | PASS |
| 38 | Codex: `agent_message_board` under development; `goals` feature exists (00:25,27) | `codex features list` (`goals stable true`, `agent_message_board under development false`) | PASS |
| 39 | Claude Code: "no native task board"/TodoWrite-only, and Codex "no native todo/goal tool" (00:24,27; 03:130; 09:107) | Claude Code 2.1.289 binary: TaskCreate/TaskGet/TaskList/TaskUpdate tool text + `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; `codex features list` goals=true | **FAIL** |

Also verified: all `§Section` citations in all ten "Evidence" tables resolve to real README headings (automated check — 0 misses); 20+ sampled `lib/index.js:line` citations land within a few lines of the cited behavior (2 minor offsets noted in N7).

Mechanical checks run: markdown link resolver (only the 3 `qa-review.md` links fail), YAML frontmatter parse, `.claude-plugin/*.json` JSON parse, `claude plugin validate` on the marketplace root and on `skills/dsh-harness` (both "Validation passed"), `agents/openai.yaml` diffed against installed Codex `.system/*/agents/openai.yaml` (same `interface:` schema), `install.ps1` executed into a temporary `CODEX_HOME` (installs all 18 files; works when execution policy permits).

## Portability findings

- **Verified working mappings:** Claude Code `--bg`/`claude agents`, `--append-system-prompt`, `--allowedTools`, plugin marketplace add/install/validate, skills dirs; Codex `exec`, `resume`, `agents`, `features list`, `plugin marketplace`, three sandbox modes, `goals`/`multi_agent` flags. The fidelity legend (Native/Adaptable/Degraded/Skip) is used honestly; the "Apply in Claude Code/Codex" subsections are consistently labelled "(unverified)" where client behavior was not reproduced.
- **Blocking gap:** Claude Code task/task-board and experimental agent-teams support (B2). The installed version contradicts "no native task board"; the fallback advice is still valid, so this is a wording/verification fix rather than a redesign.
- **Blocking gap:** Codex goal support contradiction (B3).
- **Non-blocking:** Claude Code sandbox-mode fidelity (N5), Codex subagent feature-flag naming (N6), permission-mode enumeration containing a non-existent `default` value (N4).
- The porting guide's "tested against 2.1.289 / 0.162.1 (Windows)" is accurate for this machine, and `codex features list` output exactly matches both 00:5 and the feature-flag claims around 00:26-27 — evidence the author did check these CLIs, which makes the B2 miss more likely a stale assumption than invention.

## Internal consistency and packaging

- SKILL.md routing table: 10 rows → all ten reference files exist, names and one-line descriptions match their contents; the table appears before the loop, so a fresh loader can route without preloading.
- No contradictory numeric rules found across references (parallel cap 10, repeat thresholds 3/5/8, compaction 0.8/16%/65,536, read 2000/2000/51,200, glob 100 / grep 250, preset table, team 16/256/65,536, workflow caps all agree where repeated).
- Duplication to fix: the subagent brief template (SKILL vs 04) and the two differently-structured "compaction summary templates" (SKILL vs 02).
- Cross-reference naming: one shorthand (`tool-agent-team`) and two off-by-a-few-lines lib citations (N7); all README-section citations resolve.
- Packaging: frontmatter valid (`name` kebab-case + single-sentence-ish `description`); both JSON manifests validate with the real `claude plugin validate`; `agents/openai.yaml` matches the installed Codex skill metadata schema; LICENSE (MIT) and NOTICE (non-affiliation/trademark) present and coherent; `.gitignore` sane; no scaffolding placeholders (only literal `{{variable}}` prose and Japanese "TODO" in normal text); installers work; 3 broken links = B1.

## Usability note — what a fresh agent does after reading SKILL.md

1. It reads the frontmatter description, matches "long, multi-step coding work", and loads SKILL.md.
2. It reads "Load policy" and does **not** preload all references; it continues into "The loop".
3. First concrete actions: **Frame** the deliverable/constraints/definition of done (asking only decision-changing questions), then **Recon** (read files, list tree, check git state) before touching anything; it writes one todo per step with exactly one `in_progress`; it batches independent reads, prefers file tools over shell for files, and treats tool errors as data.
4. On a long turn it will consult `01-loop.md` (step/failure semantics, retry budget), on context pressure `02-context-budget.md` (including the compaction template), on plan approval `03-plan-goals.md`, on delegation `04-delegation.md` (complete brief template), on tool choice `05-tools.md`, on a denial `06-safety.md`, and — because it is in a weaker host — `00-porting-guide.md` for the fidelity table and degraded-mode checklist.
5. Before answering it runs the build/tests, reads the diff, and reports changed → verified → risks.

Usability gaps (minor): SKILL.md has no explicit "exit criteria / evidence required" block (its own 07 template recommends one), the router does not tell the loader that each reference contains "Apply in Claude Code"/"Apply in Codex" subsections (discoverability), and the `09-orchestration` row sits before 05–08 in the routing table (harmless, but numeric order would scan faster). With B1–B3 fixed, a fresh Claude Code or Codex agent has everything it needs to act correctly without opening another file.

## Review limits

Sampled rather than exhaustive: ~39 of the ~1,300 deliverable lines were checked against source (all ten references represented); the remainder was assessed for consistency/packaging rather than re-derived. No outbound network access was used; host-behaviour checks were run against the locally installed CLIs and binaries described above.

## Resolution (Lead, same day)

- **B1 fixed** — the report now lives at `docs/qa-review.md`; README.md, README.en.md, and docs/distillation-notes.md links resolve.
- **B2 fixed** — 00-porting-guide.md and 09-orchestration.md now describe Claude Code 2.1.x native task tools (`TaskCreate`/`TaskGet`/`TaskUpdate`/`TaskList`) and the experimental agent-teams mode (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`), with the `TASKS.md` fallback retained; the sandbox-fidelity row was downgraded to Adaptable.
- **B3 fixed** — 03-plan-goals.md now matches 00-porting-guide.md on Codex's `goals` feature.
- **Non-blocking applied** — permission-mode enumeration corrected in 06-safety.md; Codex feature-flag wording verified in 00; shorthand/citation offsets corrected in 04/07/09; `-ExecutionPolicy Bypass` fallback added to both READMEs; SKILL.md routing table reordered and its state-summary template renamed to avoid confusion with the 8-section DSH checkpoint; canonical delegation template noted.
- **Not changed** — the two templates remain (SKILL.md = portable quick version; 02-context-budget.md = DSH-accurate checkpoint), intentionally distinguished by name and cross-reference.
