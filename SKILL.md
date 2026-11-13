---
name: rpcwright
description: >-
  Implement, review, survey, and conformance-test Ethereum execution-layer
  JSON-RPC behavior across clients (go-ethereum, Nethermind, Erigon, Besu, Reth,
  ethrex, Nimbus), the execution-apis OpenRPC spec, testgen/rpctestgen,
  speccheck, and Hive rpc-compat. Load this before any of: a Hive rpc-compat run
  or failure triage; adding, regenerating, or reviewing .io fixtures; an
  execution-apis spec PR or issue about eth_*, debug_*, trace_*, txpool_*, or
  testing_* behavior; a cross-client behavior survey or divergence; a client PR,
  or review feedback on one, that changes RPC behavior; a geth pin bump in
  tools/go.mod; named-tracer schemas; test-chain (hivechain) fork changes.
  Excludes ordinary RPC consumption and consensus-layer Beacon APIs.
---

# rpcwright

Use this skill to change or validate Ethereum JSON-RPC behavior.
Read only the references needed for the requested task.
When you delegate part of this work to another agent, tell it to load this skill.

## Scope and source of truth

The execution-apis spec defines the contract. A fixture records one client's
behavior and can contain that client's bugs. Check disagreements against the
spec before changing a client to match a fixture.

When the spec has a gap or clients disagree, derive one recommended rule. Use
this evidence in order: the execution specs and EIPs, earlier merged spec and
client decisions on the same behavior, then the current behavior of each client.
Present the rule as a proposal with its evidence. Do not list options without a
recommendation. Client agreement supports a proposal. It is not an approved
standard until client teams review it.

- For behavior that affects interoperability, do not propose "undefined" or
  "client-specific". The exception is a value that the spec leaves to the
  client; see "Test strength" below.
- Search the spec and client repositories for an existing issue or PR before
  you file one.
- Before you call a divergence a consensus bug, show that a valid chain can
  reach the state. A state override can create a state that no chain can hold.
- A client divergence belongs to the client or to the dependency that owns the
  behavior. Do not change the harness to hide it.

Match the work to the request. A review, documentation edit, or diagnosis does
not require changes across every client. For a behavior change, trace the affected
client, spec, generator, and harness stages. Change only the stages that need it.

Before using commands, locate the repositories and inspect their instructions,
Git status, revisions, Makefiles, and toolchain pins. Set these paths to the
actual checkouts:

```sh
export GETH=/path/to/go-ethereum
export EXECapis=/path/to/execution-apis
export HIVE=/path/to/hive
```

Reference paths and historical failures are starting points. Confirm them in the
target revision. Preserve existing edits when removing generated drift or local
build overrides. Use an isolated checkout when cleanup would otherwise be ambiguous.

## Choose the relevant references

| Task | Read |
| --- | --- |
| Change a client handler, signature, registration, or tests | [clients.md](references/clients.md); for geth, [go-ethereum.md](references/go-ethereum.md) |
| Change a method, parameter, result schema, or error contract | [execution-apis.md](references/execution-apis.md) |
| Add or regenerate `.io` fixtures | [testgen.md](references/testgen.md) |
| Run fixtures across clients or diagnose Hive failures | [hive.md](references/hive.md) |
| Change the chain or test behavior before a fork | [hivechain.md](references/hivechain.md) |
| Standardize named-tracer output | [tracers.md](references/tracers.md), then the spec and fixture references |
| Align or spec Parity-style `trace_*` methods | [trace-namespace.md](references/trace-namespace.md) |
| Investigate a specific failure | Search [gotchas.md](references/gotchas.md) for the symptom |
| Survey raw client behavior | [hive.md](references/hive.md#survey-raw-client-behavior-no-expected-value-needed) |
| Run local or unmerged fixtures | [hive.md](references/hive.md#run-against-local-or-unmerged-fixtures) |
| Attribute failures after a chain or pin change | [hivechain.md](references/hivechain.md), the A/B baseline item |

## Behavior-change workflow

1. Compare the requested behavior with the spec and the current client behavior.
2. Trace the handler, registration, callers, overrides, and relevant client variants.
3. Implement the change using the client's existing parameter and error conventions.
4. Add a regression test through RPC when dispatch or parameter decoding changes.
5. Update the OpenRPC YAML and run `make build` from `$EXECapis`.
6. Add generator cases for the changed path and relevant boundaries.
7. Generate fixtures with the intended reference client, then inspect the recorded responses.
8. Run speccheck and the affected client's builds and tests.
9. Replay the affected fixtures through Hive using the intended client build, fixtures, chain, and spec.

For another client's implementation, reuse conformant fixtures when the contract
stays the same. A local geth `go.mod` replace selects the reference build for
`make fill`; it does not belong in the committed dependency configuration.

## Other workflows

**Multi-client survey.** Use it to find what clients do before you propose a rule.

1. Trace the handler in each client's source. Record each revision.
2. Probe the running clients with placeholder fixtures (see the route table).
3. Make a table: one row per client, with the result or the error code and data.
4. Search for earlier decisions: merged PRs, issues, and EIPs.
5. Derive the rule and open the spec issue or PR. For each client that differs,
   file an issue that links it. Open a client PR when the spec already defines
   the behavior, or after the proposal has agreement.

**Stacked change set.** Use it when a spec change needs new reference-client behavior.

1. Open the client PR with its tests.
2. Open the spec PR with fixtures from a local `replace` build. The fill check
   in CI fails until the pinned client has the change.
3. After the client PR merges, bump the pin in `tools/go.mod` and fill again.
   If the bump changes other fixtures, put the bump and that drift in one PR
   and merge it first. Then rebase the spec PR and fill again.
4. Open PRs for the other clients against the same fixtures.

**Full matrix with a baseline.** Use it to attribute failures to a change.

1. Run the selected client images against the unchanged fixtures. Record failures.
2. Run the same images against the changed fixtures.
3. Confirm that each client launched and ran the same number of tests in both
   runs.
4. Report, per client, the failures that the second run adds and removes.

**Pre-merge batch check.** Use it before several spec PRs merge together.

1. Merge the PRs into one checkout of the main branch, in the intended order.
2. Run `make build` and `make fill`. `tests/` must show no difference, apart
   from files that the repository's CI check excludes.
3. Run speccheck, then a Hive run of the merged fixtures with the merged
   compiled spec.

## What each change needs

| Change | Required considerations |
| --- | --- |
| New method | Register the handler and spec method; register generator cases in `AllMethods`. |
| Optional parameter | Match the client's optionality convention; set `required: false`; test omission and an explicit value. Treat `null` separately. |
| Result change | Update the schema and affected fixtures; decide whether extra fields are permitted by the contract. |
| Error change | Test the error code and success/error distinction. Check which fields each validator actually compares. |
| Deprecation | Mark the method deprecated and document its replacement. Preserve support and tests unless removal is requested. |
| Removal | Remove the handler, registration, spec entry, and affected cases when removal is in scope. |
| Chain fork | Generate the chain through hivechain; verify genesis, fork environment variables, and client mappings agree. |
| Named tracer | Give each tracer fixture a validation script that validates the tracer's own schema. The method's `anyOf` has a branch that accepts any value. |

## Validation rules

- **Client tests:** A Hive run does not replace the client's tests. Build and test affected modules and signature callers.
- **RPC decoding:** Test the exact changed request. Passing an explicit block does not test an omitted block.
- **Schema enforcement:** For a changed constraint, use a temporary invalid spec or fixture and confirm rejection.
- **speccheck exclusions:** Names containing `invalid` skip parameter validation. Error responses get an error-code check instead of result validation.
- **Fixture comparison:** Ordinary Hive tests compare recorded responses. For an error, `code` and `data` must match exactly; only `message` is removed before the comparison.
- **Imported head:** Compare each client's `eth_blockNumber` with the chain head before you interpret its failures. A client that did not import the chain fails most fixtures for one cause.
- **Test strength:** Prefer an exact fixture. Use `speconly` only for values the spec leaves to the client. Then add a script that compares the rest of the response with the recorded one. A schema-only check is the last choice. When a client differs on a defined value, fix the client; do not loosen the test.
- **Validation scripts:** speccheck runs a script with the recorded response as both `expected` and `response`. Test a comparison script with a changed response, not a changed fixture.
- **Spec-only tests:** Confirm which response the target Hive revision gives to schema validation. It must be the client response, not the recorded one.
- **Build inputs:** Run local fixtures from a clean copy of the simulator with the matching compiled spec. A leftover `tests/` directory or an edited shared Dockerfile changes later runs without a visible sign.
- **Client images:** Record the image tag or source revision of each client with every result. An old image can show a divergence that the client already fixed.
- **Test selection:** Use `--sim.limit 'rpc-compat/<test-regex>'`. Confirm the intended fixture cases run for every selected client.
- **Test counts:** `tests > 0` is insufficient because launch tests also count. Check fixture names, launch results, and failures.
- **Failure attribution:** Use the baseline workflow above before you classify a failure as unrelated. A failure outside the edited code is not proof.

## Completion evidence

Report the changed repositories, revisions or build inputs, checks performed,
and results. For runtime changes, include client build/test results and the
selected Hive fixture results per client. Identify any checks that remain unrun.
Until the spec decides the behavior, write "differs from the recorded fixture",
not "the client is wrong".

Before a PR, read each affected repository's current contribution rules and CI
configuration. Check the diff for unrelated fixture drift and local overrides.
If the spec depends on an unreleased client change, describe that dependency
instead of claiming the pinned-client CI passes.
