# 03 — Planning, goals, todos, and persistence

Long work fails at the seams: a plan that exists only in the conversation dies at the first compaction, a task list that is never updated hides the real state, and an objective that is never written down is abandoned after the first interruption. DSH splits this into four durable mechanisms — `todo_write` for the step plan, plan mode for an approval gate, goal objects for a multi-turn objective, and scheduled reminders for deferred work. This reference documents each, then gives a portable planning protocol.

## What the harness does (observed)

### Todos: the step plan

- `todo_write` replaces the **entire** list on every call. Items are `{content, status}`; statuses are `pending`, `in_progress`, `completed`. There are no partial updates, per-item edits, priorities, or ids (`dsh-tool-todo` README, "What each call does", "Known Limitations").
- The model-facing description asks for one todo per concrete step, says to skip the list for trivial single-step work, requires exactly one `in_progress` unless the deployment allows parallel work, and asks for immediate completion marking (`dsh-tool-todo/lib/index.js:21-24`).
- Validation is strict: blank content, duplicate content, unknown item fields, or more than one `in_progress` when `allowParallelInProgress: false` all fail with stable error text (`lib/index.js:45-62`; `dsh-tool-todo` README, "Tool-call history and result").
- Success returns exact counts: `Updated todo list: <pending> pending, <inProgress> in progress, <completed> completed.` (`lib/index.js:167`).
- State is log-backed: each call appends a `todo/write` event, replay is last-write-wins, and the `todos` projection clears when the next turn starts while `turn/end` keeps the finished checklist visible in the UI (`dsh-tool-todo` README, "Session projection").
- The list is owned by exactly one agent session; subagents keep their own, and a non-agent caller is rejected (`dsh-tool-todo` README, "Single owner").
- Token cost scales with every full list submitted: the arguments stay in history until compaction. Keep lists short and stop resending completed work (`dsh-tool-todo` README, "Token effect").

### Plan mode: the approval gate

- Plan mode is entered with `/plan` (optionally `/plan <message>`, with ordered image/file attachments) and left with `/plan off`. A non-empty message is steered as the next user message under plan guidance; `/plan off` with attachments is rejected before any mode change (`dsh-plan-mode` README, "Entering and leaving plan mode").
- While active, the deployment's `section` text renders as the `plan:policy` prompt section at first-party order 500. Inactive mode contributes no text. The `section` config is required (`dsh-plan-mode` README, "Minimal configuration", "Model Experience").
- Plan mode is **guidance, not enforcement**: every tool stays callable, and the package does not filter capabilities. Real limits require sandbox mode and approval policy independently (`dsh-plan-mode` README, "When to choose it", "Known Limitations").
- The exit is reviewed: the agent calls `exit_plan_mode` with the complete plan as markdown starting with a `#` heading. The user approves (leave plan mode, carry out the plan from the next step), chooses "Keep planning" with optional feedback (the plan comes back in the tool result), or dismisses the review (`dsh-plan-mode` README, "The reviewed exit"; `lib/index.js:232-301`).
- A dismissal returns `{approved: false}`, renders a note that the user will reply, and concludes the turn without another model request (`dsh-plan-mode` README, "Exit tool schema and review exchange").
- The tool remains registered in both states; entering or leaving changes only the prompt section, never the tool catalog. An approved review records a silent pending exit that is appended at the next accepted in-turn pre-step, so plan guidance persists for the rest of the current tool batch (`dsh-plan-mode` README, "The exit tool").
- State is one log-only whole-value `plan/mode` event; the last logged value is the state. It survives session resume and forks by folding the log. Pending selections are process-local and can be lost if the process exits before the next accepted pre-step (`dsh-plan-mode` README, "Durable state and step-boundary appends", "Known Limitations").
- A live child agent cannot open the review; it must carry the unresolved decision into its final result (`dsh-plan-mode` README, "Known Limitations").

### Goals: the long-running objective

- One current goal per session, with four durable phases — `active`, `paused`, `blocked`, `complete` — plus a process-local `armed`/`disarmed` flag for automatic continuation (`dsh-goal` README, "Drive the lifecycle").
- Verbs: `create` (objective + round cap), `edit`, `pause`, `resume`, `complete`, `block` (stable lower-kebab code + explanation), `clear`. Pause, complete, block, and clear disarm continuation; resume accepts a stopped goal or an active but disarmed one only while the round cap has capacity (`dsh-goal` README).
- Every mutation is a compare-and-set against the exact `{id, revision}` from `get()`; a stale view is rejected instead of silently overwriting newer state (`dsh-goal` README, "Observing a goal").
- State is event-sourced in the session log (`goal/change`, with a revisioned tombstone for clear). Goal state survives resume and fork, including revisions and admitted round count; automatic continuation does **not** — every session-start edge disarms an active goal (`dsh-goal` README, "What survives and what does not").
- Default round cap is 256 (`defaultMaxGoalRounds`); the cap counts rounds, not tokens, money, or time (`dsh-goal` README config table, "Known Limitations").
- Model tools: `get_goal` returns state plus the id and revision; `create_goal` is for a long-running objective inferred from a direct human request, not single-turn work; `update_goal` performs the verbs (`dsh-tool-goal/lib/index.js:123-196`).
- Authority rules: `edit`, `pause`, and `resume` require a direct human turn on a top-level agent. `complete` and `blocked` are also allowed during the current automatic goal round. `blocked` is rejected before the configured minimum round count and requires a concrete `blocked_reason` (`dsh-tool-goal/lib/index.js:57-80`, `344-366`).
- Blocked criteria in the model guidance: the same blocking condition must persist for at least N consecutive goal rounds (default **3**), and the reason must name that concrete condition; difficulty, uncertainty, or "more work remains" is not blocked (`dsh-tool-goal/lib/index.js:115`, `195-197`).
- On `complete`/`blocked` during an automatic round, a deferred wrap-up context asks the model to write the closing message — outcome, verification evidence, remaining work, or the blocker and what is needed — and explicitly tells it not to call more tools in that run (`lib/index.js:89-96`).
- Automatic continuation (`dsh-goal-round-driver`) queues one `<goal_round>` prompt when the agent is idle, the goal is active and armed, and capacity remains. The prompt quotes the objective as JSON, states `Round: n/max`, and tells the model to treat the workspace, tool results, and durable session state as authoritative, make concrete progress, verify it, and only mark complete with evidence (`dsh-goal-round-driver/lib/index.js:11-18`).
- Each round enters as a goal-sourced user message on a distinct request series; only an entered goal message consumes a round, and human input takes precedence. Continuation stops on completion, pause, blocking, max-tokens turn end, durability failure, cancellation, plugin unload, or cap exhaustion — at the cap it records a blocker with code `round-limit` (`dsh-goal-round-driver` README, "What each round does", "When continuation stops").
- After resume, fork, or mounting the driver over an existing agent, an active goal stays disarmed until a human explicitly resumes it; cancellation pauses at the next idle point rather than restarting (`dsh-goal-round-driver` README, "After resume, fork, or unload").

### Scheduled reminders

- Four tools: `schedule_create`, `schedule_list`, `schedule_update`, `schedule_delete`. Each acts on the calling agent's Session; storage and delivery belong to the Host service (`dsh-tool-schedule` README, "The four tools").
- `schedule_create` needs a non-empty prompt, a title of at most 120 characters, and exactly one of `after_seconds`, `at`, `every_seconds`, `daily`, `weekly`, or `cron`. `schedule_update` replaces title, prompt, or timing in place; `after_seconds` is create-only (`dsh-schedule` README, "Use this package").
- Wall-clock selectors take explicit IANA zones. Missing local times/dates from DST gaps are skipped, repeated local times fire once at the earlier instant, recurring tasks contribute only their **latest missed occurrence** after downtime, and the cron dialect is five-field Vixie (minimum one minute) (`dsh-schedule` README, "Use this package").
- Delivery is a follow-up message injected into the original Session; it commits only after the Session acknowledges a flush, so delivery requires the Host Web Session controller and persistence. Active and inactive tasks remain inspectable until explicit deletion (`dsh-schedule` README, "Summary").
- Archiving a Session with active reminders is refused until they stop; stopping them deletes them, and unarchiving does not bring them back (`dsh-schedule` README, "Use this package").

### What survives compaction and context loss

| State | Durable store | After compaction | After resume/fork |
|---|---|---|---|
| Todo list | `todo/write` session events (last-write-wins) | Event survives; the model's own call arguments may be shadowed, so re-issue the list when unsure | Projection rebuilds from log; list clears at the next turn start |
| Plan mode | Log-only `plan/mode` event | Yes — folds from the log | Yes; forked agents inherit logged state |
| Goal | Log-only `goal/change` events | Yes — strict replay reads the log | Yes, including rounds/revisions, but automatic continuation is disarmed |
| Schedule | Host task store, not the session log | Unaffected | Unaffected; bound to the original session |
| Notes kept only in chat | Nothing | **Lost** | **Lost** |

- The common thread: plan mode, goals, and todos are event-sourced, so compaction (which replaces surface messages) does not erase them. Free-form prose in the conversation has no such protection.
- After compaction the model still must re-read those states through the corresponding tools or files; a projection existing in the UI is not the same as the model knowing it.

## Portable protocol

1. **Recon before plan, plan before mutation.** Read-only exploration first; for large, ambiguous, or destructive work write the plan down and get approval before the first mutation.
2. **Keep the plan in a file, not in the chat.** Create `PLAN.md` (or equivalent) with context, ordered steps, files/areas, verification, and risks. The plan must be sufficient for a fresh agent to execute.
3. **Gate execution on explicit approval.** Present the plan verbatim; approved → execute from the next action; feedback → revise and re-present; dismissed → wait for the user. Do not "start small" while approval is pending.
4. **Todos are the working plan.** One concrete imperative per item ("add timeout to fetch in src/api.ts", not "improve API"), one `in_progress` at a time, mark complete immediately, and rewrite the whole list when the plan changes.
5. **Use a goal only for a multi-turn objective.** Single-turn work does not need a goal; a goal without measurable completion criteria is a wish.
6. **Define completion and blocking up front.** Done criteria are verifiable checks. Blocked requires the same concrete condition across at least three consecutive attempts plus a named reason; difficulty and remaining work are not blockers.
7. **Resume explicitly.** After a context loss, resume, or fork, re-arm any continuation deliberately and restate the objective; do not assume it kept running.
8. **Persist at boundaries.** Update the state file after each phase, before compaction, and before ending a turn that leaves work in progress.
9. **Schedule deferred work as a reminder, not a note.** One reminder per follow-up, with an absolute deadline or a wall-clock rule in an explicit zone.
10. **Never widen scope silently.** A changed objective is a user decision, not an implementation detail.

Plan artifact template:

```markdown
# Plan — <task name>

## Context
- User request: <one or two sentences>
- Constraints: <stack, compatibility, scope boundaries, deadlines>
- Non-goals: <what this must not touch>

## Steps
1. <step> — files: <paths> — verification: <how you will know>
2. ...

## Risks / unknowns
- <risk> → <mitigation or question>

## Verification
- <commands / checks that must pass before claiming done>
```

Goal definition template:

```markdown
Objective: <one concrete, verifiable outcome>
Done criteria: <checks that prove it>
Non-goals: <explicit exclusions>
Round budget: <n rounds>   Stop conditions: <cap / repeated blocker / max-tokens>
Current round plan: <one action for this round>
Evidence so far: <artifacts inspected or produced>
```

Approval-gate pseudo-loop:

```text
draft plan -> present plan (verbatim)
  approved  -> execute steps in order; verify each
  feedback  -> revise plan; present again (do not execute in between)
  dismissed -> stop; the user will reply
```

## Apply in Claude Code

- Plan mode + `ExitPlanMode` is the native approval gate: explore read-only, write the plan with a `#` heading, request approval, then execute. Feedback returns as a tool result and the plan must be revised and re-presented.
- `TodoWrite` is the whole-list replacement tool; keep one `in_progress`, use imperative one-line items, and update at each real transition. It is not a goal.
- For long objectives, use `GOAL.md` with done criteria and round budget (or the host's goal feature if present); re-arm after resume by re-reading it. Add a stop condition to avoid endless loops.
- Scheduled work: Claude Code has no native durable reminder (unverified); use an external scheduler (cron/CI) or record a dated next action in the state file, and create the reminder rather than a note.
- Shared work: use Claude Code's native task tools (`TaskCreate`/`TaskUpdate`, `blockedBy`, owner) when enabled, otherwise a board file — dependency order, one owner per file scope, explicit completion. Never let two agents share a todo list.

## Apply in Codex

- Planning lives in files: write `PLAN.md` and keep it authoritative; `AGENTS.md` should state that risky mutations require an approved plan.
- Non-interactive runs (`codex exec`) have no review dialog, so the approval step becomes: stop, write the plan, and wait for a human-approved follow-up run.
- Codex exposes a `goals` feature (verify with `codex features list`); plan/todo tracking and reminders are version-dependent. Use the state file and an objective file with done criteria, an external scheduler where no tool exists, and re-read them at the start of every session.
- Sandbox read-only mode is a practical recon gate: explore there, then switch modes to execute the approved plan.

## Pitfalls

- **Treating plan mode as a permission system.** It only changes prompt text; tools remain callable.
- **Forgetting the `#` heading.** `exit_plan_mode` rejects a plan that does not start with a markdown heading.
- **Assuming todos persist across turns.** The projection clears at turn start; the log keeps history, not a live list.
- **Confusing todos with goals.** Todos are per-turn steps; goals span rounds and need explicit completion.
- **Marking a goal complete without evidence.** The evaluator is the caller — "it should work" is not completion.
- **Marking blocked too early.** A blocker must be the same concrete condition for at least three consecutive rounds and must be named.
- **Expecting continuation after resume.** Goals are disarmed on every session-start edge; a human must resume.
- **Planning in chat only.** A compaction that shadows the plan leaves you executing from memory.
- **Double-scheduling a reminder.** Recurring reminders deliver only the latest missed occurrence, but re-creating a reminder after a crash can still duplicate.
- **Opening the plan review from a child agent.** Live children cannot; carry the decision up.

## Evidence

| Claim | Source |
|---|---|
| Todo replacement, statuses, validation, result text, projection clearing | `dsh-tool-todo` README §What each call does, §Session projection, §Tool-call history and result; `lib/index.js:21-62`, `167` |
| Todo single-owner scope and token cost | `dsh-tool-todo` README §Single owner, §Known Limitations, §Token effect |
| Plan mode entry/exit, guidance-only, prompt order, config | `dsh-plan-mode` README §Entering and leaving plan mode, §Minimal configuration, §Model Experience, §Known Limitations |
| Exit tool review flow, dismissal, pending exit | `dsh-plan-mode` README §The reviewed exit, §The exit tool, §Exit tool schema and review exchange; `lib/index.js:232-301` |
| Plan state durability and resume/fork | `dsh-plan-mode` README §Durable state and step-boundary appends, §Session projection unit |
| Goal phases, verbs, CAS, round cap, event sourcing | `dsh-goal` README §Drive the lifecycle, §Observing a goal, §What survives and what does not, §Design |
| Goal tool authority, blocked threshold, wrap-up context | `dsh-tool-goal/lib/index.js:57-96`, `115`, `195-197`, `344-366`; `dsh-goal-round-driver` README §What each round does |
| Goal round prompt, reservation, stop reasons, disarm-after-resume | `dsh-goal-round-driver/lib/index.js:11-18`, `99-171`; `dsh-goal-round-driver` README §What each round does, §When continuation stops, §After resume, fork, or unload |
| Reminder selectors, title rules, wall-clock rules, delivery | `dsh-schedule` README §Use this package, §Summary; `dsh-tool-schedule` README §The four tools |
| Reminder lifecycle limits | `dsh-tool-schedule` README §Known Limitations; `dsh-schedule` README §Known Limitations |
