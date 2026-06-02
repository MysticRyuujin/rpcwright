---
name: rpcwright
description: >-
  Use when implementing, changing, or conformance-testing the Ethereum JSON-RPC
  API (the execution-apis / OpenRPC spec) across execution-layer clients. Covers
  the full loop: changing a client (go-ethereum first, plus Nethermind, Besu,
  Erigon, Reth, ethrex), editing the execution-apis OpenRPC spec, writing
  rpctestgen test cases, generating and validating .io fixtures with speccheck,
  and running the hive rpc-compat simulator against one or more clients. Triggers
  on tasks involving eth_* / debug_* / txpool_* JSON-RPC methods, execution-apis
  PRs, rpctestgen / testgen, .io test fixtures, speccheck, openrpc.json, or hive
  rpc-compat. Read this BEFORE guessing build/test steps — it encodes the exact
  commands and the non-obvious gotchas that otherwise cost hours.
---

# rpcwright — Ethereum JSON-RPC standards engineering

A field guide for making and proving a change to the Ethereum execution-layer
JSON-RPC API. The hard part is never the one-line behavior change — it is the
four repos that must agree (the client, the spec, the test generator, the
cross-client harness) and the dozen places a silent failure hides. This skill
encodes the exact commands and the gotchas.

> Conventions in this skill: paths are generic. Set these once and the snippets
> below copy-paste cleanly. Adjust to wherever you cloned each repo.
> ```sh
> export GETH=~/code/go-ethereum          # the client under change (primary)
> export EXECapis=~/code/execution-apis    # the OpenRPC spec + testgen + speccheck
> export HIVE=~/code/hive                   # the cross-client conformance harness
> ```

## The mental model (read this first)

Four moving parts, in dependency order:

1. **The client** (e.g. go-ethereum) implements the RPC method. This is the
   actual behavior.
2. **execution-apis** holds the **OpenRPC spec** — per-method YAML under `src/`
   (`src/eth/*.yaml`, `src/schemas/*.yaml`), compiled into `openrpc.json` by the
   `specgen` tool. This is the *contract*.
3. **testgen** (lives at `execution-apis/tools/testgen`) is Go code defining test
   cases. The `rpctestgen` tool spins up a **real client binary**, runs each case
   against it, and records the request/response as a **`.io` fixture** under
   `execution-apis/tests/<method>/<case>.io`. **speccheck** then validates those
   fixtures against `openrpc.json`.
4. **hive** is the cross-client harness. Its **`rpc-compat`** simulator clones
   execution-apis at a git ref, copies the `tests/` fixtures into a container,
   and **replays each `.io` fixture against the client under test, comparing the
   response byte-for-byte** (via jsondiff). It does **not** consult the OpenRPC
   spec at runtime.

So a behavior change flows through all four:

```
edit client behavior ─▶ add client unit test
        │
        ▼
edit execution-apis OpenRPC YAML ─▶ regenerate openrpc.json (make build)
        │
        ▼
add a testgen case ─▶ generate .io fixtures with the MODIFIED client (make fill)
        │
        ▼
speccheck the fixtures against the spec (make test)
        │
        ▼
hive rpc-compat replays the fixtures against every client (build clients from
local source as needed; assert failed=0)
```

Miss any stage and you get a plausible-but-wrong result: a green hive run that
ran zero tests, a fixture that passes speccheck only because the param was still
"required", or a client that "works" because the harness used a prebuilt image
without your change.

## The golden-path recipe

This is the end-to-end sequence. Each step links to a reference file with the
detail and the traps.

1. **Implement the behavior in the client** and add a unit test that exercises it
   through the real RPC server (not just the Go function). → `references/go-ethereum.md`
2. **Update the OpenRPC spec** in `$EXECapis/src/...` and regenerate:
   `cd $EXECapis && make build`. → `references/execution-apis.md`
3. **Add a testgen case** in `$EXECapis/tools/testgen/generators.go`. → `references/testgen.md`
4. **Generate fixtures with your modified client**: point testgen's go.mod at your
   local client, then `make fill`. Revert any unrelated fixture drift. → `references/testgen.md`
5. **Validate**: `cd $EXECapis && ./tools/speccheck -v`. Sanity-check enforcement
   with a negative test. → `references/execution-apis.md`
6. **Run hive rpc-compat** with your client built from local source, using a
   client-file and the correct `--sim.limit` form. Assert `failed=0`. → `references/hive.md`
7. **Cross-client**: add other clients; investigate any failure — it may be that
   client's bug, which you can patch locally to prove and then report upstream.
   → `references/clients.md`

## The gotchas that cost hours

A condensed list. Full explanations in `references/gotchas.md`.

- **Optional trailing RPC param must be a pointer (go-ethereum).** The geth `rpc`
  package only lets a caller omit a *trailing* argument if its Go type is a
  pointer. A value-type trailing arg is mandatory → `missing value for required
  argument N`. To make a block param optional: `*rpc.BlockNumberOrHash`, default
  `nil` → latest.
- **`--sim.limit` needs the suite prefix.** It is `<suite>/<test>`. A bare string
  is the *suite* pattern. The suite is gated first, so `--sim.limit "my-test"`
  matches no suite and silently runs **0 tests** (a false green). Use
  `--sim.limit "rpc-compat/my-test"`.
- **hive does not check the spec.** rpc-compat replays `.io` fixtures and compares
  responses exactly. The OpenRPC spec only matters for `speccheck` and fixture
  generation. Changing the spec without regenerating fixtures changes nothing in
  hive.
- **speccheck enforces `required` params.** A fixture that omits a param only
  passes if the spec marks that param `required: false`. This is your proof that
  the spec change is doing work — flip it back to `required: true` and watch
  speccheck reject the fixture.
- **A newer client regenerates unrelated fixtures.** If your local client is ahead
  of the version the committed fixtures were made with, `make fill` rewrites
  unrelated `.io` files (e.g. `eth_simulateV1` error-code drift). `git checkout`
  the unrelated changes to keep the diff focused.
- **Use a `go.mod` replace for the local client — don't commit it.** testgen
  builds whatever geth its module resolves; point it at your checkout with a
  `replace` directive, but keep that out of the spec PR (it's an absolute local
  path).
- **Fixtures are deterministic** against the fixed chain in `tools/chain`. A clean
  `make fill` reproduces them byte-for-byte; any change in output is a real
  behavior change.
- **hive defaults to the official prebuilt client image.** To test *your* change
  you must build the client from local source (`dockerfile: local`) — otherwise
  the harness silently tests upstream, not you.

## Reference files

- `references/go-ethereum.md` — build, test, RPC method/param patterns, in-proc RPC test harness.
- `references/execution-apis.md` — OpenRPC YAML, specgen/openrpc.json, speccheck, the `required` semantics.
- `references/testgen.md` — rpctestgen, `make fill`, the `.io` format, local-client `go.mod` replace, determinism.
- `references/hive.md` — rpc-compat architecture, local fixtures, building clients from source, client-files, the `--sim.limit` trap, reading results.
- `references/clients.md` — per-client handler locations and local-build notes: go-ethereum, Nethermind & Erigon (verified), Besu, Reth, ethrex (guidance).
- `references/gotchas.md` — the full gotcha catalog with explanations and fixes.
- `references/worked-example.md` — a complete worked change ("default an omitted block param to latest") end to end, including a real cross-client bug found and fixed.

## Scope notes

Verified end-to-end against **go-ethereum**, **Nethermind**, and **Erigon**. The
remaining clients (Besu, Reth, ethrex) have *guidance* pointers in
`references/clients.md` — treat those as starting points to confirm, not gospel.
The execution-apis and hive workflow is client-agnostic and applies to all of
them.
