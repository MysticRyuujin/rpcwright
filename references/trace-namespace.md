# Trace namespace — standardizing Parity-style trace_* methods

Use this reference for work on the `trace_*` namespace: the draft spec, client
alignment, or cross-client evidence. For `debug_trace*` named tracers, read
[tracers.md](tracers.md). Read [execution-apis.md](execution-apis.md) before a
schema edit and [hive.md](hive.md) before a Hive run.

**Status: work in progress.** This summary reflects banteg/trace-interop on
2026-10-12. Decisions, client results, and PR states change often. Read the
current repository before you cite a status, a verdict, or a client position.

## Where the work lives

| Item | Location |
| --- | --- |
| Evidence, decisions, reports | https://github.com/banteg/trace-interop |
| Draft spec PR | execution-apis [#895](https://github.com/ethereum/execution-apis/pull/895) (draft) |
| Draft spec source | `banteg/execution-apis` branch `feat/trace`; trace-interop pins a commit in `spec.lock.json` |
| Standardization discussion | execution-apis [#890](https://github.com/ethereum/execution-apis/issues/890) |
| Candidate geth implementation | `banteg/go-ethereum` branch `feat/trace`; go-ethereum [#35791](https://github.com/ethereum/go-ethereum/pull/35791) |
| Client fix queue | `docs/client-fixes.md`, generated from `decisions/fixes.json` |

Scope: all nine methods (`trace_call`, `trace_callMany`, `trace_rawTransaction`,
`trace_replayTransaction`, `trace_replayBlockTransactions`, `trace_block`,
`trace_transaction`, `trace_get`, `trace_filter`). The output families are the
call trace (`trace`), `stateDiff`, and `vmTrace`.

Measured clients: Besu, Erigon, Nethermind, and Reth (release and development
builds), the geth fork, and Anvil. Upstream geth has no `trace_*` namespace. The
geth fork is a candidate implementation. It is not a client vote, and it is not
upstream geth support. Anvil is reported, but it does not count toward
harmonization.

## How the repository is organized

- `decisions/ledger.json`: decisions H01–H33. Each has a question, a
  recommendation, a rationale, and the `corpus/case` IDs that test it. This is
  the source of truth for the proposed behavior.
- `decisions/status.json`: policy status and stated client positions, each with a
  source. `decisions/impact.json`: proposed client changes in plain text.
- `decisions/sources.json`: client source links, pinned to a revision with a line
  anchor and a file hash.
- `fixtures/chains`, `fixtures/corpora`: frozen research chains and request sets.
- `evidence/<date>/<run>`: raw requests, responses, logs, and build locks.
  Checksummed. Never rewrite them.
- `reports/`: generated pages. Do not edit them by hand.
- `docs/source-review/`: the 2026-09-24 review of the draft against Parity,
  client source, and the sibling `eth_*` methods. Its recommendations are now in
  the ledger.

Read `decisions/README.md` for the current status of each decision. Read
`reports/clients/<client>.md` for one client's differences with source links.

## Commands

The repository uses uv. Capture needs Linux and Docker. Report and unit checks
also run on macOS.

```sh
uv sync --locked
uv run trace-interop verify
uv run python scripts/check_schema.py
uv run python scripts/build_reports.py
scripts/check.sh                 # the full CI check
```

Run the current matrix (latest releases, development images, geth fork head):

```sh
uv run python scripts/run_matrix.py --output runs/current-matrix
```

Reproduce one case against a frozen build:

```sh
uv run trace-interop run --lock locks/clients-2026-09-21.json \
  --clients reth_release --corpus initial --case '^get-root$' --output runs/reth-root
uv run trace-interop report --run runs/reth-root --output runs/reth-root-report
```

Show one case across builds:

```sh
uv run python scripts/compare_responses.py show <evidence-run-dir> <case> --family trace
```

To change the draft, edit YAML in the execution-apis fork and push `feat/trace`.
Then run `scripts/pin_spec.py <execution-apis checkout>`, `check_schema.py`, and
`build_reports.py`. Commit the lock, the artifact, and the reports together.
Do not edit `spec/trace-openrpc.json`; it is a build artifact.

Confirm these commands in the target revision. `docs/usage.md` is the full guide.

## Proposed rules by area

Each row names the decisions. Read the ledger recommendation before you rely on
a rule; this table omits conditions and exceptions.

| Area | Decisions | Core rule |
| --- | --- | --- |
| Method scope | H01 | All nine methods are required. An unserved method returns -32601, never an empty result. |
| Lookup results | H02, H06 | `trace_get` takes one `traceAddress` path of hex quantities. A missing transaction or path returns `null`. `[]` means an evaluated empty collection. An unknown block returns an error (-32001 recommended). |
| Filters | H03, H04, H23, H30, H32, H33 | OR within an address list, AND between lists. `mode: "union"` is optional. Empty, null, or omitted lists do not restrict. Omitted bounds default to `latest`. Range errors follow `eth_getLogs` (-32602). `blockHash` selects one block. |
| Rewards and system operations | H05, H27, H28 | No synthetic PoS reward. Genesis has no records. System calls and withdrawals change replay state but are not trace records. |
| Envelope | H07, H08, H11 | Replays carry `transactionHash`. `output` is `"0x"` when empty. `trace` is `[]` and `stateDiff`/`vmTrace` are `null` when not requested. An empty type list is valid. |
| Call frames | H09, H10, H22, H24, H29 | `error` alone marks failure, with Parity labels ("Reverted", "Out of gas", ...). REVERT keeps `result {gasUsed, output}`. Every create has `creationMethod`. Nested zero-value precompile calls are omitted; root and value-carrying ones stay. |
| Simulation inputs | H12, H13, H14, H15, H31 | Unsigned calls follow `eth_call` fee rules: zero price runs with BASEFEE 0. Raw transactions get full execution validation, not pool policy. Explicit `null` equals omission. Errors reuse `eth_simulateV1` and `eth_sendRawTransaction` codes. |
| Errors in transit | H25 | A failure before output is one JSON-RPC error. A failure after output aborts the transport. |
| stateDiff | H16, H17, H18, H26 | `+`/`-` only for birth and death. `*` for changed fields and slots. Deleted accounts report `storage: {}`. An account absent at both endpoints has no entry. Block-level operations belong to no transaction. |
| vmTrace | H19, H20, H21 | `code` is the executed bytecode. `mem` is the post-operation content of the operand range. Stack words are minimal hex quantities; `pc`, `cost`, and `used` are integers. |

## Statuses and what they mean

- Policy status: Under review, Diverging, Converged, Harmonized · dev, and
  Harmonized · stable. "Converged" means aligned direction. It is not unanimous
  formal approval.
- Per-build verdict: agree, differ, fix submitted, partial, unassessed, blocked,
  and control. Blocked and control are not passes.
- A client position is a stated view with a source, or a merged non-partial fix.
  Silence is "no response". It is not agreement.

Do not report "Converged" as an approved standard. Upstream acceptance needs
rough consensus from client reviewers on PR #895, not a vote count. See the
trace-interop file `docs/upstream-acceptance.md`.

## Path to upstream fixtures

The trace-interop corpora run on research chains. Their hashes do not match the
execution-apis test chain. Do not copy them into `.io` fixtures.

When a rule is agreed:

1. Add or adapt a small case on the upstream hivechain chain. Start with one
   ordinary transaction and one discriminating edge case.
2. Generate fixtures through the normal path ([testgen.md](testgen.md)). The
   normal path uses upstream geth, which has no `trace_*` methods. A fill with
   the geth fork or a hand-written `.io` file needs an explicit maintainer
   exception. State which path you used.
3. Replay through Hive `rpc-compat` on exact client commits ([hive.md](hive.md)).

PR #895 and callTracer PR #855 both change recursive-schema tooling. Check the
current state of both before you split upstream patches. See
[tracers.md](tracers.md) for the `$id` self-reference pattern.

## Gotchas

- **Hive failure counts are not conformance results.** `trace-interop run` uses
  placeholder expectations to record responses. Use `trace-interop report` for
  verdicts. Read `summary.json` first: launch and setup failures are not
  semantic differences.
- **Schema validity does not prove execution.** The harness checks schemas and
  semantic assertions separately. A schema-valid response can still be wrong.
- **Client agreement does not prove correctness.** The harness uses
  independent models (a bounded VM, fee and state models), not a majority answer.
- **Build selection.** Reports use the most recently captured build per client
  and channel. Results from older builds never fill gaps.
- **Reth nightly can be older than the latest release.** The preflight lists such
  builds under `lagging_development`.
- **Anvil runs as a replica.** It has no Engine API. The harness mines each block
  again. Chains with fork transitions, reorg scenarios, and pruning scenarios
  cannot run on Anvil.
- **`trace_get` paths are not portable across clients.** Precompile frame
  inclusion changes sibling indexes. Anchor a path to the same client's
  `trace_transaction` response.
- **Dirty sources.** A run with `source_dirty` is a development capture. Do not
  present it as a clean reproduction.
- **Source citations drift.** Re-read the cited lines at the pinned revision
  before you rely on a claim from the source review.

## Recording a disagreement

For a client that disputes a rule, record these items (from `docs/review.md`):

1. The rule and a minimal discriminating case.
2. Each build's observation, including unsupported, error, and setup outcomes.
3. The kind of question: execution correctness, API semantics, output encoding,
   or scope.
4. The recommendation and its evidence.
5. The effect on existing consumers. Do not estimate effort from failure counts.
6. The client feedback and its disposition.

Keep optional extensions and open policy choices separate from client bugs.
