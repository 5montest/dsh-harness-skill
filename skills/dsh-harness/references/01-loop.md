# 01 — Agent loop, tool execution, and failure recovery

A turn is not one model request. DSH runs a turn as a sequence of **steps**, where each step is one request plus the tool batch it emits. That structure explains the rules you must follow: batch independent reads in one step, never parallelize conflicting mutations, treat tool errors as data rather than fatal events, and know exactly what "retry" means after a crash. This reference documents the observed mechanics, then gives a portable protocol for Claude Code and Codex.

## What the harness does (observed)

### Turn and step lifecycle

- A turn opens with a durable `turn/start`; each step appends `step/start`, sends one model request over the session's derived history and visible tool schemas, then appends `step/end` in a `finally` even when the step throws (`dsh-agent-loop` README, "What a step does").
- Before a step enters, the `agent/pre-step` waterfall may return `{kind:'reject'}` or `{kind:'enter', messages}`. A reject ends the turn as `blocked`; an empty first batch ends it as `completed` without a request (`dsh-agent-loop/lib/index.js:953-968`; `dsh-agent` README, "Step admission").
- A step that produces no tool calls completes the turn. A step with tool calls dispatches them, commits one `tool/result` per call **in model order**, and returns `null` so the loop proceeds to another step (`dsh-agent-loop/lib/index.js:1148-1167`).
- A tool result can declare `concludesTurn`; the loop then ends the turn as completed even though tool calls ran (`lib/index.js:573`, `1167`).
- Tools may defer extra model-facing context onto the next step (steering, wrap-up notices, answer continuations). The loop splices these into the next-step inbox, which is also why a turn can continue with another step after its tool batch finishes (`lib/index.js:1166`, `1000-1008`).
- When a step completes and no next-step input is pending, `agent/turn-stopping` runs; a listener may steer to keep the turn open. If no input is added, the turn closes (`lib/index.js:1000-1007`).
- After `turn/end`, a non-empty inbox starts a **new** turn with the step counter reset to 0 (`lib/index.js:1037-1041`). Queued user prompts never share a turn with the previous one.
- `turn/end` records a reason: `completed`, `blocked`, `max-tokens`, `error`, or `aborted` with a cause kind of `user`, `parent`, `disposed`, or `hook` (`lib/index.js:1010-1036`; `dsh-agent-loop` README, "Failure and cancellation").
- There is **no built-in turn or step budget**: tool calls and steering keep the current turn alive. Bounding runaway turns is an extension-layer policy, e.g. cancel from `agent/turn-stopping` (`dsh-agent-loop` README, "Known Limitations").

### Parallel-safe vs exclusive tool calls

- Each call is classified before dispatch through `ctx.tools.executionMode()`: only an exact `true` from the tool's `isConcurrencySafe(args)` is parallel; unknown, hidden, undeclared, invalid, or throwing classifiers fall back to exclusive (`dsh-tools/lib/index.js:3146-3161`).
- Parallel-safe calls may overlap up to `maxParallelToolCalls` per step, default **10**; `1` restores serial dispatch. The value is a volatile config sampled for the next tool group (`dsh-agent-loop` README config table; `lib/index.js:1554`).
- Calls are taken in model order. A call reclassified as exclusive **before it starts** waits for the current pool to drain and acts as an ordering barrier for everything after it (`lib/index.js:543-550`, `618-629`).
- Results and attached contexts commit in model order even when executions finish out of order; the scheduler holds a slot array until the preceding call has committed (`lib/index.js:565-576`).
- On abort, no new calls start; started calls settle and their results commit; every unstarted call gets a synthetic `tool/call` + `tool/result` pair with code `ABORTED_BEFORE_DISPATCH` and text `Error: tool call aborted before dispatch` (`lib/index.js:646-679`).
- A scheduler failure drains in-flight dispatches and rethrows so the owning step records recovery results instead of losing history (`lib/index.js:541-549`, `641-645`).
- Classification is unary: a tool whose safety depends on sibling calls or shared resources must stay exclusive (`dsh-agent-loop` README, "Known Limitations").

### The guarded tool pipeline

- Fixed order: `tools/pre-execute` (extensible allow/deny/ask) → monotonic `ctx.tools.guard()` guards → `tools/execute` wrappers (timeout, retry) → `tools/post-execute` → definition-owned `finalizeContent` → observe-only `tools/result` (`dsh-tools` README, "Design concept").
- A guard denial is final for the call; no later listener can turn it back into permission. `pre-execute` deliberately cannot rewrite arguments, because logged args must equal executed args (`dsh-tools` README, "Enforce policy on calls", "Known Limitations").
- Unknown and throwing tools become structured `UNKNOWN_TOOL` errors. Denials, wrapper failures, tool failures, and `TOOL_TIMEOUT` are result states, so an ordinary tool failure does **not** end the turn (`dsh-tools` README, "Execution and cancellation").
- Model-visible failures are exactly `Error: <message>`; structured error detail stays in metadata, not model text (`dsh-tools` README, "Tool-call history and results").

### Failure recovery result codes

- Before a failed step closes, every unanswered assistant tool call receives a recovery result. A recorded `tool/call` with no committed result gets `TOOL_OUTCOME_UNKNOWN`; a request with no call record gets `TOOL_NOT_STARTED` (`dsh-session/lib/index.js:726-733`; `dsh-agent-loop` README, "Failure and cancellation").
- `TOOL_OUTCOME_UNKNOWN` tells the model the outcome is unknown and permits retry only for read-only or idempotent work; possible side effects require verifying external state or asking the user (`dsh-session/lib/index.js:732`).
- `TOOL_NOT_STARTED` tells the model the call was interrupted before the harness recorded it as started, so retrying is reasonable if the work is still needed (`dsh-session/lib/index.js:733`).
- Committed results stay intact, started dispatches settle before recovery, and the turn retains its original failure; recovery does not rewrite already-closed historical turns (`dsh-agent-loop` README, same section).
- Cancellation has its own more specific code: `ABORTED_BEFORE_DISPATCH` before the body ran; after invocation, cancellation replaces only a *successful* outcome with `ABORTED`. Denials, wrapper failures, tool failures, and timeouts keep their own codes (`dsh-tools` README, "Execution and cancellation").

### Retries and timeouts

- A model-request failure reaches the `agent/request-error` waterfall; a listener returning `{kind:'retry'}` re-runs the failed step in the **same open turn over the same durable history**. Retries reuse the rendered assembly: no second prompt assembly, pre-step, or user admission (`dsh-agent` README, "Intercept or observe work"; `dsh-agent-loop/lib/index.js:1119-1147`).
- `dsh-llm-retry` implements the executor. Normal mode: five retries for `EMPTY_RESPONSE`, `RATE_LIMIT`, `SERVER`, `TIMEOUT`, `TRANSPORT` with exponential backoff from 500 ms to 10 s and 10% jitter. Always mode retries every model-request failure without an attempt limit, stopping only on success, cancellation, or disposal. Provider `Retry-After` may replace local backoff; each scheduled retry is durable before its wait (`dsh-llm-retry` README, "Use this package", "What you can observe").
- Direct `ctx.llm.stream()` calls stay single-attempt; retry exists only for the durable step boundary (`dsh-llm-retry` README, "When to choose it").
- Tool `timeoutMs` on a definition is declarative only; the registry never enforces it. `dsh-tool-call-timeout-policy` arms a cooperative deadline, swaps the derived signal onto the execution, and maps expiry to `isError` with `Error: tool call timed out after <ms>ms` and `{name:'ToolTimeoutError', code:'TOOL_TIMEOUT'}` (`dsh-tool-call-timeout-policy` README, "What you get"; `lib/index.js:93-105`).
- Only tools that declare a limit are covered. Shipped `web_fetch`/`web_search` default to 30,000 ms via their plugin config; shipped `bash`, `read`, `write`, and `edit` declare none (`dsh-tool-call-timeout-policy` README, "Setting it up").
- Timeouts are cooperative, not hard kills: a tool that ignores `exec.signal` keeps running and the caller keeps waiting, so no timeout result appears until it settles (`dsh-tool-call-timeout-policy` README, "When to choose it").

### Repeated-call detection

- `dsh-repeat-tool-reminder` counts **consecutive** calls with the same tool name and canonicalized arguments (deep JSON key-sort before stringify). Default thresholds are 3, 5, 8 (`dsh-repeat-tool-reminder/lib/index.js:2118-2125`, `2223-2239`).
- At the first threshold it injects a gentle reminder to analyze the previous result and try a different approach; at later thresholds a detailed reminder names the tool, the consecutive count, and a truncated argument preview, and forbids repeating that exact call (`lib/index.js:2133-2141`).
- Reminders arrive as model-facing context attached to the tool result, not as a turn-terminating error; denied calls also count, and tools not tracked by `include`/`exclude` patterns are transparent — they neither extend nor reset the chain (`lib/index.js:2210-2233`).

### Cancellation semantics

- Cancellation is cooperative. `agent.cancel(cause)` aborts the current activity and, unless `keepInbox` is set, clears queued and steering work; there is no step-only abort that keeps the turn running (`dsh-agent` README, "Known Limitations").
- A cancelled stream finalizes text already delivered to the user rather than discarding it; cancellation before a tool body is invoked yields `ABORTED_BEFORE_DISPATCH` rather than a fabricated success (`dsh-agent-loop` README, "Summary"; `dsh-tools` README, "Execution and cancellation").
- Undispatched model tool calls after cancellation still receive paired synthetic results, so a later request replays valid tool history instead of dangling calls (`dsh-agent-loop` README, "Undispatched calls after cancellation").

### When to continue vs stop

- Continue when a step produced new evidence, when tools deferred context or input remains in the inbox, or when the definition of done is not yet verified.
- Stop when the model emitted no tool calls (final answer), a result declared `concludesTurn`, the turn ended `max-tokens`, the run was cancelled, an unrecoverable error closed the turn, or the done criteria are verified.
- Stop-and-replan when the same failure recurs twice with no new information, when identical calls are being repeated (see reminder thresholds), or when the loop is burning steps without producing an artifact.

## Portable protocol

1. **Step = one request.** Before each request, rebuild state from durable artifacts (files, logs, task lists), not from remembered conversation. If you cannot cite the artifact, re-read it.
2. **Batch independent reads in one step; serialize writes.** Never issue two file mutations that touch the same file or directory in one batch — treat writes as exclusive barriers.
3. **Cap fan-out.** Keep concurrent parallel-safe calls at or below ~10. If a call's safety depends on another call's result, put it in a later batch.
4. **Preserve submission order mentally.** Parallel execution does not reorder results; commit reasoning in the order you submitted.
5. **Treat every tool error as data.** Read the message, classify it (policy / timeout / transient / logic), and only then decide. Never treat a nonzero exit or error result as automatic failure of the task.
6. **Retry discipline.** One retry for transient/environmental failures. Permission denials are never retried through another route. Unknown outcome: verify external state first; retry only if the operation is read-only or idempotent.
7. **Break identical-call loops.** After 3 identical calls, stop and re-read the result; after 5, change approach or ask. Never a 6th identical attempt.
8. **Deadline every long call.** State the expected duration, and treat a timeout as a result: inspect state, then retry only if safe.
9. **Cancel cleanly.** Stop starting new work, let in-flight work settle, and record which calls were skipped and which completed.
10. **Close the turn deliberately.** A turn ends when no pending work remains and the done criteria are evidenced — not when the output looks plausible.

Step ledger template (keep it in your working notes, not in the final answer):

```text
STEP <n> — intent: <one line>
calls: <name(args-hash)> × <batch>   parallel-safe: <yes/no>
result: <what changed / what was learned>
retry budget used: <0/1> for <call>
decision: continue  -> next: <call>
        | stop      -> because: <done criterion verified | blocked>
```

Failure triage table:

| Symptom | Meaning | Action |
|---|---|---|
| Permission/denial error | Policy decision, not transient | Stop; escalate or change plan. Never route around it. |
| Timeout result | Deadline hit; tool may still be running | Inspect external state; retry only if idempotent. |
| Outcome unknown | Crashed mid-call, no committed result | Verify side effects first; then retry or report. |
| Not started | Interrupted before dispatch | Safe to retry if still needed. |
| Aborted before dispatch | Cancelled before the body ran | Safe to retry when work resumes. |
| Same error twice | No new information | Re-plan or ask; do not repeat blindly. |

## Apply in Claude Code

- A Claude Code turn is your prompt plus the assistant/tool_result exchange; one message with several `tool_use` blocks is the equivalent of a DSH step. Batch independent `Read`/`Grep` calls in one message; never batch two `Edit` calls to the same file.
- Tool errors arrive as `tool_result` content, not exceptions: read them and adjust. A failed `Edit` ("file has not been read", "string not found") is a stale-view signal — `Read` again, rebase, retry.
- Background `Bash` commands: capture the id, keep working, collect output before the final answer. Long output should be redirected to a log file and sliced with `Read(offset, limit)`.
- Hooks (`PreToolUse`/`PostToolUse`) can deny calls, but treat denials as final, not something to bypass with a different tool.
- Claude Code does **not** synthesize `TOOL_OUTCOME_UNKNOWN`/`TOOL_NOT_STARTED` markers. After an interrupted session, treat every in-flight call as unknown and verify state yourself.
- Use `TodoWrite` as the step ledger and stop conditions; there is no built-in step budget, so your own budget rule is required.

## Apply in Codex

- Codex exposes shell and `apply_patch`, so read-before-write is your discipline: locate with `rg -n`, read a bounded region with `sed -n 'a,bp'`, then patch narrowly. A patch that fails to apply usually means stale context — re-read before retrying.
- Map "parallel-safe" to read-only shell commands; sequence anything that mutates the workspace or external state.
- Approval/sandbox modes are the policy gate: a denial is a decision. Do not retry a denied command with a different spelling or a wrapper.
- Put retry and timeout rules in `AGENTS.md` (one transient retry, no retry on denials, same error twice means re-plan) so they survive context loss.
- Codex has no documented built-in repeat-call reminder or per-tool timeout policy (unverified); enforce both yourself: bound every command with an explicit timeout and stop after three identical invocations.

## Pitfalls

- **Assuming one response = one tool call.** Several calls in one step can run concurrently; a shared resource is a race, even when results come back ordered.
- **Retrying after an unknown outcome.** This is how duplicate side effects happen; verify state first.
- **Treating "inactive"/"completed" as outcome.** A stopped process, subagent, or teammate has not necessarily succeeded; check the artifact.
- **Letting a turn run unbounded.** DSH has no turn budget; a loop without a stop rule will burn context and time.
- **Ignoring the reminder.** The third identical call is the signal; the fifth is a mistake.
- **Reading a timeout as "the tool never ran."** It ran; it just did not finish within the budget.
- **Killing work mid-write.** Cancel means "stop starting, settle started"; killing in-flight mutations can leave partial state.

## Evidence

| Claim | Source |
|---|---|
| Turn/step loop, turn-end reasons, retry reuse, no turn budget | `dsh-agent-loop` README §What a step does, §Turn and step flow, §Failure and cancellation, §Known Limitations; `lib/index.js:937-1042`, `1119-1167` |
| Pre-step decisions and empty-batch behavior | `dsh-agent` README §Step admission; `dsh-agent-loop/lib/index.js:953-968` |
| Parallel pool, exclusive barriers, ordering commits | `dsh-agent-loop/lib/index.js:543-661`; `dsh-agent-loop` README §Use this package (config table) |
| Fail-closed execution mode classification | `dsh-tools/lib/index.js:3146-3161`; `dsh-tools` README §Known Limitations |
| Pipeline order, guards, `UNKNOWN_TOOL`, error rendering | `dsh-tools` README §Design concept, §Enforce policy on calls, §Execution and cancellation, §Tool-call history and results |
| Recovery codes and model-facing text | `dsh-session/lib/index.js:720-734`, `885-888`; `dsh-agent-loop` README §Unanswered calls after step failure |
| Retry policy modes and durability | `dsh-llm-retry` README §Use this package, §What you can observe |
| Timeout enforcement and covered tools | `dsh-tool-call-timeout-policy` README §What you get, §Setting it up; `lib/index.js:93-105` |
| Repeat-call thresholds and reminder text | `dsh-repeat-tool-reminder/lib/index.js:2118-2141`, `2223-2239` |
| Cancellation scope (`keepInbox`, no step-only abort) | `dsh-agent` README §Known Limitations, §Drive an agent's conversation |
