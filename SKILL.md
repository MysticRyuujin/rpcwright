---
name: rpcwright
description: >-
  Implement, review, and conformance-test Ethereum execution-layer JSON-RPC
  changes across clients, execution-apis OpenRPC schemas, testgen/rpctestgen,
  speccheck, and Hive rpc-compat. Use for eth_*, debug_*, txpool_*, or testing_*
  API behavior, .io fixtures, named-tracer schemas, and test-chain fork changes.
  Excludes ordinary RPC consumption and consensus-layer Beacon APIs.
---

# rpcwright

Use this skill to change or validate Ethereum JSON-RPC behavior.
Read only the references needed for the requested task.

## Scope and source of truth

The execution-apis spec defines the contract. A fixture records one client's
behavior and can contain that client's bugs. Check disagreements against the
spec before changing a client to match a fixture.

If the spec is ambiguous, identify the unresolved behavior and prepare a proposal
for client-team review. Do not treat client agreement as an approved standard.

Match the work to the request. A review, documentation edit, or diagnosis does
not require changes across every client. For a behavior change, trace the affected
client, spec, generator, and harness stages. Change only the stages that need it.

Before using commands, locate the repositories and inspect their instructions,
Git status, revisions, Makefiles, and toolchain pins. Set these paths to the
actual checkouts:

```sh
export GETH=~/code/go-ethereum
export EXECapis=~/code/execution-apis
export HIVE=~/code/hive
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
| Investigate a specific failure | Search [gotchas.md](references/gotchas.md) for the symptom |
| Follow an example across repositories | [worked-example.md](references/worked-example.md) |

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
| Named tracer | Check branch selection in both validators; an unconstrained `anyOf` branch can bypass the intended schema. |

## Validation rules

- **Client tests:** A Hive run does not replace the client's tests. Build and test affected modules and signature callers.
- **RPC decoding:** Test the exact changed request. Passing an explicit block does not test an omitted block.
- **Schema enforcement:** For a changed constraint, use a temporary invalid spec or fixture and confirm rejection.
- **speccheck exclusions:** Names containing `invalid` skip parameter and result validation. Error responses otherwise skip result validation.
- **Fixture comparison:** Ordinary Hive tests compare recorded responses. Inspect error-message redaction before claiming error-text coverage.
- **Spec-only tests:** Verify the target Hive revision validates against OpenRPC. Older versions compare structure instead.
- **Build inputs:** Supply the local compiled spec as well as local fixtures when testing an unpublished schema change.
- **Test selection:** Use `--sim.limit 'rpc-compat/<test-regex>'`. Confirm the intended fixture cases run for every selected client.
- **Test counts:** `tests > 0` is insufficient because launch tests also count. Check fixture names, launch results, and failures.
- **Failure attribution:** Compare against the unchanged baseline with the same client builds and configuration before classifying a failure as unrelated.

## Completion evidence

Report the changed repositories, revisions or build inputs, checks performed,
and results. For runtime changes, include client build/test results and the
selected Hive fixture results per client. Identify any checks that remain unrun.

Before a PR, read each affected repository's current contribution rules and CI
configuration. Check the diff for unrelated fixture drift and local overrides.
If the spec depends on an unreleased client change, describe that dependency
instead of claiming the pinned-client CI passes.
