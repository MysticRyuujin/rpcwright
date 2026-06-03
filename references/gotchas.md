# The gotcha catalog

Each entry: the symptom, the cause, the fix. Several entries use the
default-to-latest change as the example, but each is an instance of a broader
class — read them that way.

## 0a. execution-apis CI can't go green for a client-coupled change (chicken-and-egg)

- **Symptom:** the execution-apis PR's `Test` job fails at **`make fill`** /
  "Fail if any files are untracked or have changes", even though `speccheck`
  (`make test`) and `make lint` pass and your fixtures are committed.
- **Cause:** `make fill` regenerates fixtures by building the **geth pinned in
  `tools/go.mod`**. If your change needs new client behavior (a new method, a new
  default, a new result field), upstream-pinned geth doesn't have it, so your new
  testgen cases error or produce different output → the "no changes" gate fails.
  CI does **not** use your local `replace` (it's uncommitted, and pointing it at a
  personal fork branch isn't mergeable). This is structural: a spec+client change
  is a two-PR dance.
- **Fix / expectation:** there is no clean fix until the **client PR merges and
  the execution-apis `go.mod` is bumped** to that geth commit (then `make fill`
  reproduces the fixtures and CI goes green). Until then the red `make fill` is
  *expected* — say so in the PR description, and rely on `speccheck` + the client's
  own tests + a local `make fill` (with the `replace`) as proof. This is what
  "not expected to merge until the client implementation lands" means in practice.

## 0b. Every client repo has its own CI gates / PR rules — check before pushing

- **Symptom:** a PR fails CI on something unrelated to the code — a title check,
  a sign-off check, a formatting check, a missing changelog.
- **Cause:** each client enforces different contributor gates (see the table in
  `references/clients.md`): **conventional-commit PR titles with a *required
  scope*** (ethrex: `feat(l1): …`, scopes `l1|l2|levm`; reth: `feat(rpc): …`);
  **DCO sign-off on every commit** (Besu: `git commit -s`); **`CHANGELOG.md`**
  entry (Besu); **`spotlessApply`** formatting (Besu); `cargo fmt`/`clippy`
  (Rust); a **PR-template release-notes** box (Nethermind); and **test rules
  encoded in `AGENTS.md`/`CONTRIBUTING.md`** (e.g. Nethermind's `AGENTS.md`: a bug
  fix must ship a regression test).
- **Fix:** match the repo's conventions *before* pushing. Read its
  `AGENTS.md`/`CONTRIBUTING.md` and `.github/workflows/` rather than guessing —
  and note that several clients run an **automated AI reviewer** on PRs that
  enforces these rules (it will flag, e.g., a bug fix with no regression test)
  even after human reviewers approve. To fix a missing sign-off retroactively:
  `git rebase --signoff <base>` then force-push.
- **But triage AI-reviewer *findings* skeptically** (distinct from the hard rules
  above): bots (Copilot, claude-review, etc.) mix real issues with false positives
  and over-engineering. Check each against the codebase's actual constraints and
  existing patterns before acting — e.g. an "unbounded allocation / integer
  overflow" finding is moot when the RPC server already caps request-body size,
  and matching a sibling method's behavior (error class, validation order)
  usually beats a one-off "improvement" that makes one method inconsistent.
  Usually **match the reference client and the conformance fixture, not a bot's
  idea of "nicer"** — e.g. a bot suggesting EIP-55-checksummed address keys in a
  response is *wrong* when geth (the reference) and the `.io` fixture use
  lowercase; following it would fail rpc-compat. (Caveat: this holds only while
  the reference client agrees with the spec — if geth itself is the deviation, the
  spec wins and geth gets fixed; see #0d.) Apply the genuinely correct
  ones; decline the rest with a brief rationale on the PR.
- **The maintainer's call governs their repo.** Skepticism applies to your own
  default; it does not override the repo owner. If a maintainer endorses a bot
  suggestion (or asks for a change) you'd have declined — e.g. "put the helper in
  the base class," "use a private constructor for the constant" — implement it.
  They set their codebase's standards, and a declined-bot-finding can become a
  requested change once a human signs off on it.

## 0c. A red CI check may be unrelated/flaky — confirm before chasing it

- **Symptom:** a client PR shows a failing test job.
- **Cause:** large client suites have flaky/timing tests unrelated to your change
  (real example: go-ethereum's `TestTracingHTTPTimeout` in the `rpc` package).
- **Fix:** read which test failed and which package. If it's outside what you
  touched and is timing/infra-flavored, it's not yours — confirm `go vet ./...`
  (or the build) is clean and your own tests pass, note it, and don't chase it.

## 0d. The reference client is not the source of truth — the spec is

- **Symptom:** a client's response differs from the geth-generated `.io` fixture,
  and the reflex is "make the client match geth."
- **Cause:** fixtures are produced by running *one* reference client (go-ethereum),
  so they encode that client's behavior — bugs included. go-ethereum is not
  perfect and is not the authority on Ethereum; client diversity is. Treating
  "geth does X" as the spec turns a geth bug into a conformance requirement for
  everyone else.
- **Fix:** arbitrate by **the spec + rough consensus across clients**, not by geth:
  - If the spec mandates the behavior, the diverging client is wrong → fix it.
  - If **geth** is the one that deviates from the spec (a real regression /
    non-conformance), strongly prefer **fixing go-ethereum and its libraries** for
    conformance, then regenerate the fixture — don't force peers to reproduce the
    deviation.
  - If the spec is silent/ambiguous, it's a standards question: take it to client
    teams (ACD / RPC-standards), get rough consensus, write it into the spec, then
    into fixtures. Don't unilaterally bless the geth behavior.
  See "The spec is the source of truth — not any client" in `SKILL.md`.

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

## 10a. "hive is green" is not "done" — the client's own tests still run in CI

- **Symptom:** you declare the change done after a green hive run, then the PR's CI
  fails to compile or fails unit tests — or a reviewer points out broken tests.
- **Cause:** hive builds only the client *binary* and exercises runtime behavior
  over JSON-RPC. It never compiles or runs the client's own test suite. A
  signature/behavior change commonly breaks (a) internal callers and test callers
  that don't even compile (the hive binary build may not touch them), and (b)
  tests asserting the *previous* behavior.
- **Fix:** before declaring done / opening a PR, also build and run the client's
  own tests for the packages you touched (`go test ./...`, `./gradlew test`,
  `cargo test -p <crate>`), and grep for callers AND for tests asserting the old
  behavior. Definition of done = binary builds + client tests pass + hive green.
  (Real cases: Erigon's `rpc/contracts` + `rpc/mcp` callers and test files;
  Besu's `EthGetProofTest.errorWhenNoBlockNumberSupplied`.)
- **Sub-gotcha — confirm the command actually RAN.** A build/test command can
  exit 0 without doing anything. Real case: ethrex pins Rust via
  `rust-toolchain.toml` while its `.tool-versions` named an uninstalled version;
  under **asdf**, `cargo check`/`cargo test` printed `No version is set for
  command cargo` and **exited 0 without compiling** — a false "pass". Always look
  for the real signal (`Compiling …`, `test result: ok. N passed`) and verify the
  toolchain runs (`cargo --version` / `go version`) before trusting a green exit
  code. Here: `ASDF_RUST_VERSION=1.91.0 cargo test -p ethrex-rpc --lib`.

## 10b. A shared RPC signature change ripples — callers, overrides, client variants

- **Symptom:** after changing a method's signature the client won't compile
  (errors far from the handler), or a behavior change silently misses a variant.
- **Cause:** an RPC interface/base method is reached by more than the dispatcher:
  - **Internal callers.** Erigon's `rpc/jsonrpc` `EthAPI` is called by
    `rpc/contracts/direct_backend.go` (the `bind` backend) and `rpc/mcp/*`, all
    passing value-type args. (geth had none, so its change was smaller.)
  - **Subclasses / overrides and client-variant modules.** Nethermind's
    `EthRpcModule` is extended by Optimism/Taiko/Flashbots/Merge variants — a base
    change is inherited *only* if the variant doesn't override that method.
- **Fix:** update the interface, every implementation, AND every caller; for a
  function-call result you can't address directly, introduce a local
  (`bnh := f(); api.Method(ctx, x, &bnh)`). Then grep the whole tree for callers
  **and for overrides/variants** of the changed method, and confirm each either
  inherits the change or gets its own. (A good completeness check when touching a
  shared method: callers, overrides, sibling client-variant modules, and any
  downstream default the method relies on.)

## 10c. Besu: client-facing error text ≠ source string

- **Symptom:** you grep Besu's source for the error string a client returned
  (e.g. `"Invalid block param (block not found)"`) and find it in `RpcErrorType`,
  not in the method that produced it — the method's `InvalidJsonRpcParameters`
  uses a *different* detail string ("Invalid block or block hash parameter (index
  N)").
- **Cause:** Besu serializes the `RpcErrorType` enum's static `message`, not the
  exception's detail message.
- **Fix:** map the client-visible text via `RpcErrorType`, then find which
  methods throw with that `RpcErrorType` to locate the real handler. For
  optional-param work, the relevant methods read the block with
  `getRequiredParameter(idx, BlockParameterOrBlockHash.class)` (throws when
  absent) — switch to `getOptionalParameter(...).orElse(BlockParameterOrBlockHash.LATEST)`.

## 10. Cross-client divergence read as your bug

- **Symptom:** your client passes a fixture; another client fails it.
- **Cause:** the other client hasn't implemented the behavior (e.g. a
  non-nullable param). It's that client's gap, not yours.
- **Fix:** confirm by reading the `response differs` block; if it's a genuine
  client bug, optionally patch that client locally to prove the fixture is
  correct, then file an upstream report. (See the Nethermind `eth_getStorageValues`
  case in `clients.md`.)
