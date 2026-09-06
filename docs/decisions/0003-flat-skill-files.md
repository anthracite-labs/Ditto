# ADR-0003: Flat per-task workflow files instead of upstream `SKILL.md` directories

**Date:** 2026-09-06
**Status:** accepted
**Deciders:** Ditto maintainers (issue #2 permits structural deviation when
simpler); implemented by Arena Agent Mode

## Context

Issue #2 sketches `.ecc/skills/<name>/` directories, mirroring upstream ECC,
where each skill is a directory containing `SKILL.md` plus optional helper
scripts, reference files, and harness-specific copies (`.cursor/`, `.kiro/`,
`.agents/`). The same issue explicitly allows a simpler structure if the
deviation is explained. Ditto's skills are single self-contained Markdown
procedures with no helper assets, and the loader is one agent calling
`read_file` on a path it took from an index.

## Decision

Store each workflow as a single flat file — `.ecc/skills/planning.md`,
`.ecc/skills/tdd.md`, and so on — routed through `.ecc/skills/INDEX.md`, with
the router↔file relationship enforced in both directions by
`scripts/verify.sh` (`skill_index`).

## Alternatives considered

### Alternative: Upstream layout, `.ecc/skills/<name>/SKILL.md`

- **Pros:** Matches upstream one-for-one, so diffs against ECC are trivial and
  a future helper script has an obvious home.
- **Cons:** Doubles the path length for no content; an extra directory per
  skill that holds exactly one file.
- **Why not:** No skill in v0.1 has assets, and a directory that can only ever
  contain `SKILL.md` adds a hop to every load. If a skill later needs helper
  files, it can be promoted to a directory then — the index is the contract,
  and it changes in one row.

### Alternative: One large `WORKFLOWS.md`

- **Pros:** A single read.
- **Cons:** Defeats on-demand loading; every task pays for every workflow.
- **Why not:** Context budget is the whole reason the index exists.

## Consequences

### Positive

- One path, one read, per workflow: minimal context cost.
- The index is a small, auditable router, and its rows are machine-checked
  against the files on disk.
- Adding a workflow is one file plus one index row.

### Negative

- Deviates from the layout sketched in issue #2 and from upstream, so upstream
  comparisons need a path mapping (recorded in `.ecc/UPSTREAM.md`).
- A skill that later needs helper assets must be promoted to a directory,
  touching the index.

### Follow-ups

- Revisit if any workflow accumulates reference files or executable helpers.
