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

## Besu — Java — VERIFIED

- Handlers: one class per method under
  `ethereum/api/src/main/java/org/hyperledger/besu/ethereum/api/jsonrpc/internal/methods/`
  — `EthGetBalance.java`, `EthGetCode.java`, `EthGetStorageAt.java`,
  `EthGetTransactionCount.java`, `EthGetProof.java`, `EthGetStorageValues.java`.
  Each extends `AbstractBlockParameterOrBlockHashMethod` and implements
  `blockParameterOrBlockHash(request)`.
- **No wire-level pointer trick like the Go clients** — Besu parses params
  manually by index. The block param was read with
  `request.getRequiredParameter(idx, BlockParameterOrBlockHash.class)`, which
  *throws* when the param is absent → the method maps it to
  `-32602 "Invalid block param (block not found)"`. Optionality is explicit in
  code: switch to `getOptionalParameter(idx, BlockParameterOrBlockHash.class)
  .orElse(BlockParameterOrBlockHash.LATEST)`.
- The fix needs a "latest" constant. `BlockParameterOrBlockHash` had none (only
  `BlockParameter.LATEST` exists, a different type), so add one:
  `public static final BlockParameterOrBlockHash LATEST = new
  BlockParameterOrBlockHash("latest");` — its constructor throws a *checked*
  `JsonProcessingException`, so wrap it in a static factory that rethrows as
  unchecked.
- Block-param indices: `getBalance`/`getCode`/`getTransactionCount`/
  `getStorageValues` → index 1; `getStorageAt`/`getProof` → index 2.
- Besu implements all six (including the non-standard `eth_getStorageValues`), so
  one uniform fix covers them all.
- **Gotcha:** the client-visible error string is the `RpcErrorType` enum's static
  message (`INVALID_BLOCK_PARAMS` → "Invalid block param (block not found)"), not
  the `InvalidJsonRpcParameters` detail string in the method's catch block. Don't
  grep the source for the literal client-facing text — find it via `RpcErrorType`.
- Build: `./gradlew installDist` (output `build/install/besu/bin/besu`).
  **JDK version matters:** Besu's `build.gradle` pins a Gradle Java *toolchain*
  (`JavaLanguageVersion.of(25)`), so the build JDK must satisfy it (currently
  JDK 25). A too-old JDK fails with a cryptic
  `Failed to calculate the value of task ':datatypes:compileJava' property
  'javaCompiler'` (toolchain resolution), **not** a clear "wrong Java version".
- hive: `clients/besu/` has `Dockerfile`, `Dockerfile.git`, `Dockerfile.local`.
  `Dockerfile.git` clones `build_args: {github: <org/besu>, tag: <branch>}` and
  runs `./gradlew installDist`. **Gotcha:** the shipped `Dockerfile.git` pinned
  `openjdk-21` (and stale `apt` version pins) and fails the toolchain step —
  switch the builder to a JDK-25 base (e.g. `eclipse-temurin:25-jdk`, runtime
  `eclipse-temurin:25-jre`). The Gradle build is the slow part (tens of minutes).
  Note the source repo moved org: upstream is now `besu-eth/besu`, though hive's
  prebuilt `Dockerfile` still pulls `hyperledger/besu:develop`. Verified: all six
  default-block fixtures pass on a Besu built from a fork with this fix.

## Erigon — Go — VERIFIED

- Handlers: `rpc/jsonrpc/` (note: **not** `turbo/jsonrpc/` — Erigon relocated the
  RPC code). The state methods `GetBalance`, `GetTransactionCount`, `GetCode`,
  `GetStorageAt`, `GetStorageValues` are in `rpc/jsonrpc/eth_accounts.go`;
  `GetProof` is in `rpc/jsonrpc/eth_call.go`; the `EthAPI` **interface** is in
  `rpc/jsonrpc/eth_api.go`.
- Erigon vendors a near-identical copy of go-ethereum's `rpc` package
  (`rpc/json.go`), so the **pointer-for-optional-trailing-param** rule is
  identical: a value-type trailing `rpc.BlockNumberOrHash` is mandatory and an
  omitted block returns `-32602 missing value for required argument N`. The fix
  is the same as geth — change the param to `*rpc.BlockNumberOrHash` and default
  `nil` to latest. Erigon already has a package var `latestNumOrHash =
  rpc.BlockNumberOrHashWithNumber(rpc.LatestBlockNumber)` in `eth_call.go` and
  `Call` already uses the nil-default; add a small `orLatest(*rpc.BlockNumberOrHash)
  rpc.BlockNumberOrHash` helper and resolve at the top of each handler.
- **Gotcha specific to Erigon (unlike geth):** the `EthAPI` interface is consumed
  by *internal Go callers* that pass value-type args, so flipping the signature
  to a pointer breaks them and they must be updated too:
  - `rpc/contracts/direct_backend.go` (the `bind` backend) — `CodeAt`,
    `PendingCodeAt`, `PendingNonceAt`, `NonceAt`. These pass function-call results
    (`BlockNumArg(...)`, `PendingBlockNumArg()`), so introduce a local and pass
    its address.
  - `rpc/mcp/mcp.go` and `rpc/mcp/resources.go` (the MCP server) — several calls;
    `mcp.go` uses a local `blockNumOrHash` (just take `&blockNumOrHash`),
    `resources.go` passes call results (introduce a local).
  - Tests: `rpc/jsonrpc/eth_api_test.go`, `rpc/jsonrpc/corner_cases_support_test.go`.
  Update the **interface** (`eth_api.go`) AND every implementation AND every
  caller, or it won't compile. (geth had no such internal callers, so its change
  was smaller.)
- Build: `make erigon` (hive builds it with `BUILD_TAGS=nosqlite,noboltdb,nosilkworm`).
- hive: `clients/erigon/` has `Dockerfile`, `Dockerfile.git`, `Dockerfile.local`.
  **Use `Dockerfile.local`** (builder `golang:1-alpine`, copies
  `clients/erigon/erigon/`): Erigon's `go.mod` tracks a recent Go (e.g. 1.25.x),
  while `Dockerfile.git` pins an older `golang:1.24.1-alpine` and will fail the
  build until that pin is bumped. Verified: all six default-block fixtures pass
  on a locally-built Erigon with this fix.

## Reth — Rust — VERIFIED (already compliant, no change needed)

- **Reth already defaults an omitted block to latest on all six state methods**,
  so the stock `ghcr.io/paradigmxyz/reth:latest` image passes all six
  default-block fixtures with no source change. (Confirms the #812 note that reth
  already defaults to latest.)
- Why it's already correct: the `EthApiServer` trait in
  `crates/rpc/rpc-eth-api/src/core.rs` declares the block parameter as
  `block_number: Option<BlockId>` on every state method — `balance`,
  `get_code`, `storage_at`, `transaction_count`, `get_proof`, and
  `storage_values` (`eth_getStorageValues`, which reth *does* implement). reth's
  RPC framework (jsonrpsee) treats a trailing `Option<T>` as optional, so an
  omitted parameter arrives as `None`.
- `None` is resolved to latest in `crates/rpc/rpc-eth-api/src/helpers/state.rs`
  via `block_id.unwrap_or_default()` and `state_at_block_id_or_latest`
  ("interprets `None` as `BlockId::Number(BlockNumberOrTag::Latest)`");
  `BlockId::default()` is latest. This is the idiomatic Rust equivalent of geth's
  pointer-default and Besu's `getOptionalParameter(...).orElse(LATEST)`.
- If a future Rust client got this *wrong* (e.g. a required `BlockId` with no
  `Option`), the fix would be to make the trait parameter `Option<BlockId>` and
  `unwrap_or_default()` / default to `BlockNumberOrTag::Latest` — and then run the
  crate's tests (`cargo test -p reth-rpc-eth-api`), since trait-signature changes
  ripple to implementors and tests.
- Build: `cargo build --release --bin reth`. hive: `clients/reth/`
  (`Dockerfile`/`Dockerfile.git`/`Dockerfile.local`). No fix → no PR.

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
