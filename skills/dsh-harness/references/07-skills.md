# Skills: authoring, discovery, and progressive disclosure

A skill is a deferred prompt: a name and one-line description sit in the context permanently, and the full instructions enter only when the agent decides the task matches. Everything about skill design follows from that trade — the description carries all the routing value, and the body is paid for only when it is used. This reference covers how DSH discovers and renders skills, then how to write skills that survive a move to Claude Code, Codex, or any file-reading agent.

## What the harness does (observed)

### File format

- A skill is either a **directory bundle** `<root>/<name>/SKILL.md` or a **flat file** `<root>/<name>.md`. Nested `**/SKILL.md` trees are deliberately not discovered (`dsh-skill-filesystem` README §Skill format, §Known Limitations; `lib/index.js:553`, `:559`).
- The file starts with YAML frontmatter. Required: `name` (kebab-case) and `description`. Optional: `whenToUse`, `metadata`, `disable-model-invocation`, `user-invocable` (`dsh-skill-filesystem` README §Skill format; `lib/index.js:685`).
- The two invocation keys accept YAML booleans plus case-insensitive `true/false`, `yes/no`, `on/off`, `1/0`. A misspelled or non-boolean value **drops the whole skill with a warning** rather than silently permitting a surface (`dsh-skill-filesystem` README §Skill format).
- Catalog and body have separate lifecycles: discovery parses frontmatter into the catalog entry, and every load re-reads the current file. Editing a body needs no versioning or cache invalidation (`dsh-skill-filesystem` README §Skill format).

### Discovery and priority

- Roots are scanned in rank order (`dsh-skill-filesystem` README §Roots and priority):

| Rank | Source | Path |
|---|---|---|
| 100 | project-dsh | `<projectRoot>/.dsh/skills` |
| 200 | project-agents | `<projectRoot>/.agents/skills` |
| 300 | custom | configured dirs |
| 400 | user-dsh | `<dshHome>/skills` |
| 500 | user-agents | `<agentsHome>/skills` |
| 600 | bundled | configured bundled dir |

- The project root is the nearest ancestor containing `.git`; without one, the current working directory (`dsh-skill-filesystem` README §Roots and priority; `lib/index.js:155`).
- Existing roots are watched. Adding, renaming, or deleting a skill — or editing its frontmatter — refreshes the catalog before the next model step. Edits under `references/`, `scripts/`, `assets/` do not. First-party `write`/`edit` calls invalidate the provider synchronously (`dsh-skill-filesystem` README §Change detection).
- Malformed entries disappear with a warning. The model catalog gets **no per-skill diagnostic**, so an absent skill and an invalid skill look identical (`dsh-skill-filesystem` README §Known Limitations).
- Duplicate names: the nearest layer wins outright; within one layer, rank → provider registration order → provider-local order. Shadowed definitions are not inspectable (`dsh-skill` README §Design concept, §Known Limitations).

### Progressive disclosure: three tiers

1. **Catalog** — one durable user-role `<system-reminder>` before the first request, listing `name` plus a normalized description capped by `catalogDescriptionMaxLength` (default `500`). It exists only when model-invocable skills exist *and* the `skill` tool is visible (`dsh-tool-skill` README §Session catalog, §Config).
2. **Body** — `skill(name)` returns a canonical `<skill_content name="...">` block with `<skill_resources>` guidance and `<skill_instructions>` (the file body). The result is retained as ordinary tool history (`dsh-tool-skill` README §Tool result; `lib/index.js:789`).
3. **Resources** — the tool does not inline referenced files. It reports the bundle's base directory and instructs the model to resolve relative paths against it and load referenced resources only as needed (`dsh-tool-skill` README §Directory resource guidance).

### What routing actually sees

- The catalog renders **only name and capped description**. `whenToUse` stays provider metadata and is not rendered by the catalog or the loaded wrapper either — so it cannot help routing (`dsh-tool-skill` README §Known Limitations).
- The catalog is diffed by a digest over entries, not over rendered prose. Any membership, description, or visibility change appends a **complete replacement** catalog; removing every skill appends an empty catalog that explicitly retires older names (`dsh-tool-skill` README §Catalog lifecycle).
- Body-only edits do not change the digest: the model is not notified, and earlier tool results remain historical facts (`dsh-tool-skill` README §Known Limitations).
- Invocation policy: `modelInvocable` controls the catalog and the `skill` tool; `userInvocable` controls human commands. `disable-model-invocation: true` is reachable **only** through a `/name` gesture in direct user input, which injects the same `<skill_content>` block (`dsh-skill` README §What the registry gives you; `dsh-tool-skill` README §Invocation boundary).
- Exact failure strings: `Error: invalid skill name "<name>"`, `Error: skill "<name>" is unknown or no longer available`, `Error: skill "<name>" is not available for model invocation` (`dsh-tool-skill` README §Tool errors).
- Bodies are never cached and have **no size cap** — only catalog descriptions are truncated (`dsh-skill` README §Loading and staleness; `dsh-tool-skill` README §Known Limitations).

### Bundled skills

- Preset skills ship under `dsh-agent-preset/skills/`: `agent-experience`, `cordis-composition-reference`, `cordis-plugin-development` (with `references/` and `templates/`), and `editing-cordis-compositions` — the same bundle-with-references shape this skill uses.
- `agent-experience` is the harness's design doctrine for model-facing surfaces. Its six rules: start with minimal context; make discovery explicit; keep critical constraints visible before the action; prefer bounded outputs with identifiers or paths for detail; use locality (bounded adjacent context) and mark omissions; evaluate total work, because saving context is only useful if it does not cause more searches or mistakes. Its tool-definition rules: delete constraints the model learns from the result; describe behavior, not implementation; put parameter rules on the parameter; say each fact once; measure the token change (`dsh-agent-preset/skills/agent-experience/SKILL.md`).
- The `office` bundle shows the router pattern: a 15-line `office` skill that names per-format skills (`office-docx`, `office-xlsx`, `office-pptx`) and operation skills (`office-render`, `office-recalculate`, `office-export-pdf`), tells the model to call `skill` with the format skill name, and explicitly says not to reload skills (`dsh-skill-office/assets/office/SKILL.md`).
- The badge provider shows the minimal bundled skill: one immutable candidate at rank 600, a packaged `assets/` resource base, body read on every load (`dsh-skill-badge` README §Design concept).

## Portable protocol

### Rules

1. **One skill = one job.** Prefer multiple small skills over one encyclopedia: the catalog is cheap, the catalog entry is what routes.
2. **Write the description as a trigger, not a title.** State *when* to load it and include the words a real request would contain ("Use when the task mentions ...", "Load before ..."). It is the only routing signal the model sees.
3. **Keep `SKILL.md` a router.** Roughly one screen: purpose, numbered rules in execution order, and pointers to `references/<topic>.md`. Push tables, long examples, and templates into references.
4. **Give the loader a base path.** Assume the agent will read references relative to the skill directory; name the files explicitly rather than saying "see the docs".
5. **Bound the output.** State the expected deliverable, its format, and its size limits; require evidence instead of transcripts.
6. **Make constraints visible before the action**, not in a closing appendix.
7. **Say each fact once.** Do not restate the host system prompt, another skill, or the tool schema; duplication is paid on every load.
8. **Design for cold invocation.** The body is inserted as text with no conversation around it. Write it self-contained, in imperative form, ordered by what to do first.
9. **Change the description when routing changes.** Body edits are invisible to the catalog digest; description edits republish it.
10. **Test by cold-loading.** Ask an agent with only the catalog entry which skill it would load for three realistic requests. If it picks wrong, fix the description, not the body.

### Template: skill skeleton

```markdown
---
name: <kebab-case-name>
description: Use when <trigger situation>. <What it covers, one clause.>
# optional:
# disable-model-invocation: true   # only reachable via /name
# user-invocable: false            # hide from human commands
---

# <Title>

<2-4 sentences: what this skill is for, and the load policy for references.>

## Procedure
1. <first action>
2. <second action>
3. <verification step>

## Rules
- <hard constraint the agent must not violate>

## References
- `references/<topic>.md` — <when to read it>
- `scripts/<tool>` — <what it does, how to call it>

## Exit criteria
- <what "done" means>
- <evidence to produce>
```

```text
<name>/
  SKILL.md
  references/<topic>.md
  scripts/<helper>
  assets/<static>
```

## Apply in Claude Code

Client behavior, not verified in this checkout (unverified).

- Skills live in `.claude/skills/<name>/SKILL.md` (project) or a plugin's `skills/` directory; the frontmatter `name` and `description` drive automatic invocation, and the description is the routing surface exactly as above.
- Claude Code loads the whole `SKILL.md` when triggered, so keep the body small and move detail into `references/` inside the same directory — the agent reads them with `Read`.
- Slash commands (`.claude/commands/<name>.md`) are the user-invoked tier, roughly equivalent to a `/name` gesture; a command can be a thin wrapper that says "load and follow `skills/<name>/SKILL.md`".
- Ship skills through the plugin manifest (`.claude-plugin/plugin.json`) so they install as a versioned bundle rather than loose files.

## Apply in Codex

Client behavior, not verified in this checkout (unverified).

- Codex has no built-in skill catalog: create a `skills/<name>/SKILL.md` tree and make discovery **explicit** in `AGENTS.md` with a one-line trigger table ("When the task is X, read skills/x/SKILL.md before acting").
- `codex exec` starts a fresh process with no memory of prior turns, so a skill is only useful if it is on disk and referenced by path; never assume an inline explanation survives.
- Keep `AGENTS.md` to routing plus standing constraints, and put procedures in the skill files — the same progressive-disclosure split, implemented with plain files.
- Prefer a small number of high-signal skills over a deep tree; without a catalog, every extra hop is a search the agent may skip.

## Pitfalls

- **A description that names the topic but not the trigger.** The agent will load it too late or not at all.
- **Relying on `whenToUse`.** It never reaches the model in DSH.
- **Nesting skills deeper than one level.** `a/b/SKILL.md` is simply not discovered.
- **Non-boolean invocation values.** `disable-model-invocation: "yes"` is accepted, `disable-model-invocation: "maybe"` silently deletes the skill from the catalog.
- **Publishing a huge body.** There is no body-size cap; a 2000-line skill consumes the context it was meant to save.
- **Editing the body and expecting the catalog to update.** It won't; only the digest of name/description/membership republishes.
- **Duplicate names across roots.** The nearest root wins silently; the shadowed skill is invisible.
- **Assuming references are auto-loaded.** The tool only reports the base directory — the agent must decide to read.
- **Restating the system prompt** in a skill. It is paid twice on every load and drifts on every edit.

## Evidence

| Claim | Source |
|---|---|
| Bundle and flat-file discovery, one level deep | `dsh-skill-filesystem` README §Skill format, §Known Limitations; `lib/index.js:553`, `:559` |
| Frontmatter fields, strict boolean grammar, name/description required | `dsh-skill-filesystem` README §Skill format; `lib/index.js:685` |
| Root ranks, project-root rule, watcher invalidation | `dsh-skill-filesystem` README §Roots and priority, §Change detection; `lib/index.js:155` |
| Catalog message, description cap, replacement semantics | `dsh-tool-skill` README §Session catalog, §Config, §Catalog lifecycle |
| `<skill_content>` shape and resource guidance | `dsh-tool-skill` README §Tool result; `lib/index.js:979` |
| Catalog omits `whenToUse`; no body size cap | `dsh-tool-skill` README §Known Limitations |
| Invocation policy matrix and `/name` boundary | `dsh-skill` README §What the registry gives you; `dsh-tool-skill` README §Invocation boundary |
| Exact skill error strings | `dsh-tool-skill` README §Tool errors |
| Design doctrine for model-facing surfaces | `dsh-agent-preset/skills/agent-experience/SKILL.md` |
| Router-pattern example (office) | `dsh-skill-office/assets/office/SKILL.md` |
| Bundled immutable provider shape | `dsh-skill-badge` README §Design concept |
