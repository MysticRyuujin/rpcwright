# Contributing to rpcwright

rpcwright is a Claude Skill: **reusable, timeless guidance** for engineering and
conformance-testing Ethereum JSON-RPC (execution-apis) changes across clients.
PRs from humans and agents are welcome — the bar:

## The rule

**Every line must be guidance that helps with *any* future JSON-RPC change — not
a changelog of one specific change.**

A concrete example (e.g. "default an omitted block to latest") is welcome *when it
illustrates a general technique*. A work-artifact is not. Cut or generalize:

- "verified in our case", "no change needed", "what we did", "found via this
  workflow", PR/issue-specific narrative, or dated status that will rot.
- If a line only makes sense in the context of one past change, it doesn't belong
  in the skill — move the lesson into a gotcha or the worked example, generalized.

## Keep it structured

- **Per-client info** follows the cheat-sheet shape in `references/clients.md`:
  handlers · registration · param/result idiom · build/test · CI gates. Add a new
  client as a new table row + a section in that same shape.
- **A new change-type** is a new row in SKILL.md's "What to touch, by change type"
  table, with the mechanics in the relevant reference file
  (`execution-apis.md` / `testgen.md` / `clients.md` / `hive.md`).
- **Reusable traps** go in `references/gotchas.md`. The long narrative of an
  example lives in `references/worked-example.md`; other files reference it
  rather than re-telling it.
- Prefer verifying client specifics against the actual repo — file paths and CI
  rules drift, so the skill says "read the workflow/source" rather than freezing
  exact details that go stale.

## Mirror files

`AGENTS.md`, `CLAUDE.md`, and `llms.txt` are **symlinks** to `SKILL.md` (one
source of truth, no drift). Don't replace them with copies. If you add a mirror,
symlink it: `ln -sf SKILL.md <name>`.

## Before you open a PR

- `bash scripts/validate.sh` passes (frontmatter, mirror symlinks, link
  integrity). CI runs the same check (`.github/workflows/validate.yml`).
