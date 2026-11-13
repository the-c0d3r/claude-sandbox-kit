# SPEC: Layered Instruction & Memory System

Companion to ADR-001. This document specifies the concrete implementation — file layout, schemas, and algorithms — rather than the reasoning behind it.

## 1. Goals

- G1: No instruction content loads into context unless it is either (a) universal and cheap enough to always load, or (b) relevant to the current task.
- G2: A single instruction never has more than one authoritative copy. Where the same rule could plausibly live in two layers, this spec states which layer wins.
- G3: Content learned in any one surface (a project, a Claude Code session, a claude.ai conversation) can be deliberately promoted to wherever else it's relevant, without silent duplication.
- G4: All promotion/retirement actions are proposed and confirmed, never applied silently.

## 2. Non-Goals

- Automatic, unattended synchronization with claude.ai memory. Out of scope — no API exists (see ADR-001, Alternatives Considered).
- Guaranteed deterministic loading of task-specific conventions. Skills are triggered semantically; this spec does not attempt to make that deterministic (see ADR-001 re: rules-directory defects).
- Cross-machine sync of any file in this system. All paths below are local to a single machine's `~/.claude/`.

## 3. Components

| Component | Path | Authored by | Loaded | Scope |
|---|---|---|---|---|
| Core instructions | `~/.claude/CLAUDE.md` | Human | Full, every Claude Code session | Global, universal |
| Task-triggered conventions | `~/.claude/skills/<name>/SKILL.md` | Human (initially), promotable by memory-promotion | Metadata (name+description) always; body on semantic match | Global, task-scoped |
| Personal memory index | `~/.claude/memory/MEMORY.md` | Claude, on request or via promotion | Every session, through `@~/.claude/memory/MEMORY.md` in `CLAUDE.md` (Claude Code does not load this directory on its own) | Personal |
| Personal memory topic files | `~/.claude/memory/*.md` | Claude, on request or via promotion | On demand (Read tool; needs `permissions.additionalDirectories: ["~/.claude/memory"]` while `blockReadsOutsideWorkingDirectories` is on) | Personal |
| Project auto-memory | `~/.claude/projects/<key>/memory/` | Claude (auto) | Index: first 200 lines / 25KB, every session; topic files on demand (readable under `blockReadsOutsideWorkingDirectories` via `additionalDirectories: ["~/.claude/projects"]`) | Per project (see §3.1) |
| Chat-only preferences | A local chat-preferences file | Human, promotable by memory-promotion | Not loaded by Claude Code at all — manually pasted into claude.ai Settings → Profile → Preferences | Claude.ai only |
| Claude.ai memory | claude.ai internal storage | Claude.ai (auto) | Per claude.ai's own retrieval logic | Claude.ai only; no filesystem access |

### 3.1 Project vs. personal auto-memory

Claude Code's auto memory is per project only. By default it lives at `~/.claude/projects/<key>/memory/`, keyed on the git root. A project's sandbox mounts that folder, so the host and the sandbox share it (ADR-007). The personal store `~/.claude/memory/` is this repo's own convention, loaded through the `CLAUDE.md` import. This spec treats every project memory directory as a candidate input to the memory-promotion algorithm (§5) — the algorithm must enumerate whichever are in scope for a given run (see §5, step 3).

## 4. Placement Rules (resolves G2)

When a candidate instruction could go in more than one place, apply in order:

1. **Is it only actionable inside claude.ai (chat UI)** — e.g. artifact formatting? → the chat-preferences file. Otherwise continue.
2. **Is it universal, stable, and cheap** (a short, general rule, unlikely to change, applicable regardless of file type or task)? → `CLAUDE.md`.
3. **Is it tied to a specific file type or a specific recurring task shape**, and reusable across projects? → a skill. If a matching skill already exists, append to it rather than creating a new one.
4. **Is it narrow, project-specific, or still likely to change?** → auto-memory (personal or project-scoped, matching where it was learned).

Ties are broken toward the more restrictive scope — prefer a skill over CLAUDE.md if a rule can be stated with a clear trigger condition, since that keeps CLAUDE.md lean per G1.

## 5. The `memory-promotion` Skill: Algorithm Specification

This section specifies the skill's logic precisely.

**Trigger:** user explicitly asks to review, clean up, sync, or promote memory.

**Inputs:**
- `~/.claude/CLAUDE.md` (current)
- The chat-preferences file (current, may not exist yet)
- `~/.claude/memory/MEMORY.md` + all linked `feedback_*.md`
- Zero or more project memory directories (`~/.claude/projects/<key>/memory/`), selected by the user or via a full sweep if requested
- A pasted snapshot of claude.ai memory, obtained interactively (never fetched automatically — see Non-Goals)

**Algorithm:**

```
candidates = []
candidates += parse(web_memory_paste)
candidates += parse(personal_auto_memory)
candidates += parse(each project_memory in scope)

for c in candidates:
    if semantically_present_in(CLAUDE.md) or semantically_present_in(chat_prefs.md):
        classify(c, "already_covered")
        continue

    if c.only_applies_to_chat_ui:
        classify(c, "promote_to_chat_prefs")
    elif c.is_universal_and_stable:
        classify(c, "promote_to_claude_md")
    elif c.is_file_or_task_type_specific and c.reusable_across_projects:
        classify(c, "promote_to_skill", target=find_matching_skill(c) or "new")
    else:
        classify(c, "leave_in_auto_memory")

redundant = [
    f for f in personal_auto_memory.files
    if fully_covered_by(f, CLAUDE.md) or fully_covered_by(f, chat_prefs.md)
]

present_to_user(candidates_by_classification, redundant_files)
await user_confirmation()

on_confirmation:
    apply promote_to_claude_md    -> append to CLAUDE.md, matching existing section or new section
    apply promote_to_chat_prefs   -> append to chat_prefs.md
    apply promote_to_skill        -> create or update SKILL.md
    apply leave_in_auto_memory    -> write as new feedback_*.md if not already a file
    delete redundant_files (only those confirmed AND passing the verification in §6)
    update all affected MEMORY.md indexes to remove dangling links

report: what changed, what was skipped, and why
```

Important constraint: **no file is written before `await user_confirmation()` returns.** This is a hard requirement, not a default — the skill must not proceed on assumed consent.

## 6. Verification-Before-Deletion Procedure

Applies to any `memory-promotion` run that proposes deleting a file.

For each file proposed for deletion:

1. Read the file's full content.
2. For each discrete instruction/point in the file, check whether an equivalent instruction is present in the proposed target (`CLAUDE.md`, the chat-preferences file, or a skill) — equivalence means same instruction, not merely same topic.
3. If **all** points are covered: mark eligible for deletion.
4. If **any** point is missing: do not delete. Either (a) fold the missing point into the target file as part of this same run, then mark eligible for deletion, or (b) leave the file in place and report the gap to the user for a manual decision.
5. Only after this check may a file move from "proposed" to "confirmed for deletion" in the confirmation step of §5.

## 7. Skill Authoring Requirements

Every `SKILL.md` created or updated by this system must:

- Include a `description` field written in the third person, naming concrete trigger phrases or file patterns (per ADR-001, vague descriptions are the primary cause of a skill never firing).
- Keep the body under roughly 500 lines; move detailed reference material into a `references/` subdirectory if it grows beyond that.
- State any preconditions or file types it applies to explicitly in the first line of the body, not only in the frontmatter.

## 8. Known Limitations (carried from ADR-001)

- Skill activation is not deterministic; a skill can fail to fire even when its description is well-written, if the model judges the task doesn't match.
- Claude.ai memory sync is manual and point-in-time — it reflects whatever was pasted at run time, not a live view.
- The chat-preferences file has no enforcement mechanism; if the user forgets to re-paste it into claude.ai after an update, the two drift until the next manual sync.
- This spec assumes the auto-memory and skills subsystems' documented loading behavior is accurate at time of writing; both are relatively new and have shown defects elsewhere in Claude Code (see ADR-001). Re-verify loading behavior periodically, e.g. via `/memory`.
