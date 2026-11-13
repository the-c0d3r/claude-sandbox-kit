# ADR-005: Public Template Testing Strategy

## Status

Accepted. Amended by ADR-008: layer 3 (subtree + `@import` test) was dropped with the subtree design; layer 1 now covers docs too. Section references below point to the earlier, subtree-based version of `spec/SPEC-public-template.md`.

## Context

`spec/SPEC-public-template.md` specifies `install.sh`/`uninstall.sh` (§6), a subtree + `CLAUDE.md` `@import` composition mechanism (§4) confirmed only against docs and never exercised end to end, and a one-time manual self-location audit (§9) that already found a real hardcoded personal path in `README.md`. None of the install/uninstall scripts exist yet. Building them, and the composition mechanism, without a way to test them risks the exact category of drift the manual audit caught by chance rather than by design.

## Considered approaches

### 1. `bats-core` test framework

TAP-style output, built-in setup/teardown. Rejected as the default: it adds a tool contributors and adopters must install to run tests on what is otherwise a dependency-free dotfiles repo, working against the minimal-ceremony spirit of G3/G4.

### 2. Manual checklist only

Cheapest option, but provides no regression protection as the template evolves toward publication — the same failure mode that let the hardcoded path in `README.md` go unnoticed until a one-off manual grep (§9).

### 3. Plain-bash test harness, layered by cost (chosen)

Matches the existing script idiom in this repo (self-locating `REPO` variable, plain bash, no new runtime). Layers ordered cheapest/most frequent to most expensive/rarest so the common case stays fast.

## Decision

`test/run.sh` discovers and runs every `test/test_*.sh` (each a standalone script, exit 0 = pass), and prints a pass/fail summary.

Four layers:

1. **Static checks** — `test_no_hardcoded_paths.sh` automates the §9 audit (scoped to what actually ships: `*.sh`, `README.md`, `spec.yaml`, `files/home/.claude/**` — not design docs under `spec/` or `adr/`, which are allowed to discuss real paths as prose). `test_shellcheck.sh` runs `shellcheck` over every script if it's installed, and skips cleanly (exit 0) if it isn't — optional lint, not a hard dependency.
2. **Isolated `install.sh`/`uninstall.sh` filesystem tests** — each test sets `HOME` to a fresh `mktemp -d` so the real `~/.claude` is never touched. Covers fresh install, idempotent re-run, backup-on-existing-file, the `settings.json` diff+confirm path and its `--yes` bypass, and uninstall's symlink-only removal plus backup restore.
3. **Subtree + `@import` composition test** — two throwaway git repos under `/tmp` standing in for the template and personal repos (no GitHub dependency), exercised with real `git subtree add`/`pull`, followed by an actual `claude -p` invocation to confirm the import resolves in the real product rather than trusting the docs alone.
4. **Kit injection smoke test** — a manual pre-release checklist, not automated. Spinning up a real `sbx` sandbox per test run is slow and stateful enough that automating it isn't worth it at this repo's size; it's already migration-plan step 8.

## Consequences

**Positive**

- Zero new dependencies to run the suite — `shellcheck` is optional and skips cleanly if absent.
- Same idiom as `setup.sh`/`run-sandbox.sh`/`sync-memory.sh`, so contributors don't learn a second way of writing scripts just to add a test.
- Layer 1 caught a real, pre-existing issue (the 3 hardcoded personal paths in `README.md` from §9) on its first run, before any of the scripts under test in layers 2–3 even exist — evidence the approach works, not just that it's plausible.

**Negative / accepted trade-offs**

- No TAP/JUnit output and no parallelism. Acceptable at the current suite size (single-digit test files); worth revisiting only if that grows substantially.
- Layer 4 stays manual. Kit injection needs a real `sbx` sandbox; that cost isn't worth automating yet.

## References

- `spec/SPEC-public-template.md` §§4, 6, 9, 11, 13 (import mechanism, install/uninstall, self-location audit, kit injection, testing strategy)
- `test/run.sh`, `test/test_no_hardcoded_paths.sh`, `test/test_shellcheck.sh`: implementation
