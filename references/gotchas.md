# The gotcha catalog

Each entry: the symptom, the cause, the fix.

## 1. Omitted trailing RPC param rejected (go-ethereum)

- **Symptom:** `-32602 missing value for required argument N` when a caller omits
  the last positional param.
- **Cause:** geth's `rpc` package (`rpc/json.go: parsePositionalArguments`) only
  allows omitting a trailing arg if its Go type is a **pointer**. Value types are
  mandatory.
- **Fix:** declare the param `*T` and default `nil` (→ latest, etc.). Mirror
  `eth_call`'s `*rpc.BlockNumberOrHash`.

## 2. `--sim.limit` runs zero tests but exits green

- **Symptom:** hive prints `suites=0 tests=0 failed=0`, exit 0. Feels like a pass.
- **Cause:** `--sim.limit` is `<suite>/<test>`. A bare value is the *suite*
  pattern; it doesn't match the suite name `rpc-compat`, and the suite gate runs
  before any test.
- **Fix:** `--sim.limit "rpc-compat/<testregex>"`. Always assert `tests=N>0`.

## 3. hive "passes" but didn't test your change

- **Symptom:** green run, but the behavior isn't actually exercised.
- **Cause:** the client's default `Dockerfile` uses a **prebuilt upstream image**;
  and/or the simulator pulled execution-apis from GitHub instead of your local
  fixtures.
- **Fix:** build the client from local source (`dockerfile: local`, source at
  `clients/<name>/<name>/`) AND uncomment `ADD tests /execution-apis/tests` in
  the rpc-compat Dockerfile after copying your `tests/` in.

## 4. speccheck passes vacuously

- **Symptom:** an omitted-param fixture passes even though you're unsure the spec
  change took effect.
- **Cause:** speccheck only rejects an omitted param when the spec marks it
  `required: true`. If you already flipped it to `false`, it passes — correctly,
  but you haven't proven the change is doing work.
- **Fix:** run the negative test in `execution-apis.md` (temporarily flip back to
  `required: true`, confirm speccheck rejects, restore).

## 5. Unrelated fixtures change during `make fill`

- **Symptom:** `git status tests/` shows edits to methods you didn't touch (often
  `eth_simulateV1` error codes, e.g. `-32602` → `-38012`).
- **Cause:** your local client is newer than the version the committed fixtures
  were generated with; their output legitimately drifted.
- **Fix:** `git checkout -- tests/<unrelated>/` to revert. Commit only the
  fixtures your change introduced/affected.

## 6. Committing the local `go.mod` replace

- **Symptom:** CI/others can't build `execution-apis/tools` — it points at an
  absolute local path.
- **Cause:** the `replace github.com/ethereum/go-ethereum => /abs/path` you added
  to generate fixtures with your local client got committed.
- **Fix:** keep it out of the PR (`git restore tools/go.mod tools/go.sum` before
  committing, or never `git add` them). The real dependency change is a version
  bump once the client PR merges.

## 7. False compiler diagnostics on generators.go

- **Symptom:** editor/LSP reports `undefined: Chain` / `undefined: TxInfo` in
  `tools/testgen/generators.go`.
- **Cause:** single-file analysis; those types are defined in sibling files
  (`chain.go`, `utils.go`).
- **Fix:** trust `go build ./testgen/`. If it builds, it's fine.

## 8. Fixture vs chain mismatch

- **Symptom:** a fixture that should pass fails with wrong values on replay.
- **Cause:** the `.io` fixture was generated against a different chain than the
  one in the simulator's `tests/` dir.
- **Fix:** fixtures are only valid against their chain. Keep `chain.rlp` /
  `genesis.json` and the `.io` files from the same generation. `cmp` chains
  before mixing fixtures from different sources.

## 9. Spec change with no hive effect

- **Symptom:** you edited the OpenRPC YAML, but hive behavior is unchanged.
- **Cause:** hive replays `.io` fixtures and does **not** read the spec.
- **Fix:** the spec drives `speccheck` and documents the contract; to change what
  hive enforces you must (re)generate and ship `.io` fixtures.

## 10b. Changing an RPC interface signature breaks internal Go callers

- **Symptom:** after switching a method's param to a pointer (for wire
  optionality), the client no longer compiles — errors far from the handler.
- **Cause:** in some clients the RPC interface is consumed by *internal* Go code,
  not just the JSON-RPC dispatcher. Erigon is the example: `rpc/jsonrpc`'s
  `EthAPI` is called by `rpc/contracts/direct_backend.go` (the `bind` backend)
  and `rpc/mcp/*` (the MCP server), all passing value-type args. (geth had no
  such internal callers, so its change was smaller.)
- **Fix:** update the interface declaration, every implementation, AND every
  caller. For callers that pass a function-call result you can't take the address
  of directly — introduce a local: `bnh := f(); api.Method(ctx, x, &bnh)`. Grep
  the whole tree for callers before assuming the change is local.

## 10. Cross-client divergence read as your bug

- **Symptom:** your client passes a fixture; another client fails it.
- **Cause:** the other client hasn't implemented the behavior (e.g. a
  non-nullable param). It's that client's gap, not yours.
- **Fix:** confirm by reading the `response differs` block; if it's a genuine
  client bug, optionally patch that client locally to prove the fixture is
  correct, then file an upstream report. (See the Nethermind `eth_getStorageValues`
  case in `clients.md`.)
