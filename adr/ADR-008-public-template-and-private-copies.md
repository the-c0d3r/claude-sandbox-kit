# ADR-008: Public Template and Private Copies

## Status

Accepted. Replaces the subtree + `@import` design of the earlier `spec/SPEC-public-template.md`; amends ADR-005.

## Context

The setup is published as a public template that others (and the author) use to keep their own Claude Code config in git. The earlier design pulled the template into a personal repo as a git subtree and had the personal `CLAUDE.md` import the template's with a relative `@import`. That needed a path that fails silently when wrong, a `skills -> template/skills` symlink chain through the sbx skills store, and subtree commands for every update.

## Decision

- **Two repos.** The public template holds scripts, `spec.yaml`, docs, tests and starter files. Each user's private copy is a clone of it with `upstream` (the template, push disabled) and `origin` (private). Updates: `git pull upstream main`.
- **Ownership split.** The template owns scripts, kit manifest, docs and tests; users don't edit them. Users own everything in `files/home/.claude/`, `skills/` and `projects/`; the template ships starters and never changes them after the first release, so pulls don't conflict.
- **Linking is data-driven.** `install.sh` links every entry of `files/home/.claude/` (plus `skills/`, `projects/`); `uninstall.sh` removes every `~/.claude/` link into the repo; `run-sandbox.sh` copies every entry except `settings.json` (merged) and `memory/` (mounted).
- **Template work happens in a separate clone of the template**, never moved out of a private copy.
- **Fresh history** for the public repo, built from template-owned and starter files only.

## Alternatives Considered

- **Subtree + `@import`** (above). Rejected for the fragile import path, the symlink chain and the update ceremony; users owning `CLAUDE.md` outright gives conflict-free pulls without them.
- **Git submodule.** Empty `template/` until an explicit init step, which breaks kit injection.
- **Plugin distribution.** Plugins can't carry `CLAUDE.md`.
- **`.example` files.** Manual merge on every update.

## Consequences

- Starter files can't be improved for existing users through `git pull`; new defaults are announced in the README instead.
- Adding config (e.g. `agents/`) needs no script change.
- A user who edits a template-owned file takes on merge conflicts for it.
- The ADR-005 subtree/import test layer and its manual smoke test are removed.

## References

- `spec/SPEC-public-template.md`, `spec/PLAN-public-template.md`
- ADR-005, ADR-007
