# Failure reference

Search by symptom. Check historical observations against the target revision
before applying a fix. Use the linked reference for the full procedure.

## 0a. Fixture generation fails in CI with the pinned client

`make fill` builds the geth revision selected by `tools/go.mod`. A local replace
can pass while CI fails because the pinned revision lacks the new behavior.
Record the dependency on the client change. After it becomes available, update
the dependency and regenerate. Do not commit an absolute local replace.
See [testgen.md](testgen.md).

## 0b. Repository contribution checks fail

Read the target repository's instructions, PR template, and workflows before
preparing a PR. Titles, DCO, changelog structure, and formatting rules vary.
Treat examples in [clients.md](clients.md) as guidance for the inspected revision.
Verify review findings against the code and spec before applying them.
A request-size limit alone does not prove that allocation or arithmetic is safe.

## 0c. A test failure appears unrelated

Reproduce the failure on the unchanged baseline with the same toolchain,
client build, fixtures, and configuration. Record both results.
A failure outside the edited package or a timing-sensitive test is not sufficient
proof that the change is unrelated. If reproduction is unavailable, report the
cause as unresolved.

## 0d. A client differs from a geth-generated fixture

Check the spec first. If geth violates the contract, correct the reference behavior
and regenerate within the task's scope. If the contract is ambiguous, identify the
standards decision needed. A recorded response does not establish that decision.

## 0e. Comments repeat the implementation

Follow the target repository's comment style. Explain a non-obvious invariant or
workaround when needed. Remove comments that only restate the code.

## 1. An omitted trailing parameter is rejected

In geth, `rpc/json.go` accepts missing trailing pointer arguments and supplies nil.
A value argument produces `missing value for required argument N`.
Use the client's optionality convention and test through RPC dispatch.
See [go-ethereum.md](go-ethereum.md) and [clients.md](clients.md).

## 2. Hive exits successfully without running the requested fixtures

`--sim.limit` uses `<suite-pattern>/<test-pattern>`. Use
`--sim.limit 'rpc-compat/<test-regex>'` and inspect the executed case names.
A bare test pattern can exclude the suite. A valid suite with no matching
fixtures can still run launch tests, so `tests > 0` is insufficient.
Confirm the intended fixtures run for every selected client.
See [hive.md](hive.md).

## 3. Hive tests the wrong build inputs

Inspect the selected client Dockerfile. Use a local source build or the intended
fork revision for a client change. Copy the intended fixtures and generated spec
into the simulator build context and enable the relevant overrides.
Record all input revisions. See [hive.md](hive.md).

## 4. speccheck passes without proving a constraint

Use a negative test in temporary files. For optionality, change the compiled
parameter back to `required: true` and confirm the omitted-parameter case fails.
Cases containing `invalid` skip parameter and result validation, so they cannot
prove parameter-schema enforcement. See [execution-apis.md](execution-apis.md).

## 5. `make fill` changes unrelated fixtures

A different reference client, chain, configuration, or generator can change
recorded output. Compare these inputs before attributing drift to client behavior.
Prefer a filtered fill. Remove only drift produced by this task and preserve
pre-existing changes. See [testgen.md](testgen.md).

## 6. A local dependency replace enters the diff

Remove only the temporary replace and dependency changes introduced for the local
build. Preserve any earlier replace, dependency edits, and intentional version
bump. Do not restore entire module files unless their pre-task state was clean.

## 7. The editor reports undefined testgen helpers

Helpers such as `Chain` and `TxInfo` live in sibling files. Run
`go build ./testgen/` from `$EXECapis/tools` to check the package.

## 8. Fixtures and chain data disagree

Keep fixtures, `chain.rlp`, `genesis.json`, `forkenv.json`, and `headfcu.json`
from the same generation. Check all inputs before combining copied fixtures.
See [hivechain.md](hivechain.md).

## 9. A spec change has no effect in Hive

Ordinary tests compare recorded responses, so they need updated fixtures when
expected output changes. Schema-based `speconly` tests need the updated compiled
spec in the image. Older Hive revisions use structural comparison instead.
Inspect `runTest` and the Dockerfile in the target revision.
See [hive.md](hive.md).

## 10a. Hive passes, but client tests fail

Hive does not replace the client's own tests. Build and test the affected modules,
including callers of changed signatures. Confirm the command actually executes:
a toolchain shim can print an error without a useful exit status.
Read the checkout's toolchain pins and inspect the test summary.

## 10b. A signature change breaks callers or misses overrides

Search the whole repository for the method before editing. Update interfaces,
implementations, callers, tests, and overrides as needed. Erigon's `rpc/contracts`
and `rpc/mcp` are examples of internal consumers. Nethermind client variants can
override `EthRpcModule` methods. Verify these paths in the target revision.

## 10c. Besu error text differs from the exception detail

Inspect the serialization path and `RpcErrorType`. The wire message can come
from the enum rather than the exception detail in the handler.
See [clients.md](clients.md).

## 10d. Besu fork selection or cache behavior is incorrect

Use the timestamp of the relevant block or execution context for fork selection.
Check time units; Java wall-clock milliseconds cannot replace epoch seconds.
For caches with variable-size values, determine whether an entry limit bounds
memory sufficiently. Reuse `MemoryBoundCache` when a byte limit is required.
Check current usage before adopting it. Keep unrelated cache changes outside the task.

## 11. A new method duplicates an existing implementation

Reuse existing helpers first. If two methods share substantial logic, consider
one private helper at that layer. Preserve public compatibility and avoid changing
unrelated signatures solely to reduce line count.
See [go-ethereum.md](go-ethereum.md).

## 12. A stale Hive checkout lacks required client configuration

Compare the checkout with `ethereum/hive`, even when `origin` points to a fork.
Check the specific namespace, fork, or gas-limit mapping needed by the test.
Inspect upstream changes before applying them; do not overwrite local wrapper
edits with a blanket checkout. See [hive.md](hive.md).

## 13. Historical client limitations resemble regressions

Past surveys report pre-Byzantium receipt encoding differences in Reth and
historical-state gaps in ethrex on the Hive chain. These are diagnostic leads,
not permanent exclusions. Confirm the client revision, imported head, fork
schedule, and raw response. Reproduce on the unchanged baseline before attributing
an unrelated failure. See [clients.md](clients.md) and [hivechain.md](hivechain.md).

## 14. Schema validation accepts output that exact comparison rejects

Objects permit extra properties unless the schema forbids them. Optional fields
can also differ while both responses remain schema-valid. Decide the intended
contract before changing either the schema or fixture comparison mode.
`additionalProperties: false` forbids extras; it does not make optional fields or
values deterministic. See [execution-apis.md](execution-apis.md).
