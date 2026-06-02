# rpcwright 🔧

> A *wright* is a maker — a shipwright builds ships, a playwright builds plays.
> A **rpcwright** builds (and proves) Ethereum JSON-RPC.

**rpcwright** is a [Claude Skill](https://docs.claude.com/en/docs/claude-code/skills)
that teaches an AI agent how to implement and conformance-test a change to the
**Ethereum execution-layer JSON-RPC API** — across the four repos that have to
agree:

| repo | role |
| --- | --- |
| **the client** (go-ethereum, Nethermind, Besu, Erigon, Reth, ethrex) | implements the method |
| **execution-apis** | the OpenRPC spec (the contract) |
| **testgen / rpctestgen** | generates `.io` fixtures from a real client |
| **hive** (`rpc-compat`) | replays fixtures against every client |

The one-line behavior change is easy. The hard part is the build/test plumbing
and the dozen places a *silent* failure hides — a green hive run that executed
zero tests, a fixture that passes validation only because the param was still
"required", a harness quietly testing the upstream image instead of your change.
This skill encodes the exact commands and those gotchas so future sessions don't
rediscover them the slow way.

## What's inside

- [`SKILL.md`](SKILL.md) — the mental model, the golden-path recipe, and the
  gotchas that cost hours.
- [`references/go-ethereum.md`](references/go-ethereum.md) — build, test, RPC
  method & optional-parameter patterns, in-process RPC test harness.
- [`references/execution-apis.md`](references/execution-apis.md) — OpenRPC YAML,
  `specgen`/`openrpc.json`, `speccheck`, and the `required` semantics.
- [`references/testgen.md`](references/testgen.md) — `rpctestgen`, `make fill`,
  the `.io` format, generating fixtures with a *local* client, determinism.
- [`references/hive.md`](references/hive.md) — the `rpc-compat` simulator,
  local fixtures, building clients from source, client-files, the `--sim.limit`
  trap, reading results.
- [`references/clients.md`](references/clients.md) — per-client handler
  locations and local-build notes (go-ethereum & Nethermind verified; Besu,
  Erigon, Reth, ethrex guidance).
- [`references/gotchas.md`](references/gotchas.md) — the full catalog.
- [`references/worked-example.md`](references/worked-example.md) — a complete
  change end to end (default an omitted block param to `latest`), including a
  real cross-client bug found and fixed.

## Install (Claude Code / Claude Agent)

Personal skills live under `~/.claude/skills/`. Clone into place:

```sh
git clone https://github.com/MysticRyuujin/rpcwright.git ~/.claude/skills/rpcwright
```

Or symlink a working copy:

```sh
git clone https://github.com/MysticRyuujin/rpcwright.git
ln -s "$PWD/rpcwright" ~/.claude/skills/rpcwright
```

Claude discovers the skill from its `SKILL.md` frontmatter and loads it when a
task involves the Ethereum JSON-RPC API, execution-apis, rpctestgen/testgen,
`.io` fixtures, `speccheck`, `openrpc.json`, or hive `rpc-compat`.

## Scope

The execution-apis + testgen + hive workflow is client-agnostic. The
client-specific guidance is **verified** for go-ethereum and Nethermind and is
**best-effort guidance** for Besu, Erigon, Reth, and ethrex — contributions to
verify and extend those are welcome.

## License

MIT — see [LICENSE](LICENSE).
