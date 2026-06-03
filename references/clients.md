# Per-client notes: handlers, registration, builds, and PR conventions

The execution-apis + hive workflow is client-agnostic. What differs per client is
(a) where RPC handlers live, (b) **how a method is registered/exposed**, (c) how
params/results are typed (and the optionality idiom), (d) how to build and test
it, and (e) the repo's **PR conventions / CI gates**. This file covers all five
so the skill serves *any* change — new method, modified params/results, error
behavior, deprecation — not just default-to-latest.

For hive, the local-build pattern is the same everywhere: put your modified
source where the client's `Dockerfile.local` expects it (`clients/<name>/<name>/`)
and select `dockerfile: local`, OR build from a fork branch with
`dockerfile: git` + `build_args: {github, tag}` (see `hive.md`).

## Per-client cheat sheet

| Client | Lang | RPC handlers | How a method is registered/exposed | Optional-param idiom | Build / run tests |
|---|---|---|---|---|---|
| go-ethereum | Go | `internal/ethapi/*.go` | **Automatic** — exported method on an API service struct (`eth_<method>` = lowercased name); only edit `backend.go` `GetAPIs()` for a *new service struct* | `*T` pointer trailing arg (nil = omitted) | `make geth` / `go test ./internal/ethapi/` |
| Erigon | Go | `rpc/jsonrpc/*.go` | **Add to `EthAPI` interface** (`eth_api.go`) + `APIImpl` method; exposed via `rpc.API` in `daemon.go` | `*rpc.BlockNumberOrHash` pointer | `make erigon` / `go test ./rpc/jsonrpc/...` |
| Nethermind | C# | `…/Modules/Eth/EthRpcModule.cs` | **Add to `IEthRpcModule` + `[JsonRpcMethod]`**; auto-registered; only touch `EthModuleFactory` for new ctor deps | nullable `T? x = null` | `dotnet build` / NUnit in `…JsonRpc.Test` |
| Reth | Rust | `crates/rpc/rpc-eth-api/src/core.rs` + helpers | **Add `#[method(name=…)]` to the `EthApiServer` trait** + impl; auto-registered via `into_rpc()` | `Option<BlockId>` (None→latest) | `cargo build` / `cargo test -p reth-rpc-eth-api` |
| Besu | Java | `…/jsonrpc/internal/methods/*.java` | **3 edits:** method class + `RpcMethod` enum + the methods *factory* (`EthJsonRpcMethods`) | `getOptionalParameter(i, …)` | `./gradlew installDist` / `./gradlew test` (JDK per build) |
| ethrex | Rust | `crates/networking/rpc/eth/*.rs` | **Add a `match` arm** in `rpc.rs` (`"eth_x" => XRequest::call(...)`) + an `RpcHandler` (parse/handle) | manual `params.len()` + `Option`-style default | `cargo build` / `cargo test -p ethrex-rpc` |

**Registration takeaway:** geth/Erigon/Nethermind/Reth auto-expose a method once
it's on the API surface; **Besu and ethrex require an explicit registry/dispatch
entry** — forget it and the method is "method not found" even though the handler
compiles.

## PR conventions & CI gates (what gets a PR bounced)

These are enforced by CI and/or reviewers — get them right *before* pushing:

- **go-ethereum**: commit/PR title `package: imperative summary` (e.g.
  `internal/ethapi: …`); tests expected; reviewers require a matching
  **execution-apis spec** PR and often wait for another client + a release
  boundary; prefer the `eth` namespace and the most general API shape.
- **Erigon**: title `rpc:`/`rpc/jsonrpc:`; tests must exercise the new branch
  (reviewers flag coverage gaps); strong push on execution-apis field-shape
  compliance; spec-conformance via the external `erigontech/rpc-tests` (an
  `RPC_VERSION` tag).
- **Nethermind**: fill the **PR template** — reviewers flag blank templates and
  require the **release-notes** box ticked for user-visible RPC changes; tests
  required; return `ResultWrapper.Fail(...)` rather than throwing (the client
  sees the `RpcErrorType` message, not the exception detail).
- **Reth**: **conventional-commit titles** (`feat(rpc): …`); `cargo fmt` +
  `cargo clippy` + tests are CI gates; no DCO.
- **Besu**: **DCO sign-off on every commit** (`git commit -s`, CI-enforced);
  **`CHANGELOG.md`** entry under `## Unreleased` — the section is *structured* and
  reviewers point you to the exact nested heading. An RPC behavior change goes
  under `### Breaking Changes` → as a **sub-bullet of the existing
  `- RPC changes to enhance compatibility with other ELs` bullet** (not a new
  top-level bullet). Note Besu files RPC behavior changes as *Breaking Changes*
  **even when they improve cross-client compatibility** (e.g. defaulting an
  omitted block param to `latest`). Match an adjacent sub-bullet's style:
  one line — what changed, the affected RPCs, and a trailing PR link. A CHANGELOG-only
  (markdown) change does **not** need `./gradlew spotlessApply` or a Gradle build
  — spotless gates Java/license headers, not markdown. Otherwise:
  **`./gradlew spotlessApply`** (formatting/license-header gate); add a unit test
  *and* a JSON spec scenario under `src/test/resources/.../jsonrpc/eth/` (BySpec
  tests).
- **ethrex**: **conventional-commit PR titles with a required scope** — CI lints
  the title (`.github/workflows/pr_lint_pr_title.yml`); allowed types `feat fix
  perf refactor revert deps build ci test style chore docs`, scopes **`l1` `l2`
  `levm`** (`requireScope: true`), e.g. `feat(l1): …`. An AI reviewer checks hex
  formatting (quantities `{:#x}` vs 32-byte values `0x{:064x}` vs addresses
  `{:#x}`) and `notFound → null` semantics; intentionally-skipped tests must be
  noted in `docs/known_issues.md`.

> The exact rules drift — when a title/format check fails, read the failing
> workflow under the client's `.github/workflows/` rather than guessing.

## go-ethereum — Go

- Handlers: `internal/ethapi/api.go` (backend: `internal/ethapi/backend.go`,
  `eth/api_backend.go`).
- Optional trailing param idiom: pointer type, default nil → latest. See
  `go-ethereum.md`.
- Build: `make geth`. Test: `go test ./internal/ethapi/`.
- hive local build: `clients/go-ethereum/Dockerfile.local` copies
  `clients/go-ethereum/go-ethereum/` and runs `make geth`. It caches `go.mod`/
  `go.sum` in a separate layer, so dependency downloads are reused across builds.

## Nethermind — C# / .NET

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

### Example: a single-method divergence

A useful pattern — Nethermind defaulted an omitted block to `latest` for `eth_getBalance`,
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

## Besu — Java

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
  prebuilt `Dockerfile` still pulls `hyperledger/besu:develop`.

## Erigon — Go

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
  build until that pin is bumped.

## Reth — Rust

- Handlers: the `EthApiServer` trait in `crates/rpc/rpc-eth-api/src/core.rs`;
  logic lives in helper traits under `crates/rpc/rpc-eth-api/src/helpers/`. A new
  method is `#[method(name = "...")]` on the trait plus an impl — jsonrpsee
  auto-registers it (`into_rpc()`), no manual wiring.
- Optional param idiom: a trailing `Option<T>` (e.g. `block_number:
  Option<BlockId>`). jsonrpsee treats a trailing `Option` as optional, so an
  omitted argument arrives as `None`, which resolves to latest via
  `block_id.unwrap_or_default()` / `state_at_block_id_or_latest` in
  `helpers/state.rs` (`BlockId::default()` is latest) — the Rust equivalent of
  geth's pointer-default and Besu's `getOptionalParameter(...).orElse(LATEST)`.
  A *required* `BlockId` is made optional by switching it to `Option<BlockId>`
  and defaulting `None` to latest.
- Build: `cargo build --release --bin reth`. Tests: `cargo test -p
  reth-rpc-eth-api` (trait-signature changes ripple to impls and tests).
- hive: `clients/reth/` (`Dockerfile`/`Dockerfile.git`/`Dockerfile.local`).

## ethrex — Rust

- Handlers: `crates/networking/rpc/eth/account.rs` — one struct + `RpcHandler`
  impl per method (`GetBalanceRequest`, `GetCodeRequest`, `GetStorageAtRequest`,
  `GetTransactionCountRequest`, `GetProofRequest`). Method dispatch is a
  `match` on the method name in `crates/networking/rpc/rpc.rs`
  (`"eth_getBalance" => GetBalanceRequest::call(...)`).
- **Unlike reth, ethrex does NOT auto-handle optional trailing params.** Each
  `parse` does a strict `if params.len() != N { return Err(BadParams("Expected N
  params")) }` and then `BlockIdentifierOrHash::parse(params[idx], idx)`, so
  omitting the block returned `-32000 "Expected N params"`. Fix: relax the check
  to accept `N-1` or `N`, and parse the block as
  `params.get(idx).map(|b| BlockIdentifierOrHash::parse(b.clone(), idx)).transpose()?.unwrap_or_default()`.
  Add `impl Default for BlockIdentifierOrHash` returning latest —
  `BlockTag` already derives `#[default] Latest` and `BlockIdentifier` had a
  `Default`, but `BlockIdentifierOrHash` did not.
- **ethrex did not implement `eth_getStorageValues`** (returned `-32601 method
  not found`). It's small to add (~45 LOC): a `GetStorageValuesRequest` that
  batches `get_storage_at` over a `map<address, slots>` at a block, with the same
  optional-block default and a 1024-slot cap; register it in the `rpc.rs` match.
- Build/test: cargo workspace; the RPC crate is `ethrex-rpc`. Run
  `cargo test -p ethrex-rpc --lib`.
- **Toolchain gotcha (cost me a false "pass"):** ethrex pins Rust via
  `rust-toolchain.toml` (e.g. channel `1.91.0`) and ships a `.tool-versions` that
  may pin a *different / not-installed* version. If your shell uses **asdf**,
  `cargo` can print `No version is set for command cargo` and **exit 0 without
  running** — a silent no-op that looks exactly like a passing build. Always
  confirm cargo actually ran (`cargo --version` prints a version); override with
  e.g. `ASDF_RUST_VERSION=1.91.0 cargo ...`. (See gotcha #10a — confirm your
  command actually executed.)
- hive: `clients/ethrex/` has `Dockerfile` and `Dockerfile.git` (no
  `Dockerfile.local`). Build from a fork via `build_args: {github: <you/ethrex>,
  tag: <branch>}`; the `Dockerfile.git` `rust:latest` builder + ethrex's
  `rust-toolchain.toml` auto-fetches the pinned toolchain.
- Caveat: ethrex's hive default-chain state-serving has gaps — a stock ethrex can
  return `0x0`/`null` for account state at `latest`, so rpc-compat *value*
  fixtures for the state methods may fail independent of any spec change. Apply
  gotcha #0c: check whether the client fails the same call with an *explicit*
  block before blaming your change, and prove the change via the client's unit
  tests + omitted==explicit-block equivalence rather than the fixture value.

## General per-client checklist for any change

1. **Locate** the handler(s) and, for a new method, the registration point (cheat
   sheet above).
2. **Make the change** in that client's idioms — param optionality (pointer /
   nullable+default / `Option<>` / optional accessor), result type, error type,
   or a new handler + registration.
3. **Add/adjust the client's own tests** — a new test for new behavior, and fix
   any test asserting the *old* behavior. Grep for callers of a changed
   signature.
4. **Build AND run the client's tests** (definition of done) — and confirm the
   command actually ran (toolchain shims can no-op; see gotcha #10a).
5. **Point hive at your build** (`dockerfile: local` or `git` + fork branch) and
   run rpc-compat. If a value fixture fails, check whether the client fails the
   same call with an *explicit* block before assuming your change is the cause.
6. **Meet the repo's PR conventions/CI gates** (sign-off, changelog, formatting,
   conventional-commit title with required scope) before opening the PR.
