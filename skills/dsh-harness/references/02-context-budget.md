# 02 — Context budget, output retention, and durable file state

Context is the scarcest resource in a long run: every tool result is resent on every later request until something removes it. DSH attacks the problem in layers — bounded read windows, spill files for oversized results, pruning of giant tool outputs, image offload, and finally compaction of old history into a summary. This reference documents those layers and gives a budget protocol plus the summary template that a replacement agent needs to resume cleanly.

## What the harness does (observed)

### Layer 1 — bounded reads and progressive disclosure

- `read` returns a 1-based line window, not a file. `offset` defaults to 1; `limit` defaults to and may not exceed `readLimit` = **2000 lines**; each line is capped at **2000 chars** (`... (line truncated to 2000 chars)`); one read returns at most **50 KiB** of selected text; files ≥ **10 MiB** are streamed rather than loaded whole (`dsh-tool-fs/lib/index.js:16-19`, `69-112`, `212-217`).
- The footer is the recovery contract: `(Showing lines a-b of N. Use offset=c to continue.)`, `(Output capped. Showing lines a-b. Use offset=c to continue.)`, or `(End of file - total N lines)`. An offset past EOF is an `FS_NOT_FOUND` error, not an empty result (`dsh-tool-fs/lib/index.js:101-112`, `52-58`).
- A failed read of a missing path is still an observation: it records confirmed absence, which authorizes a later guarded `write` to recreate the file (`dsh-fs-observation-policy` README, "What changes for the model").
- Search is pre-bounded too: `glob` returns at most 100 paths (modification-time order), `grep` at most 250 matches with 2000-byte line previews; over-cap results are saved whole and the page carries the locator and retrieval hint (`dsh-tool-fs-search/lib/index.js:1220-1222`, `692-731`, `1031-1040`).
- Shell and web tools bound output with head/tail byte retainers and an omission notice such as `Omitted N items.`; the library standardizes the notice and each tool supplies its own recovery wording (`dsh-output-retention` README, "Building the omission footer").
- The prompt itself steers this: use `read`/`offset`/`limit` and prefer host file tools over shell dumping (`dsh-tool-fs/lib/index.js:245-249`).

### Layer 2 — spill: truncation becomes a file plus a pointer

- `dsh-spill-policy` enforces one estimated-token budget shared by text and images, `maxInlineTokens`. Omitted (the default) disables retention; the value in a given deployment is composition-specific (unverified here). A negative or fractional value fails plugin load (`dsh-spill-policy` README, "Minimal configuration").
- Oversized results keep order: the head and tail each receive half the remaining budget after notices; text may split, images are kept or omitted whole, and images inside the omitted interval are omitted (`dsh-spill-policy` README, "What the model sees").
- The notice is the model's recovery path: `(Omitted N bytes. Full formatted result stored at: <path>. Use read with offset/limit, or grep this path to search within it.)`; omitted image counts are reported too (`dsh-spill-policy` README, "What the model sees").
- `read` results and blocked/value-replaced results pass through untouched; provider/tool limits applied earlier cannot be recovered by the policy. A failed save or missing backend logs a warning and keeps the original inline — spill never turns a success into an error (`dsh-spill-policy` README, "Which results are affected", "Best-effort failure behavior").
- The local backend writes `<root>/session-<hash>/<random>-<safeName>`, root private 0700 by default, and returns `locator`, exact byte count, and the hint "Use read with offset/limit, or grep this path to search within it." A one-shot startup cleanup deletes files older than `cleanupPeriodDays` (default 30; `0` disables) (`dsh-spill-local` README, "What you get back", "Where files land", "Startup cleanup").
- Spilled artifacts are text conventions, not proof: `hasSpillNotice` recognizes formatting, not authenticity, so a tool can print the same notice (`dsh-spill-policy` README, "Known Limitations").

### Layer 3 — pruning oversized tool results

- `dsh-compaction-tool-result-pruner` replaces over-budget tool text with head + a short "middle pruned" marker + tail. Defaults: trim when text exceeds **8192** code points, keep the first **4096** and last **1024** (`dsh-compaction-tool-result-pruner` README, "Setting the size limits").
- It runs only **after a compaction trigger qualifies**; below pressure nothing is trimmed. Trimming makes no model call and can relieve enough pressure to skip summarization entirely. The complete original event stays in the log and the replacement cites it (`dsh-compaction-tool-result-pruner` README, "When trimming runs", "Design philosophy").

### Layer 4 — image offload

- When an image-capable route rejects a request as over its image budget (`IMAGE_OFFLOAD_REQUIRED`, carrying an `offloadImages` count), `dsh-compaction-image-offload` permanently replaces that many older images with text naming the attachment and its read-only path, then retries without spending provider retry budget (`dsh-compaction-image-offload` README, "Use this package").
- The decision is a durable `image/offload` event; message events and surface identities stay unchanged, and later requests, route changes, resume, and replay all honor it. Token accounting follows the logged selections; provider cache reuse ends at the first changed message (`dsh-compaction-image-offload` README, "What you can observe", "Summary").

### Layer 5 — compaction of old history

- Trigger by pressure: with window `W`, routed output cap `O`, and headroom `B` = 65,536 tokens, the default threshold is `floor(min(W × 0.8, W − O − B))`. Retention keeps the newest 16% of `W − O` verbatim; both are configurable, with per-model overrides (`dsh-compaction-basic` README, "Tuning when condensation starts").
- Recovery trigger: a provider-confirmed `CONTEXT_WINDOW_EXCEEDED` bypasses threshold and retention, attempts one maximal balanced head reduction, and authorizes retry only after the surface replacement generation advances (`dsh-compaction-basic` README, "Automatic triggers and overflow recovery").
- Manual trigger: `/compact` condenses immediately, even below pressure; it reports items condensed and estimated tokens freed, and reports "unavailable" mid-turn or while compaction is already running (`dsh-compaction-basic` README, "On-demand condensation").
- Safety rules: the selected range must start at the first non-system surface node (the system prompt is never shadowed), edges must be tool-pair balanced (no unanswered call crossing the cut), and the framed summary must be strictly smaller than the shadowed content (`dsh-compaction` README, "Tool-pairing boundaries"; `dsh-compaction-basic/lib/index.js:601`).
- The transaction is bracket-locked: `compaction/start` → summarize → revalidate → `compaction/summary` + one replacement `user/message` → `compaction/end`. A crash leaves a detectable orphaned lock; shadowed events remain in the log, so replay is deterministic (`dsh-compaction` README, "The surface contract").
- Limits: compaction shrinks derived history only — never the system prompt, tool schemas, or session prefix — and cannot split one indivisible unit such as a single huge tool call (`dsh-compaction` README, "Known Limitations").
- The replacement is framed as established background inside `<compacted-summary>` tags with a preamble telling the model not to acknowledge it; only summary text enters the checkpoint (no reasoning, tool calls, or images) (`dsh-compaction-basic/lib/index.js:233-280`, `344-356`).

### What the summary must contain

The default instruction requires exactly this structure, every section present, terse bullets, `(none)` for empty sections (`dsh-compaction-basic/lib/index.js:243-278`):

- `## Primary Request and Intent` — the user's original and evolving goals; quote exact wording where it matters.
- `## Key Technical Concepts` — technologies, frameworks, patterns, conventions.
- `## Files and Code` — exact paths plus why they matter and what changed.
- `## Errors and Fixes` — error → resolution, including related user feedback.
- `## Pending Jobs` — explicitly requested work not yet completed.
- `## Current Work` — precisely what was in progress at the cutoff.
- `## Next Step` — the single next action, or `(none)`.
- `## Critical Context` — decisions and rationale, constraints, preferences, open questions, data needed to continue.

Rules attached to the template: concise engineering prose; preserve exact paths, commands, error strings, identifiers, numeric values, signatures, syntax fragments; capture user corrections faithfully; do not mention the summarization; output only the checkpoint; when a prior `<compacted-summary>` exists, merge it instead of copying it forward verbatim (`lib/index.js:272-278`).

### Token metering

- `ctx.tokenMeter.measure(session)` replays the durable log and returns a detached snapshot: `totalTokens` (request+response pressure), `surfaceTokens`, and per-node prices. Estimation is a fixed heuristic of four characters per token plus block and role overhead — accurate enough for pressure, not billing (`dsh-token-meter` README, "Measuring pressure", "Reading the numbers").
- Provider-reported usage is reused only when the latest successful call's canonical envelope matches the measured envelope and its total is not lower; otherwise the whole surface is estimated (`dsh-token-meter` README, "Measuring pressure").
- Projections: `tokenUsage`, `contextPressure` (`pressureTokens`, `projectedTokens`, `contextWindow`), and `contextBreakdown` (`systemTokens`, `toolsTokens`, `messageTokens`). Nothing in the harness makes decisions from occupancy; compaction reads `measure()` (`dsh-token-meter` README, "Session projections", "Reading the numbers").
- The heuristic underprices CJK text and JSON schemas badly, so treat percentages as approximate and leave headroom (`dsh-token-meter` README, "Reading the numbers").

### Read-before-write and stale-version discipline

- The observation policy records one of three states per target per session: unseen, confirmed absent, or present at a version. `write` on unseen/absent resolves to guarded `createIfAbsent`; on present it resolves to `replaceIfVersion` at the observed version. `edit` on unseen fails `FS_NOT_OBSERVED`, on absent fails `FS_NOT_FOUND`, otherwise supplies the observed version as a compare-and-swap basis (`dsh-fs-observation-policy/lib/index.js:47-70`).
- Model-facing remedies are stable: unread target → `cannot modify "<path>": file has not been read — read the file, then retry`; stale target → the provider reason plus `— re-read the file, then retry` (`dsh-tool-fs/lib/index.js:466-478`).
- Observations are process/session-local and never persisted: a resumed session must re-read files before guarded mutations (`dsh-fs-observation-policy` README, "What changes for the model").
- A windowed read authorizes a full overwrite of an unchanged file — the guard is version freshness, not view completeness — so a partial read does not mean you know the file (`dsh-fs-observation-policy` README, "Known Limitations").
- A create/overwrite outside the guard can clobber a concurrent writer; the guarded `createIfAbsent` path exists precisely to protect concurrent creation (`dsh-fs-observation-policy` README, "Failures and recovery").

### Time and runtime context

- On eligible steps the model receives a three-line clock reading: sampled time with offset and IANA zone, the request's browser-zone policy, and elapsed time since the preceding model-visible message (or preceding step context). Missing baseline reports `unavailable`; backward clock movement clamps to zero (`dsh-time-context` README, "What the model gets", "Model Experience").
- Readings are durable user-role messages, injected at most once per 10 minutes by default (`refreshIntervalMs: 0` injects every eligible step) and accumulate until compaction shadows them. Mixed or missing browser zones make the model ask rather than guess (`dsh-time-context` README, "Configuration", "Known Limitations").
- Runtime context (working directory, tool updates) is refreshed per step and committed as part of the derived history; it is subject to the same compaction budget (`dsh-agent-loop` README, "Model Experience").

## Portable protocol — the context budget

1. **Know the capacity and the trigger.** Estimate the window and set your own threshold at ~80% of capacity minus the output reservation. At the threshold, stop opening new work.
2. **Climb the disclosure ladder.** `glob`/`grep` to locate → `read` with `offset`/`limit` → only then open the region. Never read a whole large file when a slice answers the question.
3. **Bound at the source.** Redirect long command output to a file and read a slice; pipe through `tail`/`head`; cap search results. A tool call that can return megabytes is a design error.
4. **Externalize state before it is needed.** Maintain a durable state file; update it at phase boundaries and before any compaction.
5. **Keep identifiers verbatim.** Paths, commands, error strings, identifiers, numbers, and signatures are the expensive part of context; narration is the cheap part to drop.
6. **Spill oversized artifacts, keep the pointer.** Save full output to a file and keep a one-line handoff (`Omitted N bytes; full result at <path>; read with offset/limit or grep the path`). Never treat spill as failure.
7. **Prune before summarizing.** Trim the middle of huge tool results (keep head and tail) — a no-model-call reduction that may avoid compaction entirely.
8. **Re-read before every mutation after a gap.** A read is a version observation; after compaction, resume, or another writer, re-read. On stale conflict: read, rebase, retry — never blind-overwrite.
9. **Offload media, keep handles.** Store images/pages as paths, re-open only when the current step needs them.
10. **Compact deliberately, then re-anchor.** Write the state file, produce the summary, and after compaction re-read the state file and the live files before acting. Never trust pre-compaction file contents.
11. **Qualify time.** Record timestamps with zone when a decision depends on "today", deadlines, or elapsed time.
12. **Verify your estimate.** Provider usage is authoritative; local heuristics underestimate CJK and JSON, so keep extra margin.

Compaction summary template (portable form of the DSH structure):

```markdown
## Primary Request and Intent
- <original goal; evolving goals; exact wording where it matters>

## Key Technical Concepts
- <stack, patterns, conventions>

## Files and Code
- <exact path> — why it matters; what changed

## Errors and Fixes
- <error string> — resolution; related user feedback

## Pending Jobs
- <explicitly requested work not finished>

## Current Work
- <exactly what was in progress at this cutoff>

## Next Step
- <single next action, or (none)>

## Critical Context
- <decisions + rationale, constraints, preferences, open questions, data needed>

<!-- Rules: terse bullets, never drop a section, use (none); preserve exact paths,
commands, errors, identifiers, numbers, signatures; merge any prior checkpoint. -->
```

Durable state file (`CONTEXT.md`) template:

```markdown
# State — <task>
Objective: <one sentence>
Done criteria: <verifiable checks>
Constraints / user decisions: <...>
Verified done: <artifacts + evidence>
In progress: <file:step>   Next: <one action>
Files touched: <path — change>
Open questions / risks: <...>
```

Stale-version recovery loop:

```text
edit -> FS_STALE_VERSION | "file has not been read"
  -> read(target, region)          # new observation
  -> recompute the intended diff against current content
  -> edit again; never force-write the old content
```

## Apply in Claude Code

- `Read` supports `offset`/`limit` and returns line-numbered windows; use `Grep` with bounded `head_limit` before reading. `/context` shows occupancy; auto-compact fires near the limit — prefer writing a state file and a summary before it does.
- `Edit` fails when the file was not read or `old_string` does not match; that is the stale-view signal — `Read` again and rebase. `Write` overwrites whole files, so read first.
- Bound `Bash`: pipe long output to a file, then `Read` a slice; use `run_in_background` plus `BashOutput` instead of a giant captured log.
- `TodoWrite` is your durable plan; write key decisions into `CLAUDE.md`/a state file so a `/compact` or session resume can recover them.
- Images: read only on demand; repeated reads add per-request cost until compaction.

## Apply in Codex

- No automatic compaction control in the same shape as DSH (unverified); manage the window yourself: keep outputs to files, read slices with `sed -n`, and summarize into a state file at phase boundaries.
- `apply_patch` failures ("context does not match") are stale-context signals: re-read the region, then patch narrowly.
- Put the budget rules in `AGENTS.md` (bound output, externalize state, re-read before patch, keep exact identifiers) so they survive context loss.
- Sandbox and approval modes do not change the token economics; a denied command still costs context, so avoid retry storms.

## Pitfalls

- **Reading a truncated result as complete.** The footer or omission notice says what you are missing — follow it.
- **Compacting without externalized state.** A summary written from memory loses exactly the identifiers you need.
- **Trusting a partial read as full knowledge.** Overwriting an unchanged file with a windowed view is allowed by the guard; it is still a mistake.
- **Treating spill paths as permanent.** Startup cleanup prunes old files; copy out anything that must survive.
- **Ignoring stale conflicts.** `FS_STALE_VERSION` means someone else changed the file; forcing your old content clobbers work.
- **Summarizing before pruning.** Trim oversized tool results first; it may remove the need to summarize at all.
- **Assuming compaction touched the system prompt or tools.** It never does; schema and prompt cost is fixed and paid every step.
- **Believing the token percentage is billing.** Four-chars-per-token underestimates code, CJK, and JSON; verify with provider usage.

## Evidence

| Claim | Source |
|---|---|
| Read caps, footer forms, streaming threshold, offset errors | `dsh-tool-fs/lib/index.js:16-19`, `52-58`, `69-112`, `212-217`; `dsh-tool-fs` README §Read result |
| Search caps and spill handoff | `dsh-tool-fs-search/lib/index.js:692-731`, `1031-1040`, `1220-1222` |
| Retention notices, retainers | `dsh-output-retention` README §Building the omission footer, §How the current tools use it |
| Spill budget, notice text, pass-through rules, failures | `dsh-spill-policy` README §What the model sees, §Which results are affected, §Best-effort failure behavior |
| Spill file layout, hint, cleanup | `dsh-spill-local` README §What you get back, §Where files land, §Startup cleanup |
| Pruner defaults and trigger ordering | `dsh-compaction-tool-result-pruner` README §Setting the size limits, §When trimming runs |
| Image offload durability | `dsh-compaction-image-offload` README §Use this package, §What you can observe |
| Compaction thresholds, retention, triggers, locking | `dsh-compaction-basic` README §Tuning when condensation starts, §Automatic triggers; `dsh-compaction` README §The surface contract, §Tool-pairing boundaries |
| Summary structure and rules | `dsh-compaction-basic/lib/index.js:233-280` |
| Token heuristics, projections, disposition | `dsh-token-meter` README §Measuring pressure, §Session projections, §Reading the numbers |
| Observation states, guards, remedies, resume behavior | `dsh-fs-observation-policy/lib/index.js:47-70`; `dsh-tool-fs/lib/index.js:466-478`; `dsh-fs-observation-policy` README §What changes for the model, §Known Limitations |
| Clock context lines, interval, zone policy | `dsh-time-context` README §What the model gets, §Configuration, §Model Experience |
