# ADR-001: Layered Instruction & Memory Architecture Across Claude Code and Claude.ai

## Status

Accepted

## Context

Instructions for how Claude should work (communication style, engineering values, debugging approach, task-specific conventions) existed in three uncoordinated places before this design:

1. A manually maintained `claude.md` used with Claude Code.
2. Claude Code's built-in auto-memory system (`~/.claude/memory/`, `feedback_*.md` files), populated automatically by Claude as it worked.
3. Claude.ai's separate web-chat memory and per-conversation user preferences, with no relationship to either of the above.

This produced three concrete problems:

- **Duplication and drift.** The same rule (e.g. "read before writing," "verify before declaring done") existed almost verbatim in both the hand-written `claude.md` and in auto-memory `feedback_*.md` files, authored independently at different times. Editing one copy had no effect on the other, so the two could silently diverge.
- **No mechanism to distinguish "always relevant" from "only relevant sometimes."** Every instruction was either always loaded (expensive, and drowns out signal as the file grows) or living in an auto-memory file that Claude may or may not decide to read.
- **No path between surfaces.** Claude Code cannot read claude.ai's memory store, and claude.ai has no filesystem access — there is no API or shared storage bridging the two products.

## Decision

Adopt a four-layer model, split by *how each surface actually loads content*, rather than by topic:

1. **`~/.claude/CLAUDE.md`** — static, human-authored, loaded in full at the start of every Claude Code session. Reserved for instructions that are universal and stable: communication style, engineering values, debugging philosophy, and the meta-rules that govern how the other three layers get maintained.

2. **`~/.claude/skills/*/SKILL.md`** — task-triggered, on-demand. Only a name and one-line description load at startup (~100 tokens per skill); the full body loads only when Claude judges the current task matches. Used for conventions tied to a *kind of task* rather than a file type (e.g. multi-agent coordination) and, after evaluation, for file-type-specific conventions as well (see Alternatives Considered).

3. **Auto-memory (`~/.claude/memory/`)** — Claude-authored, self-maintaining, on-demand (only the index `MEMORY.md` loads at session start; topic files load only when referenced). Reserved for narrow, evolving, correction-derived rules that don't yet warrant permanent, universal status.

4. **A chat-preferences file** — not read by Claude Code at all. A filesystem-resident source of truth for the subset of instructions relevant only to the claude.ai chat UI (artifact/output-format rules with no Claude Code equivalent). The user manually pastes its content into claude.ai's Settings → Profile → Preferences whenever it changes.

A fifth component, the **`memory-promotion` skill**, is introduced purely to maintain consistency across layers 1–4 plus claude.ai's own memory (which is outside the filesystem entirely). It runs on demand, asks the user to paste a snapshot of claude.ai memory (no automated bridge exists), diffs it and all auto-memory/project-memory content against the current CLAUDE.md and chat-preferences file, proposes promotions or retirements, and waits for explicit confirmation before writing anything.

## Alternatives Considered

**Single monolithic CLAUDE.md containing everything.** Rejected. Every instruction would load on every session regardless of relevance, defeating the stated goal of avoiding token waste, and Claude Code's own documentation notes that adherence degrades as a single file grows large.

**Path-scoped rules (`.claude/rules/*.md` with `paths:` frontmatter) for file-type-specific conventions (Python, Nix).** Considered and rejected in favor of skills. This is the documented, first-party mechanism for conditional loading by file pattern, but at the time of this decision multiple open defects were found (rules loading globally regardless of `paths:`; rules not injected on Write, only on Read) — see referenced GitHub issues #16299, #22170, #23478. Skills use semantic (model-judged) triggering rather than deterministic glob matching, which is a weaker guarantee in principle but was, in practice, the mechanism that actually worked. This decision should be revisited if the rules-directory defects are fixed upstream, since deterministic path matching is preferable to semantic triggering when both are reliable.

**Automatic synchronization between claude.ai memory and the local filesystem.** Rejected — not possible. Claude.ai memory is a separate product with no API or export mechanism Claude Code can call; the only path is a human copying text out of one UI and into a file. The design accepts this manual step rather than attempting to work around it.

**Keeping all learned patterns in auto-memory indefinitely rather than promoting stable ones to CLAUDE.md.** Rejected. Auto-memory topic files are not guaranteed to be read every session (they load only when Claude judges them relevant), so a rule that should always apply is unreliable if left there. Stable, universal rules are promoted out of auto-memory into CLAUDE.md; auto-memory is reserved for content that is genuinely narrow or still evolving.

## Consequences

**Positive**

- No layer loads content it doesn't need: CLAUDE.md stays lean and universal, skills cost ~100 tokens until actually invoked, auto-memory topic files cost nothing until referenced.
- A single retirement/promotion workflow (the `memory-promotion` skill) replaces manual, error-prone reconciliation across three-plus stores.
- The design degrades gracefully: if the chat-preferences file is never pasted into claude.ai, or a project is never scanned, nothing breaks — those are just missed optimizations, not failures.

**Negative / accepted trade-offs**

- Skill triggering is semantic, not deterministic. A poorly worded `description` field is the single most likely failure mode — a skill with a vague description may simply never fire. This is mitigated by writing descriptions with concrete trigger phrases, but not eliminated.
- Syncing claude.ai memory requires a manual paste step every time; there is no way to automate this given current product boundaries.
- The `memory-promotion` skill's project-memory scan depends on the user correctly identifying which project(s) to check, or explicitly requesting a full sweep — it will not discover projects on its own initiative beyond what `~/.claude/projects/` exposes.
- This architecture assumes Claude Code's auto-memory and skills mechanisms remain stable; both are relatively new subsystems and their loading semantics have already shown defects in the rules-directory case. Revisit this ADR if similar issues surface in skills or auto-memory.

## References

- Claude Code memory documentation: `https://code.claude.com/docs/en/memory`
- Claude Code skills documentation: `https://code.claude.com/docs/en/skills`
- Agent Skills specification: `https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview`
- Rules-directory defects: anthropics/claude-code issues #16299, #22170, #23478
- Claude.ai memory import/export: `https://support.claude.com/en/articles/12123587-import-and-export-your-memory-from-claude`
