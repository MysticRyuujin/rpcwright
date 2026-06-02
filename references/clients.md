# Per-client notes: handler locations and local builds

The execution-apis + hive workflow is client-agnostic. What differs per client is
(a) where the RPC handlers live, (b) how to build it, and (c) how hive builds it
from local source. For hive, the pattern is always the same: drop your modified
source at `clients/<name>/<name>/` and select `dockerfile: local` in a
client-file (see `hive.md`).

Confidence levels are marked. **Verified** = exercised end-to-end in this skill's
worked example. **Guidance** = correct starting points to confirm in-repo.

## go-ethereum — Go — VERIFIED

- Handlers: `internal/ethapi/api.go` (backend: `internal/ethapi/backend.go`,
  `eth/api_backend.go`).
- Optional trailing param idiom: pointer type, default nil → latest. See
  `go-ethereum.md`.
- Build: `make geth`. Test: `go test ./internal/ethapi/`.
- hive local build: `clients/go-ethereum/Dockerfile.local` copies
  `clients/go-ethereum/go-ethereum/` and runs `make geth`. It caches `go.mod`/
  `go.sum` in a separate layer, so dependency downloads are reused across builds.

## Nethermind — C# / .NET — VERIFIED

- Handlers: `src/Nethermind/Nethermind.JsonRpc/Modules/Eth/EthRpcModule.cs`
  (implementation) and `IEthRpcModule.cs` (interface + `[JsonRpcMethod]`
  attributes). Other namespaces follow `Modules/<Ns>/`.
- Optional param idiom: a **nullable parameter with a default** makes it
  optional, e.g. `BlockParameter? blockParameter = null`. A non-nullable
  `BlockParameter blockParameter` (no default) makes the param **mandatory** —
  this is the exact shape of a real bug (see below). The block resolution
  (`_blockFinder.SearchForHeader(blockParameter)`) already treats `null` as
  latest, so making the param nullable is usually the whole fix.
- Build: `dotnet build -c release` from `src/Nethermind/Nethermind.Runner`.
- hive local build: `clients/nethermind/Dockerfile.local` copies
  `clients/nethermind/nethermind/` and runs the dotnet build.

### Real cross-client bug found via this workflow

Nethermind defaulted an omitted block to `latest` for `eth_getBalance`,
`eth_getCode`, `eth_getStorageAt`, `eth_getTransactionCount`, `eth_getProof`
(all declared `BlockParameter? ... = null`) — but **not** for
`eth_getStorageValues`, which declared `BlockParameter blockParameter`
(non-nullable, no default). Omitting the block there returned
`-32602 missing value for required argument 1`. The two-line fix:

```diff
# IEthRpcModule.cs
-  eth_getStorageValues(... StorageValuesRequest requests, BlockParameter blockParameter);
+  eth_getStorageValues(... StorageValuesRequest requests, BlockParameter? blockParameter = null);
# EthRpcModule.cs
-      BlockParameter blockParameter)
+      BlockParameter? blockParameter = null)
```

Pattern worth remembering: when one client fails a single fixture in a family
that otherwise passes, look for the *one method whose param declaration differs
from its siblings*.

## Besu — Java — GUIDANCE

- Handlers: JSON-RPC methods under
  `ethereum/api/src/main/java/org/hyperledger/besu/ethereum/api/jsonrpc/internal/methods/`
  (one class per method, e.g. `EthGetBalance.java`). Parameter parsing is manual
  via `requestContext.getOptionalParameter(...)` / `getRequiredParameter(...)` —
  optionality is explicit in code, so "default to latest" means using the
  optional accessor and substituting `LATEST` when absent.
- Build: `./gradlew installDist` (binary under `build/install/besu/bin/besu`).
- hive: `clients/besu/` — check for `Dockerfile.local`; if absent, add one
  mirroring another client's local Dockerfile, or use `Dockerfile.git` with your
  fork/branch via `build_args: {github: <you/besu>, tag: <branch>}`.

## Erigon — Go — GUIDANCE

- Handlers: the RPC daemon under `turbo/jsonrpc/` (e.g. `eth_call.go`,
  `eth_account.go`). Same Go `rpc` package semantics as geth where shared —
  expect the **pointer-for-optional-trailing-param** rule to apply.
- Build: `make erigon` (and the `rpcdaemon` if RPC is separate).
- hive: `clients/erigon/` — prefer `Dockerfile.local`/`Dockerfile.git`.

## Reth — Rust — GUIDANCE

- Handlers: `crates/rpc/` — particularly `rpc-eth-api` (the `EthApi` trait) and
  `rpc-eth-types`. Optionality is expressed with `Option<BlockId>` parameters;
  default to `BlockId::latest()` (or `BlockNumberOrTag::Latest`) when `None`.
- Build: `cargo build --release --bin reth`.
- hive: `clients/reth/` — `Dockerfile.git` against your fork/branch is usually
  the path of least resistance for Rust clients.

## ethrex — Rust — GUIDANCE

- Handlers: RPC under `crates/networking/rpc/` (eth namespace modules). Same
  `Option<...>` + default-to-latest idiom as other Rust clients.
- Build: `cargo build --release`.
- hive: `clients/ethrex/` — use `Dockerfile.git`/`Dockerfile.local`.

## General per-client checklist for an optional-param change

1. Find the method's handler and how it declares the block param.
2. Make the param optional in that client's idiom (pointer / nullable+default /
   `Option<>` / optional accessor) and default to latest when absent.
3. Add/adjust the client's own unit test if it has one for the method.
4. Build the client; point hive at it via `dockerfile: local` (or `git`).
5. Run rpc-compat with the omitted-param fixture; assert it passes.
