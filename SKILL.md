---
name: rpcwright
description: >-
  Use when implementing, changing, or conformance-testing the Ethereum JSON-RPC
  API (execution-apis / OpenRPC spec) across execution-layer clients (go-ethereum,
  Nethermind, Besu, Erigon, Reth, ethrex). Covers the full loop: change a client,
  edit the OpenRPC spec, write rpctestgen cases, generate/validate .io fixtures
  with speccheck, run the hive rpc-compat simulator. Triggers on eth_* / debug_* /
  txpool_* methods, execution-apis PRs, rpctestgen / testgen, .io fixtures,
  speccheck, openrpc.json, or hive rpc-compat. Read this BEFORE guessing build/test
  steps — it encodes the exact commands and non-obvious gotchas that cost hours.
---

# rpcwright — Ethereum JSON-RPC standards engineering

A field guide for making and *proving* a change to the Ethereum execution-layer
JSON-RPC API — a new method, a new/changed param, a result-shape or error change, a
deprecation. The hard part isn't the change; it's the four repos that must agree
(client, spec, test generator, cross-client harness) and the many places a silent
failure hides.

**"Default an omitted block param to latest"** (execution-apis
[#812](https://github.com/ethereum/execution-apis/pull/812)) is the running example
below; the workflow is identical for any change. Full narrative:
`references/worked-example.md`.

> Paths are generic — set these once and the snippets copy-paste cleanly:
> ```sh
> export GETH=~/code/go-ethereum         # client under change (primary)
> export EXECapis=~/code/execution-apis  # OpenRPC spec + testgen + speccheck
> export HIVE=~/code/hive                 # cross-client conformance harness
> ```

## The mental model (read this first)

Four moving parts, in dependency order:

1. **The client** (e.g. go-ethereum) implements the method — the actual behavior.
2. **execution-apis** holds the **OpenRPC spec**: per-method YAML under `src/`
   (`src/eth/*.yaml`, `src/schemas/*.yaml`), compiled to `openrpc.json` by
   `specgen`. This is the *contract*.
3. **testgen** (`execution-apis/tools/testgen`) defines test cases; `rpctestgen`
   runs each against a **real client binary** and records the request/response as a
   **`.io` fixture** under `tests/<method>/<case>.io`. **speccheck** then validates
   those fixtures against `openrpc.json`.
4. **hive** is the cross-client harness; its **`rpc-compat`** simulator replays each
   `.io` fixture against a client and compares the response — exact-match via
   jsondiff for ordinary tests, OpenRPC-schema validation for `speconly` tests.

A behavior change flows through all four:

```
edit client behavior ─▶ add client unit test
        ▼
edit OpenRPC YAML ─▶ regenerate openrpc.json (make build)
        ▼
add a testgen case ─▶ generate .io fixtures with the MODIFIED client (make fill)
        ▼
speccheck the fixtures against the spec (make test)
        ▼
hive rpc-compat replays fixtures against every client (build from local source;
assert failed=0)
```

Miss a stage and you get a plausible-but-wrong result: a green hive run that ran
zero tests, a fixture that passes speccheck only because the param stayed
"required", or a client that "works" because hive used a prebuilt image.

## The spec is the source of truth — not any client

The OpenRPC spec is the contract; **no single client is.** `.io` fixtures are
generated from *one* reference client (go-ethereum), so they inherit its behavior —
**including its bugs**. So when a client diverges from a geth-generated fixture,
don't conclude "match geth." Ask: (1) what does the spec mandate? (2) is geth itself
conformant — if geth is the deviation, fix go-ethereum (and its libraries) and
regenerate, don't force peers to copy it; (3) if the spec is silent, settle by rough
consensus across client teams (ACD / RPC-standards), write it into the spec, *then*
into fixtures. "Match the reference/fixture" (which several gotchas recommend) holds
**only while reference and spec agree** — otherwise the spec wins. (Gotcha #0d.)

## The golden-path recipe

Each step links to its reference for the detail and the traps.

1. **Implement in the client** + a unit test through the *real* RPC server (not just the Go function). → `references/go-ethereum.md`
2. **Update the OpenRPC spec** in `$EXECapis/src/...`, then `cd $EXECapis && make build`. → `references/execution-apis.md`
3. **Add a testgen case** in `$EXECapis/tools/testgen/generators.go`. → `references/testgen.md`
4. **Generate fixtures with your client**: `go.mod` replace → `make fill`; revert unrelated fixture drift. → `references/testgen.md`
5. **Validate**: `./tools/speccheck -v`; sanity-check enforcement with a negative test. → `references/execution-apis.md`
6. **Run hive rpc-compat** from local source, correct `--sim.limit` form, assert `failed=0`. → `references/hive.md`
7. **Run the changed client's own test suite** and fix what you broke. → "Definition of done" + `references/clients.md`
8. **Cross-client**: add other clients; a failure may be that client's bug — patch locally to prove, then report upstream. → `references/clients.md`

## What to touch, by change type

Every JSON-RPC change is a combination of the same touchpoints. Find your row, then
use the reference files for each cell. Default-to-latest (making a param optional)
is just one row — the running example.

| Change type | Client: behavior | Client: register? | Spec `src/*.yaml` | Spec schemas | testgen | speccheck angle | hive |
|---|---|---|---|---|---|---|---|
| **New method** | new handler | **yes** (see clients.md) | new method object | add new types if any | new `MethodTests` var + add to `AllMethods`; new `tests/<m>/` | validates params + result schema | replays new fixtures |
| **Add optional param** | read it, default when absent | no | add param `required:false` (+`description`) | if new type | a case with it and without it | enforces `required` | exact-match |
| **Make required param optional** (default-to-latest) | default when omitted | no | flip `required:false` + default | no | an omitted-param case | enforces `required` | exact-match |
| **Change result shape/fields** | build new result | no | edit `result` schema | maybe edit/add | regen (output changes) | result-schema validation | exact-match, every field |
| **Change error code/behavior** | return new error | no | `errors`/error-groups if speced | no | a case with `invalid` in its name (skips result-schema check) | skips error bodies | errors compared only when BOTH sides error |
| **Deprecate / remove** | remove/guard handler | unregister | remove method | no | remove cases + `tests/<m>/` | — | — |

**Registration is per-client.** Most clients auto-expose a method once it's on the
RPC surface (geth reflection; Nethermind interface + `[JsonRpcMethod]`;
reth/Erigon trait/interface). **Besu and ethrex need an explicit entry** (Besu:
`RpcMethod` enum + the methods factory; ethrex: the `rpc.rs` match arm). Per-client
files in `references/clients.md`.

## Definition of done (read before you say "done" or open a PR)

**A green hive run is NOT done.** hive only exercises runtime behavior over
JSON-RPC; it never compiles or runs the *client's own* test suite — but the PR's CI
does. A signature/behavior change routinely breaks (a) internal and test callers
that the hive binary build may never compile (e.g. Erigon's `rpc/contracts` +
`rpc/mcp`), and (b) tests asserting the OLD behavior (e.g. Besu's
`EthGetProofTest.errorWhenNoBlockNumberSupplied`). Done = **all three**: client
binary builds + the client's own tests (for the modules you touched) compile and
pass + hive `rpc-compat` green. Confirm this *before* the PR, not after a reviewer.

### Pre-PR checklist (run top to bottom)

- [ ] Client **binary builds** from your branch (what hive runs).
- [ ] **grep the whole tree** for callers, overrides, and client-variant modules of any signature you changed; update each (#10b).
- [ ] Client's **own tests compile and pass** for touched modules (`go test ./...` / `./gradlew test` / `cargo test -p <crate>`) — and confirm the command *actually ran*, not a toolchain no-op (#10a/#0c).
- [ ] A **regression test hits the exact path you changed** (the *omitted* param, the new method/error) — not a near-miss that passes the param explicitly.
- [ ] **Comments are terse** — one line of WHY for non-obvious decisions only; reviewers across every client cut verbose comments (#0e).
- [ ] **hive `rpc-compat` is green** for the target tests, built from *your* source (`dockerfile: local`/`git`), with `--sim.limit "rpc-compat/<test>"`.
- [ ] **Self-review for copy-paste duplication** from a sibling method: extract the shared body into one helper at *that* layer, collapse two methods that differ only in what they return, add no needless new exported API (#11).
- [ ] **Repo CI gates** (#0b): conventional-commit title + required scope, DCO sign-off, CHANGELOG, formatter — skim the repo's `.github/workflows/` so you know what runs.

## The gotchas that cost hours (full detail: `references/gotchas.md`)

- **Optionality idiom is per-client** (#1, clients.md): geth needs a *pointer* trailing arg (a value type is mandatory → `missing value for required argument N`); reth `Option<T>`; Nethermind `T? = null`; Besu `getOptionalParameter`; ethrex a manual `params.len()` check. Every change must match how that client expresses params/results.
- **`--sim.limit` needs the suite prefix** (#2): it's `<suite>/<test>`; a bare string matches no suite and runs **0 tests** at exit 0 (false green). Use `rpc-compat/<test>` and assert `tests>0`.
- **hive checks the spec only for `speconly`** (#9, hive.md): ordinary tests replay the `.io` fixture exact-match, so changing the spec without regenerating the fixture does nothing; `speconly` tests validate against the OpenRPC result schema (ship `openrpc.json` into the sim).
- **`speconly` fixtures must be GENERATED, not hand-written** (testgen.md): a fixture inherits the reference client's *config* (which optional fields it emits), so a hand-copied one can encode values no node produces and fail replay. Back every `speconly` method with a generator. `eth_capabilities` is the example.
- **speccheck enforces `required`** (#4): an omitted-param fixture passes only if the spec marks the param `required: false` — that's your proof the spec change is load-bearing.
- **A newer client regenerates unrelated fixtures** (#5): `make fill` rewrites drifted `.io` files (e.g. `eth_simulateV1` error codes); `git checkout` them to keep the diff focused.
- **Don't commit the `go.mod` replace** (#6): it's an absolute local path; the real change is a version bump once the client PR merges.
- **Fixtures are deterministic** (testgen.md) against the fixed `tools/chain` — any output change is a real behavior change.
- **hive defaults to the prebuilt upstream image** (#3): build from local source (`dockerfile: local`) or it silently tests upstream, not you.
- **A shared signature change ripples** (#10b): update the interface, every impl, every caller, AND client-variant overrides — grep for all of them.
- **Keep comments terse** (#0e): one line of WHY only; verbose comments reliably cost a review round on every client.
- **Copying a sibling method is a refactor signal** (#11): extract the shared body first (at the layer the duplication is in), make both thin wrappers; two methods differing only in what they return → one returning the union; minimize new exported API.
- **A green hive run is not "done"** (#10a): see Definition of done above.

## Reference files

- `references/go-ethereum.md` — build, test, RPC method/param patterns, in-proc RPC test harness.
- `references/execution-apis.md` — OpenRPC YAML, specgen/openrpc.json, speccheck, `required` semantics.
- `references/testgen.md` — rpctestgen, `make fill`, the `.io` format, local-client `go.mod` replace, determinism.
- `references/hive.md` — rpc-compat architecture, local fixtures, building clients from source, client-files, the `--sim.limit` trap, reading results.
- `references/clients.md` — per-client handler locations, registration, optionality idioms, builds, and CI gates: go-ethereum, Nethermind, Erigon, Besu, Reth, ethrex (all verified).
- `references/gotchas.md` — the full gotcha catalog with explanations and fixes.
- `references/worked-example.md` — the default-to-latest change end to end across all six clients, including a real cross-client bug found and fixed.
