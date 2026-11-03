# Prompt architecture: how the model-facing prompt is composed

DSH does not have "the system prompt" as one editable file. It assembles one ordered prompt per model step from a registry: fixed identity, deployment persona, policy sections, per-tool guidance, generated SDK text, and workspace context — each contributed by the plugin that owns the fact. Understanding the composition rules is what makes a skill, a persona, or a tool description portable instead of host-specific.

## What the harness does (observed)

### One registry, ordered sections

`ctx.systemPrompt` is a registry plus a cooperative assembly pipeline. `assemble()` merges the global layer with the requested agent scope, canonicalizes sections by numeric order then by name, runs a scope-filtered waterfall, and produces the section list, tool schemas, and resolved variables; `renderPrompt()` interpolates, drops empty sections, and joins with blank lines (`dsh-system-prompt` README, "Assembly and rendering").

First-party orders are fixed constants, deliberately sparse so plugins can slot between them (`dsh-system-prompt/lib/index.js:10-43`):

| Order | Section | Role |
|---|---|---|
| −1000 | `HARNESS_IDENTITY` | Fixed opener naming the harness; omitted only when a deployment owns the whole prompt |
| 0 | `DEPLOYMENT_PERSONA_PREFIX` | Deployment persona (includes the model-name introduction) |
| 500 | `PLAN_POLICY` | Plan-mode policy; empty unless plan mode is active for that agent |
| 600 | `TEAM_POLICY` | Team/Lead-teammate policy; present only when a team is composed |
| 800 | `PTC_ONLY` | Under `run_code` presentation: what may be called directly |
| 900 | `FILE_REFERENCE` | `@path` reference semantics |
| 1000–3100 | per-tool guidance | `tool:bash` 1000, `tool:pwsh` 1010, read 1100, write 1200, edit 1300, glob 1400, grep 1500, jobs 1600, terminal 1700, web_search 2000, web_fetch 2100, session_query 2300, goal 2400, workflow 2600, ralph 2700, subagent 2800, MCP_SERVERS 3100 |
| 5000 | `TOOLS_SDK` | Generated SDK block (PTC only); interpolation disabled |
| 9000 | `DELIVERABLE_FILE_REFERENCES` | Deliverable-linking rules |
| 9900 | `STRUCTURED_OUTPUT` | Structured-output contract |
| 10000 | `HARNESS_SOURCE` | Where the DSH checkout is; value-free |
| 10100 | `WEB_SURFACE` | "This page" means this GUI; value-free |
| 10200 | `DEPLOYMENT_PERSONA_SUFFIX` | Suffix after all first-party guidance |

- Equal orders sort by code-unit name order. Repository-owned contributors resolve their slot through `getSectionOrder(name)` / `getContextOrder(name)` instead of hard-coding numbers.
- A section may declare `complete: true`; it then becomes the entire prompt, and two effective complete sections fail assembly.
- `interpolate: false` preserves literal `{{…}}` text (used by the tools SDK so tool descriptions keep their braces). Everything else interpolates by default.
- Empty sections disappear; a malformed prompt fails assembly instead of being sent — an unknown variable, a registered-but-valueless variable, or a malformed complete group throws.

### Dynamic runtime context is separate from sections

Sections become prompt text. Context contributions become **sourced user-role snapshots** appended to history before the step, ordered by a second table (`lib/index.js:44-52`):

| Order | Context | Meaning |
|---|---|---|
| 100 | `WORKING_DIRECTORY` | `Current working directory: "<abs path>".` — required, stays when optional context is suppressed |
| 110 | `SANDBOX_POLICY` | `Current DSH file policy: <mode>.` plus the workspace root under `workspace-write` |
| 115 | `APPROVAL_POLICY` | Complete meaning of `ask` or `never` |
| 120 | `SUBAGENT_DELEGATION` | Child-agent facts |
| 125 | `TEAM_IDENTITY` | Which teammate/Lead this agent is |
| 200 | `HARNESS_SOURCE` | Current checkout path |
| 210 | `WEB_SURFACE` | Current GUI URL |

- Snapshot semantics: the first request and each **effective change** append one full snapshot; unchanged requests add nothing. A changed snapshot is appended **after** retained history, so the system prefix stays byte-identical.
- `refreshContext()` re-reads registered runtime facts after pre-step and route preparation without reassembling the bound prompt or tools. `suppressRuntimeContext()` removes optional contributions for a scope while required ones remain.
- This is the mechanism that lets a value change (port, checkout path, sandbox mode, approval policy) cost one small message instead of rewriting the prompt prefix.

### Prompt variables

- Variables are written `{{name}}` with names matching `^[a-z][a-z0-9_]*$`, resolved at each assembly; scoped variables shadow globals for one agent.
- The agent loop supplies `provider` and `model`; plugins register facts they own; the working-directory service contributes the directory as context rather than a variable.
- There is **no built-in `{{cwd}}` variable**: a persona template that references it fails assembly. Custom personas must not depend on it.

### Two levers on the whole prompt

- `includeHarnessIdentity: false` removes only the fixed opener (for compatibility deployments that own the entire prompt).
- A preset-mounted `dsh-persona` row can shadow `deployment:persona-prefix` / `-suffix` for one agent and can set `complete: true` to make its prefix the only prompt text — no identity, no tool guidance, no listener additions.
- `toolOrder` pins an explicit model-facing tool order and must contain exactly one `'<unlisted-tools>'` rest entry; a listed name with no registered tool rejects every assembly.

### Tool schemas are part of the assembly

- "What the model is told it can do" is one coherent unit: registration feeds schemas into assembly automatically, and the provider returns the visible set plus the pre-restriction name universe used by `toolOrder`.
- Ordering is by configuration or **lexicographic** after restrictions and interception. A live request header confirms it: 38 tool schemas sent alphabetically, `ask_user_question` first (`_session-dump/parsed/request-header.json`).
- Per-agent `restrict()` narrows the visible set; a tool-guidance section decides its own text by asking `ctx.tools.get(name, scope)`, so hiding a tool can also drop its paragraph — but scoped restriction does **not** remove an independently registered section (documented gap for `pwsh`/jobs guidance).

### Delivery and cache behavior

- The request carries `header.config`, `deriveMessages()`, and `header.tools` — **no separate `system` field**. The prompt reaches the model as a system-role message in derived history (surface node 0, or the latest system node after an in-history update).
- With `systemPromptUpdate: 'in-history'`, a changed non-empty prompt is appended after cached history, preserving reuse of the prefix. Without it, non-empty prompt text is consolidated at the first system node — a head rewrite that loses prefix reuse from the first changed token. An empty rendering clears every active system node.
- Repeated per-request costs: harness identity, persona text, and every visible tool schema. Append-only, prefix-safe costs: tool arguments, tool results, and runtime-context snapshots.

### Workspace instructions (AGENTS.md / CLAUDE.md chain)

- At the first eligible pre-step, `dsh-agent-instructions` appends one durable user-role baseline inside a `<system-reminder>` frame: user-global chain (`$DSH_HOME/AGENTS.md`, then `<agentsHome>/AGENTS.md`) followed by the project chain from the project root down to the session working directory, **broad to specific**.
- Defaults: project root marked by `.git`; base candidates `AGENTS.md`, `CLAUDE.md`; local overlays `AGENTS.local.md`, `CLAUDE.local.md`; `maxBytes` is required (the `dsh-base` bundle sets 65,536) and caps the complete rendered message; `maxSourceBytes` 1 MiB per file.
- Budget rule: whole broader files are dropped **before** the most-specific file is truncated; a visible `Workspace instruction budget ...` notice names omitted and truncated paths; rendered bytes never exceed `maxBytes`.
- Deduplication is content-based within a candidate group: a `CLAUDE.md` identical to its `AGENTS.md` (after trimming) renders once.
- Refresh is **touch-driven**: after a successful first-party `read`/`write`/`edit` reaches a deeper directory, the next request includes the newly applicable file; a changed file produces an update message, a vanished/duplicate one a removal notice. There is no watcher, and a shell `cd` does not trigger discovery.
- Instruction text is lower authority than system/developer/user instructions, `</system-reminder>` inside content is escaped, and symlinked instruction files are followed across the trust boundary.

### What leaves the prompt on purpose

`dsh-harness-dev-context` is the reference pattern: the two paragraphs that explain the checkout and the GUI are **value-free**, and the actual path/URL arrive as runtime context at orders 200/210. Starting the process from another checkout or port therefore never rewrites a Session's logged prompt, and a changed value appends one snapshot. Earlier-format Sessions keep their old embedded paragraphs verbatim so their prompt stays byte-identical.

## Portable protocol

What to do with the architecture above — these are the rules that survive a move to any host.

1. **Progressive disclosure.** Expose name + description first; load the body only when the situation matches; push detail into references that are read on demand. This is exactly how the DSH skill catalog and `agent-experience` guidance are built.
2. **Stable prefix, volatile tail.** Put unchanging identity, rules, and tool semantics early; put anything that varies per session (paths, URLs, modes, counts, dates) into appended context or a tool result. A changed token invalidates cache reuse from that point.
3. **Say each fact once.** Do not repeat a tool definition in a prompt section, a parameter description in the tool description, or one tool's rules in another tool. Duplicated facts drift and cost tokens on every request.
4. **Parameter rules belong on the parameter.** Defaults, ranges, pairing, and "when to set this" go in that parameter's schema description. If a tool description seems to vary with configuration, the varying part is usually a parameter.
5. **Make discovery explicit.** Every deferred resource needs a clear description and a reliable retrieval path. A skill that says "see references/" without naming the file is not discoverable.
6. **Keep critical constraints visible.** Permissions, destructive effects, and required validation belong before the action they govern, not in a reference the agent may never open.
7. **Bound outputs and mark truncation.** Return concise results with identifiers/paths for detail; state omissions explicitly and provide the way to retrieve more.
8. **Measure the change.** Compare first-turn prompt tokens before and after a tool-definition or section change; "it reads better" is not evidence.
9. **One owner per fact.** Each plugin owns the section for the fact it can actually observe. A prompt that states a policy the code may not enforce is a lie the model will act on.

### Portable layout template

```markdown
---
name: <lower-kebab-case>
description: <when to use it + what it returns; this is the only text always loaded>
---
# <title>
<one-paragraph purpose>

## Load policy            # routing table: situation -> reference file
## Core rules            # stable, always-relevant constraints (numbered)
## Protocol               # the executable steps
## Apply in <host A>      # mapping to that host's primitives
## Apply in <host B>
## Pitfalls               # observed failure modes
## References             # files to read only when needed
```

### Workspace-instruction skeleton

```markdown
# <project> — agent instructions
## Commands        # exact build/test/lint invocations
## Layout          # where things live; what not to touch
## Conventions     # style, naming, error handling
## Safety          # destructive ops, secrets, generated files, ownership boundaries
## Definition of done  # what must be verified before claiming success
```
Keep it short and hierarchical: broad rules at the repo root, specific rules in the subdirectory that needs them (they load broad-to-specific and dedupe).

## Apply in Claude Code

- `CLAUDE.md` is the instruction chain: the root file plus nested files, loaded automatically. Treat it as the same "broad to specific, lower than direct instructions" contract, and keep it under a few thousand tokens.
- Skills are `SKILL.md` + supporting files under a skills directory; the description is the always-loaded routing text, the body loads on invocation. Use the same progressive-disclosure layout as above.
- Permission-mode and sandbox text is supplied by the host — do not restate it in your skill; restate only what the host does **not** say (e.g. your project's destructive-operation rules).
- Put stable behavior in `CLAUDE.md`/skill body, volatile facts (today's branch, current port) in the conversation or a file, never in the always-loaded prefix.

## Apply in Codex

- `AGENTS.md` is the instruction chain (root plus nested); keep the same broad-to-specific ordering and the same "do not override system/developer/user" framing.
- Codex skills/instructions follow the same description-then-body shape: a short routing description, then the executable body, then references loaded on demand.
- Because Codex has no generated tool-SDK section and fewer built-in tools, keep tool guidance short and place it next to the operation, not in a global preamble.
- Put host-varying values (paths, ports, interpreter locations) in a small state file the agent reads, not in the prompt text.

## Pitfalls

- **Writing one long prompt instead of sections.** You lose ordering control, you cannot scope per agent, and any change rewrites the prefix.
- **Putting volatile values in the system prompt.** Every port change or path change then invalidates the whole cached prefix.
- **Referencing an unregistered variable.** Assembly fails loudly — good in development, fatal if a persona template depends on `{{cwd}}`, which does not exist.
- **Two `complete: true` sections.** Assembly fails; only one owner may claim the whole prompt.
- **Assuming a restriction removes guidance.** Tool sections are independent registrations; hiding a tool may leave its paragraph behind.
- **Assuming a watcher exists for instruction files.** Refresh is touch-driven and shell `cd` does not trigger it — read a file in the new directory if you need its nested rules.
- **Assuming the instruction chain wins.** Workspace instructions never override system, developer, or direct user instructions, and a symlinked file can bring in off-tree content.
- **Duplicated text drifting.** If the same rule appears in a tool description and a prompt section, one will be updated and the other will not.

## Evidence

| Claim | Source |
|---|---|
| Registry, assembly/render split, complete sections, interpolation, scoping, `toolOrder` | `dsh-system-prompt` README §Use this package, §Assembly and rendering, §Scoping |
| Section order constants and context order constants | `dsh-system-prompt/lib/index.js:10-43` and `:44-52` |
| Prompt is a derived-history system message with no wire `system` field; in-history vs head consolidation | `dsh-system-prompt` README §Model Experience; `dsh-agent-loop` README §Understand the implementation |
| Persona shadowing, `complete`, runtime-context suppression | `dsh-persona` README §Persona behavior |
| Values moved out of the prompt into runtime context | `dsh-harness-dev-context` README §Main flow, §Model Experience |
| Workspace chain, budget rule, dedupe, change notices, touch-driven refresh | `dsh-agent-instructions` README §What the agent gets, §Observing the budget, §Main flow, §Known Limitations |
| Design principles for tool definitions and context loading | `dsh-agent-preset/skills/agent-experience/SKILL.md` |
| Actual tool-schema ordering in a live request | `_session-dump/parsed/request-header.json`; rendered prompt `_session-dump/parsed/system-prompt-0.md` |
