# Delegation: subagents, briefs, and supervision

Delegation is a context-budget trade: the child pays for its own working context, and you pay for one brief plus one result. Used well it isolates noise and buys parallelism; used badly it duplicates work and returns plausible prose nobody checked. This reference describes what DSH's subagent machinery actually guarantees, then gives a portable protocol for any host with a task/subagent facility.

## What the harness does (observed)

### The delegation surface

- Two model-facing tools, one per backend: `subagent` (fresh child) and `subagent_fork` (child seeded with this conversation). Each tool instance binds one provider name, one tool name, and one depth cap (`dsh-tool-subagent` README §Minimal configuration).
- A call **returns immediately** with `started subagent <childId>`; it does not wait for the work (`dsh-tool-subagent` README §Managed delegation; `lib/index.js:438`). Execution belongs to a managed activation owned by the runtime, not by the tool call.
- When the activation settles, the parent receives one **completion notice** in a user-role message: the child's non-empty final text, plus `Structured result: <JSON>` when a schema was requested. Empty closing text is reported literally (`dsh-subagent` README §Settlement notice).
- In-process spawn/fork children are **continuable**: they accept `send_message`, can be cold-resumed from storage, and keep a durable session. ACP, Claude Code, Codex, and SDK backends execute once and reject follow-ups (`dsh-subagent` README §Local and external children; §Known Limitations).
- Child composition is bounded by `maxDepth` (host default `1`); the cap is re-resolved on every request. At the cap the schema stays visible but each start is rejected with an errored result, and runtime context says so: `Delegation depth for \`subagent\`: current 1, maximum 1, remaining levels 0` (`dsh-tool-subagent` README §Runtime depth context).
- Capacity is also bounded: `maxActiveSubagents` (default `8`) counts live *and materializing* children per activation tree; at capacity, creation or cold resume rejects with `ACTIVATION_LIMIT_REACHED` and nothing queues (`dsh-subagent` README §Activation capacity; `lib/index.js:82`, `:1214`).
- A child's permission scope is **fixed at creation**. Every in-process child receives the delegation-scope statement telling it that approvals are rejected automatically and that the limitation must be reported back rather than worked around (`dsh-subagent` README §Child delegation-scope statement; `lib/index.js:362`).

### Fresh vs fork

- **Fresh (`spawn`)** starts with no parent history. The tool description is generated from `provider.inheritsParentContext`, so a fresh child's prompt parameter says it does not share the conversation and needs everything included (`dsh-tool-subagent` README §Context-sensitive wording; `lib/index.js:337–344`).
- **Fork (`fork`)** copies the parent's **completed** turns only. The parent's current in-flight turn is still open when a child starts and is never included; before the first completed turn the seed is empty and behaves like fresh (`dsh-subagent-fork-in-process` README §Seed boundary).
- A fork seed is a **one-time snapshot**. Later parent turns never reach the child, and there is no live context sharing (`dsh-subagent-fork-in-process` README §Known Limitations). Its prompt guidance is the inverse of fresh: build on the visible turns and state only what is new.
- Shipped fork tools do **not** expose child LLM route selection, because a different model would break reuse of the copied request prefix (`dsh-tool-subagent` README §Known Limitations).

### Steering, status, and interruption

- `send_message(agent_id, message)` steers a running target at its nearest step boundary, and starts or resumes an inactive one. It returns acceptance only — `message delivered to agent <agent_id>` with a `messageId` — never a reply (`dsh-tool-subagent-control` README §send_message, §Delivery result; `lib/index.js:48`).
- `interrupt_agent(agent_id)` stops only a **live local** target's current turn: queued messages stay parked, descendants keep running, and the child remains available. It returns when the stop is accepted, not when the target is quiet. Self, sibling, stale, and non-ancestor callers get errored results (`dsh-tool-subagent-control` README §interrupt_agent).
- `list_agents` reports `running` or `inactive` from the live registry. `inactive` means no turn is executing, whether loaded or stored; it says nothing about completion or outcome (`dsh-tool-subagent-control` README §Listing result).
- Messaging is **adjacent**: a parent may target its direct continuable children, a resident continuable child may target its direct parent, and the parent must be live. Siblings and deeper descendants are not message targets (`dsh-tool-subagent-control` README §Known Limitations).

### Parallel spawns

- All visible delegation tools share one guidance paragraph: start independent delegations together in one assistant message and keep working while they run (`dsh-tool-subagent` README §System prompt; `lib/index.js:516`). In practice the model spawns several children in one step, then does its own work until their notices arrive.

### When not to delegate

- **The subtask is small.** A one-file edit or a single lookup costs more in brief-writing and result-reading than doing it.
- **The work is the thinking you are doing now.** If you cannot write the brief without first resolving the design, resolve it yourself — a delegate cannot inherit your in-flight reasoning (a fork child never sees the current turn).
- **The answer must be verified piece by piece.** Delegation returns a summary; fine-grained verification is cheaper when you performed the work.
- **The work needs the user.** A child cannot ask the user: `ask_user_question` rejects a live child caller with `DELEGATED_CALLER`, so any unresolved decision comes back as prose you must re-ask (`dsh-tool-ask-user` README §When the call fails).
- **Depth or capacity is exhausted.** At zero remaining depth the tool rejects the start; at activation capacity, creation rejects rather than queues (`dsh-tool-subagent` README §Runtime depth context, §Managed delegation; `dsh-subagent` README §Activation capacity).
- **Two writers would touch one file.** That is a merge conflict with extra context cost, not parallelism.

### Choosing the mode

| Situation | Mode | Why |
|---|---|---|
| Subtask continues this conversation (review, follow-up, continuation) | fork | Child sees completed turns; state only what is new |
| Child must reason independently or must not inherit your assumptions | fresh | No conversation seed; brief must be self-contained |
| Child must outlive this turn and accept later instructions | fresh or fork in-process | Only in-process children are continuable |
| One-shot remote execution (ACP, Codex, Claude Code, SDK) | external | Executes once; no follow-ups, no cold resume |

## Portable protocol

### Rules

1. **Delegate only work that is self-contained, verifiable, and expensive enough to justify the handoff.** Good: an audit over many files, a scoped implementation in files you do not touch, independent research. Bad: a three-line edit, a decision that depends on the reasoning you are doing right now, or anything you cannot describe without "the thing we discussed".
2. **Choose the context mode deliberately.** Fork when the subtask continues this conversation (review, follow-up analysis, continuation). Fresh when the child must stand alone or must not inherit your reasoning. Never rely on a fork seeing the in-flight turn; never assume a fresh child knows anything.
3. **Write the brief as if the delegate has never seen the conversation — because it hasn't.** Objective, inputs with exact paths/commands, boundaries, required output format, acceptance criteria, constraints, and whether it may delegate further. For a fork, state only what is new and say so explicitly.
4. **Ask for a result, not a transcript.** Require the artifact, the evidence (commands run, paths, exit codes), and open questions. Never ask a child to "explain what you did" — its intermediate steps are its context, not yours.
5. **Parallelize only independent work, and launch it in one message.** Then continue your own work. Do not duplicate a running delegate's investigation; collect instead.
6. **Supervise with messages, not restarts.** Send a correction to a running child; send a follow-up to resume an inactive one. Interrupt only to stop a wrong direction, knowing that queued messages stay parked until the next send.
7. **Verify before accepting.** Read the artifact, run the checks, inspect the diff. A completion notice is a report, not a certificate.
8. **One writer per file.** Split delegates by disjoint file/directory scopes and state those scopes in the brief. Overlapping scopes are a coordination bug.
9. **Mind depth and capacity.** At zero remaining depth, do the work yourself. At capacity, wait for a child or reuse an existing one — do not retry a rejected start.
10. **Collect before answering.** Every delegated child's result must be in hand or explicitly abandoned before the final answer; interrupt what no longer matters.

### Template: subagent brief

```markdown
## Goal
<one verifiable outcome, in one sentence>

## Context
- Why: <one or two sentences of motivation>
- Inputs: <exact paths, commands, URLs, prior decisions>

## Scope
- You may modify: <paths / globs>
- Do not touch: <paths / areas>
- Do not delegate further; finish in this pass.

## Deliverable
- <artifact form: file path, patch, report>
- Acceptance: <checkable criteria>
- Include evidence: commands run, their output, files created.

## Constraints
- <no network / no installs / no destructive ops, unless allowed>
- <stack, style, compatibility requirements>

## If blocked
State what you tried, the exact error, and what you need. Do not retry a denied
operation through another route.
```

### Template: follow-up message

```text
Status check + correction, not a restart:
- Keep: <what is already correct; name the files/artifacts>
- Change: <the specific defect and the expected behavior>
- Evidence required: <command to run, output to paste>
- Stop condition: <when to report back; do not expand scope>
```

## Apply in Claude Code

Client behavior, not verified in this checkout (unverified).

- Use the `Task` tool (subagents) with a self-contained `prompt` and a short `description`; Claude Code children start **fresh**, so the brief is the only context they get. For shared context, point the child at a state file you wrote.
- Spawn independent subtasks by issuing multiple `Task` calls in a single message; each returns one final report, and the parent must assemble and verify.
- There is no live steering equivalent to `send_message` in the minimal surface: redirect by starting a follow-up task that includes the prior report, or resume the same subagent if the client exposes continuation. Treat `inactive`/idle as "not running", not "done".
- Keep the same discipline at smaller scale: verify the returned artifact yourself, and never accept "tests pass" without the pasted summary.

## Apply in Codex

Client behavior, not verified in this checkout (unverified).

- `codex exec "<prompt>"` is naturally a fresh child: separate process, no conversation seed. Write the brief to a file (`TASK.md`) and reference it by path so quoting cannot mangle it.
- Parallelism = multiple `codex exec` processes as background jobs, each with a distinct working directory or explicit write scope and its own log file; collect by reading the logs.
- There is no steering channel; a correction is a second exec whose prompt includes the prior handoff file. Keep the handoff bounded (summary + evidence + next step), not a transcript.
- Put standing delegation rules in `AGENTS.md`: what may be delegated, how to bound scope, and that the Lead reviews every diff.

## Pitfalls

- **Expecting a fresh child to know the conversation.** The most common failure: the brief says "as discussed" and the child invents the rest.
- **Over-briefing a fork.** Restating history it already has wastes the very context the fork was meant to preserve.
- **Treating `started subagent <id>` as the result.** It is an acknowledgement; the answer arrives later in the notice.
- **Treating `inactive` as success or as failure.** It only says no turn is executing; check the reported result.
- **Re-delegating a running subtask** because the first child went quiet. That doubles cost and creates conflicting writes.
- **Asking a child to ask the user.** `ask_user_question` rejects a live child caller with `DELEGATED_CALLER`; the child must surface the decision in its final result (`dsh-tool-ask-user` README §When the call fails).
- **Interrupt, then immediately expecting quiet.** Follow-ups accepted during cancellation convergence can stay queued until another waking send (`dsh-subagent` README §Known Limitations).
- **Deep nesting.** Delegation depth and activation capacity are separate limits; a chain of delegators exhausts both.

## Evidence

| Claim | Source |
|---|---|
| Tool returns `started subagent <childId>`, no waiting; activation owns execution | `dsh-tool-subagent` README §Managed delegation; `dsh-tool-subagent/lib/index.js:438` |
| Completion notice content, structured result, empty-closing wording | `dsh-subagent` README §Settlement notice |
| Fresh vs fork wording generated from `inheritsParentContext` | `dsh-subagent` README §Child presets; `dsh-tool-subagent/lib/index.js:337–344` |
| Fork seed = completed turns only, one-time snapshot | `dsh-subagent-fork-in-process` README §Seed boundary, §Known Limitations |
| Continuable vs one-shot backends; depth and capacity limits | `dsh-subagent` README §Local and external children, §Activation capacity, §Known Limitations |
| Depth-cap runtime text | `dsh-tool-subagent` README §Runtime depth context |
| Child permission scope fixed, `subagent:delegation` statement | `dsh-subagent` README §Child delegation-scope statement; `lib/index.js:362` |
| `send_message`/`interrupt_agent`/`list_agents` semantics and result lines | `dsh-tool-subagent-control` README §send_message, §interrupt_agent, §Listing result; `lib/index.js:48` |
| Parallel-spawn guidance sentence | `dsh-tool-subagent` README §System prompt; `lib/index.js:516` |
| Child cannot call `ask_user_question` | `dsh-tool-ask-user` README §When the call fails |
