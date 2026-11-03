# Orchestration: Agent Teams, the task board, and workflow scripts

One agent is a loop; several agents are a scheduling problem. The harness offers two distinct answers: **Agent Teams** — a Lead plus durable named teammates coordinating through messages and a shared task board — and **workflows** — a model-written JavaScript script that fans work across many short-lived subagents and returns one value. This reference covers both, plus the delivery and question tools that terminate the work.

## What the harness does (observed)

### The Team model

- Any ordinary runtime root is the implicit Lead of a Team whose id equals its session id; durable team state begins with the first member or task record, not with an explicit "create team" step (`dsh-experimental-agent-team` README §Team identity and roster).
- Members share one working directory and filesystem; edits are immediately visible to everyone. There is no worktree, no remote member, and no filesystem lock (`dsh-experimental-agent-team` README §Known Limitations; Team policy text in `dsh-experimental-tool-agent-team/lib/index.js:22`).
- The roster is flat and immutable: only the Lead creates teammates, names are permanent and never reused (a failed creation still consumes its name), and there is no rename or delete. `maxMembers` defaults to `16` (`dsh-experimental-agent-team` README §Teammates, §Smallest working setup).
- A teammate starts `fresh` (no Lead history) or `fork` (the Lead's completed turns captured once at creation). The creation request chooses.
- Status vocabulary: `running`, `inactive` (no turn executing, loaded or stored), `provisioning` (creation in progress), `failed` (creation failed). `inactive` explicitly does **not** imply success, failure, or completion (`dsh-experimental-tool-agent-team` README §What the model can do).
- Every member receives the same nine tools: `spawn_teammate`, `send_message`, `list_agents`, `wait_agent`, `interrupt_agent`, and `team_task_create` / `team_task_list` / `team_task_get` / `team_task_update`. Execution enforces role: only the Lead spawns and interrupts; any member messages any member and uses the board (`dsh-experimental-tool-agent-team` README §What the model can do).
- Members are addressed by `target`, not by session id; the same string is the `owner` filter for tasks (`dsh-experimental-tool-agent-team` README §What the model can do).

### The shared task board

- A task is a versioned snapshot: subject, description, optional `writeScopes` (normalized workspace-relative prefixes), optional `blocked_by` dependencies, and an owner. Every mutation carries the revision the caller last read; a stale write is rejected with `TEAM_TASK_STALE_REVISION` instead of overwriting (`dsh-experimental-agent-team` README §Shared task board).
- Readiness is derived: a task is claimable only when every task it depends on is complete. **Readiness never starts an owner** — nothing wakes a teammate because a blocker cleared (`dsh-experimental-tool-agent-team/lib/index.js:22`).
- Lifecycle: unowned → `claim` (sets owner, revision++) → `complete`; `release` returns it to the pool, `reopen` returns it to work, and the Lead can `reassign` to any member. Numeric ids are `task-<n>`, monotonic; exhaustion reports `TEAM_TASK_LIMIT`. Deleted tasks become tombstones and leave the active list. Deployment ceilings: `maxTasks` `256` active tasks, `maxMessageBytes` `65,536` per sent message, `maxMembers` `16` (`dsh-experimental-agent-team` README §Shared task board, §Smallest working setup).
- `writeScopes` produce **warnings** when two in-progress tasks plan to touch overlapping paths. They never block a claim and never authorize a write — Bash, formatters, and code generators bypass the filesystem version guard entirely (`dsh-experimental-agent-team` README §Shared task board, §Known Limitations).
- Ownership is never released automatically: inactivity, interruption, process exit, and failed work all leave the owner in place (`dsh-experimental-agent-team` README §Known Limitations).

### Messages, waiting, interruption

- `send_message` accepts a message into the target's inbox and returns acceptance — `{ "sent": true }` — not a reply. A running target is steered at its nearest step boundary; an inactive one is started or cold-resumed. A peer message arrives prefixed with its sender name (`dsh-experimental-agent-team` README §Model Experience; `dsh-experimental-tool-agent-team` README §What success and failure look like).
- `wait_agent` waits for one roster, task, message-acceptance, or live-status edge that occurs **after** the call, for 10 s to 1 h, and reports only whether it timed out. If no other member is running or provisioning it returns `noProgress` immediately and tells the caller to wake someone first. Re-list after every wake or timeout (`dsh-experimental-agent-team` README §Waiting and interruption; `dsh-experimental-tool-agent-team` README §What success and failure look like).
- `interrupt_agent` is Lead-only and cancels only a live teammate's current turn with the inbox kept: queued messages stay parked, task ownership is unchanged, descendants keep running (`dsh-experimental-agent-team` README §Waiting and interruption).

### Workflow scripts

- `workflow` is for work that fans out across many independent pieces — an audit over many files, a migration, multi-angle research, adversarial verification — and the usage guidance says to use it **only** when the user explicitly asks for a workflow or large multi-agent orchestration; one or two delegations stay plain subagent calls (`dsh-tool-workflow` README §System prompt, §Use this package).
- The call takes `meta` (`name`, `description`, optional `whenToUse` and `phases`), `script` (a plain JavaScript **body**, no `export const meta`, top-level `await`, ends with `return <json-value>`), optional `args` (a JSON object exposed as the `args` global), and optional `run_in_background`.
- Hooks (`dsh-tool-workflow/lib/index.js:140–148`):
  - `agent(prompt, opts?)` — one subagent to completion; resolves to final text, or to a validated object when `opts.schema` is given. The schema subset is object-rooted and limited to `type`, `properties`, `required`, `additionalProperties`, `items`, `enum`, `const`, `oneOf`. Resolves `null` when the child fails. Options: `label`, `phase`, `provider`, `model`.
  - `pipeline(items, ...stages)` — each item through the stages independently, **no barrier** between stages; each stage gets `(prev, item, index)`; a stage throw drops that item to `null` and skips the rest of its stages.
  - `parallel(thunks)` — run zero-argument functions concurrently and await all of them (a barrier); a throwing thunk resolves `null`.
  - `phase(title)`, `log(message)`, and the `args` global.
- Hook misuse — bad arguments, unknown options, unsupported schemas, tripped caps — ends the whole script rather than producing `null`. The script has **no filesystem, network, timer, or Node.js APIs**; the agents do the work (`dsh-tool-workflow/lib/index.js:148`).
- Foreground execution blocks the parent turn until the run settles and then returns `{ kind, runId, agentsStarted, result }`, rendered as `workflow "<name>" completed (<count> agent<s>).` plus the return value. Intermediate child messages never enter the parent conversation (`dsh-tool-workflow` README §Calling the tool, §What to expect during a run).
- `run_in_background: true` returns a job id immediately; the job's live output streams `phase()`/`log()` lines and the return value arrives with the completion notice (`dsh-tool-workflow` README §Background runs).
- Engine limits: `maxConcurrentAgents` (default `0` → CPU parallelism), `maxTotalAgents` (`1000`), `maxItemsPerCall` (`4096`), `syncTimeoutMs` (`5000`). Scripts run in a fresh Node process under the calling session's captured file policy; a runtime without confinement is accepted only for `danger-full-access`. There is no overall elapsed deadline; cancellation aborts the process and pending children (`dsh-workflow-ptc` README §Config, §Confinement and cancellation).

### Adjacent orchestration primitives

- `ralph` is a fixed foreground loop: one **fresh** child per round against one immutable objective, with only a bounded structured handoff crossing rounds and the workspace as long-term memory. Defaults: `maxRounds` `256`, `maxHandoffChars` `16384`. Completion is worker self-declaration, not independent verification (`dsh-tool-ralph` README §Summary, §Config, §Known Limitations).
- `present` declares existing regular files as deliverables: `files: [{ path, description? }]`, absolute paths recorded, contents never copied, `maxFiles` default `8`, and only the calling session can publish — a Lead must call `present` itself for files a teammate created (`dsh-tool-present` README §Use this package, §Model Experience).
- `ask_user_question` is blocking by default; `mode: timed` lets a deadline release the model while the question stays answerable, and a timed-out call returns `{ pending: true, callId }`. A live child caller is rejected with `DELEGATED_CALLER` and must surface the decision in its final result (`dsh-tool-ask-user` README §Summary, §When the call fails).

## Portable protocol

### Task-board protocol

1. **The Lead writes the board before spawning workers.** One task per deliverable; the description carries acceptance criteria, inputs, and evidence requirements.
2. **Set `writeScopes` to disjoint prefixes.** If two tasks must touch the same file, they are one task, or they are ordered with `blocked_by` — not run in parallel with a hope.
3. **Order with `blocked_by`, never with timing.** A blocked task is not claimed; the worker reports "not ready" rather than sleeping on it.
4. **Claim with the revision you read.** `get` → `claim(expectedRevision)` → work → `complete(expectedRevision)`. Re-read after any rejection; never overwrite from a stale copy.
5. **Work only inside your declared scope.** Files outside it are the owner's, and a shell redirect is not a lock.
6. **Completion carries evidence.** What changed, how it was verified, files touched — not just a status flip.
7. **The Lead reassigns explicitly.** Ownership never releases on failure or exit; a stuck task blocks its dependents forever until someone reassigns or reopens it.
8. **The Lead answers last.** Required teammates must have settled and the final diff must be reviewed before the final answer.

### Workflow-script skeleton

```js
// meta: { "name": "audit-modules", "description": "Audit N modules", "phases": [{ "title": "Audit" }] }
phase("Audit");
const items = args.files;            // wrap bare lists in an object field
const findings = await pipeline(items, async (item) => {
  return await agent(
    `Audit ${item} for <defect>. Return findings only; no prose.`,
    {
      phase: "Audit", label: item,
      schema: {
        type: "object",
        properties: { issues: { type: "array", items: { type: "string" } } },
        required: ["issues"], additionalProperties: false,
      },
    },
  );
});
const kept = findings.filter(Boolean);
return { audited: items.length, withIssues: kept.length };
```

- Use `pipeline` for staged fan-out, `parallel` only when a stage genuinely needs every prior result together.
- Filter `null` explicitly: a child failure is data, not an exception, but a hook misuse kills the run.
- Keep the return value small — it is rendered into the parent transcript and capped by `maxResultChars`.

### Team brief skeleton

```text
You are teammate "<name>". Team Lead: "lead".
Objective: <one verifiable outcome>.
Own task: <task-id> (claim it with the current revision before starting).
Write scope: <paths>. Do not touch: <paths>.
Evidence required: <commands, output, paths>.
When done: complete the task, then send the Lead a report under 300 words.
If blocked: state the blocker on the task and message the Lead; do not expand scope.
```

## Apply in Claude Code

Tool names below are from Claude Code 2.1.289; verify flags on your install.

- Claude Code 2.1.x ships native task tools (`TaskCreate`, `TaskGet`, `TaskUpdate`, `TaskList`) with `blockedBy`, owner, and status, plus an experimental agent-teams mode behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Use the native task tools where enabled; otherwise fall back to a board file (`TASKS.md` or one file per task with `owner:`, `status:`, `write_scope:`, `depends_on:` lines). The Lead edits the board; workers update only their own task file.
- Launch independent `Task` calls in one message and keep working; collect each report before the final answer. Claude Code subagents are fresh, so every brief must be complete and point at the board and the files.
- Use the native task list or `TodoWrite` for the Lead's own execution plan; the board file is for cross-agent state that must survive compaction.
- Deliverables: reference paths in the final reply; there is no `present` equivalent, so make paths absolute and explicit.

## Apply in Codex

Client behavior, not verified in this checkout (unverified).

- No teammate primitive: run several `codex exec` processes as background jobs, each with a prompt file, an explicit working directory, and a disjoint write scope; coordinate through the same board file.
- Encode readiness in the board (`status: blocked` + `depends_on`) and let the Lead start dependents after checking; a blocking wait inside a process is wasted time.
- Collect each process's log path and summarized result; the Lead runs the checks and reviews the combined diff.
- For genuine fan-out beyond a handful of items, write a small script that loops `codex exec` over a list with bounded concurrency, instead of hand-launching processes.

## Pitfalls

- **Treating `writeScopes` as a lock.** It is a warning system; two agents editing one file still lose writes.
- **Claiming from a stale revision.** The write is rejected, but a worker that ignores the rejection proceeds unprotected.
- **Reading `inactive` as done.** It only means no turn is executing.
- **Assuming a cleared blocker wakes someone.** Readiness is passive; the Lead must send or spawn the next worker.
- **Broadcasting coordination.** Peer messages are expensive context; the board is the durable channel and the message is the nudge.
- **A workflow script for two delegations.** The schema and script cost far more than two subagent calls.
- **Doing file or network I/O inside a workflow script.** There are no such APIs; the script orchestrates agents.
- **Using `parallel` where `pipeline` is meant.** A barrier wastes the concurrency the fan-out was for.
- **Forgetting `present`.** A teammate's file is not a deliverable until the Lead presents it.
- **Interrupting to "reset" a teammate.** The inbox stays parked and the task owner stays assigned; follow with a message and, if needed, a reassignment.
- **Answering while a teammate runs.** The Lead's final answer must wait for required members.

## Evidence

| Claim | Source |
|---|---|
| Team identity, roster rules, fresh/fork teammates, limits | `dsh-experimental-agent-team` README §Team identity and roster, §Teammates, §Smallest working setup |
| Nine tools, role enforcement, status vocabulary, `{sent:true}` | `dsh-experimental-tool-agent-team` README §What the model can do, §What success and failure look like |
| Team policy text (shared cwd, CAS protocol, Lead duty) | `dsh-experimental-tool-agent-team/lib/index.js:22` |
| Task CAS, readiness, `writeScopes` advisory, tombstones, limits | `dsh-experimental-agent-team` README §Shared task board, §Known Limitations |
| `wait_agent` window and `noProgress`, `interrupt_agent` keep-inbox | `dsh-experimental-agent-team` README §Waiting and interruption |
| Workflow usage gate and guidance text | `dsh-tool-workflow` README §System prompt, §Use this package |
| Hook contract and no-I/O rule | `dsh-tool-workflow/lib/index.js:140–148` |
| Result envelope, rendering, background runs | `dsh-tool-workflow` README §Calling the tool, §Background runs |
| Engine caps and confinement | `dsh-workflow-ptc` README §Config, §Confinement and cancellation |
| Ralph loop, handoff bound, self-declared completion | `dsh-tool-ralph` README §Summary, §Config, §Known Limitations |
| `present` path rules and session ownership | `dsh-tool-present` README §Use this package, §Model Experience |
| `ask_user_question` blocking/timed and `DELEGATED_CALLER` | `dsh-tool-ask-user` README §Summary, §When the call fails |
