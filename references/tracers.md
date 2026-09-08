# Tracers — spec'ing debug_trace* named-tracer output

Use this reference to standardize a named tracer's output, with callTracer as
the example. Read [execution-apis.md](execution-apis.md) and [testgen.md](testgen.md).
Check branch-selection code in the target revisions before assuming it exists.

## The shape of a named-tracer spec

The trace methods use `anyOf` result branches. Validators must select the relevant
branch using the request's `TraceConfig.tracer` field:

```
anyOf:
  - title: Opcode tracer result   # tracer absent/empty
  - title: Call tracer result     # tracer == "callTracer"
  - title: Named tracer result    # any other tracer — unconstrained escape hatch
```

Spec'ing a new tracer = add a schema file in `src/schemas/`, add a titled
branch to each method's `anyOf` (block methods: under `items.anyOf`, using a
`<Tracer>BlockEntry` `{txHash, result?, error?}` wrapper), and teach
speccheck's branch selection about it (`tools/cmd/speccheck/tracer.go`
`tracerBranchTitles`). Keep the escape-hatch branch — other tracers must stay
valid.

## Gotcha: anyOf branches are NOT enforced by default

Validation against the whole result schema accepts arbitrary tracer output when
an unconstrained branch is present. Each validator must select the intended
branch using the request's tracer value to enforce its constraints.
Inspect `tools/cmd/speccheck/tracer.go` and Hive's `rpc-compat/schema.go` for
`tracerBranchTitles` and request-based selection. Some revisions lack the
speccheck selector; Hive revisions with `methodSchemas.forRequest` already select
known tracer branches. Add or extend selection where needed in each validator.
Prove enforcement by removing a required field from a nested frame in temporary
test data. Both validators must reject it when they claim tracer-schema coverage.

## Gotcha: recursive schemas vs specgen

specgen fully inlines `#/components/schemas/` refs and hard-errors on cycles
(`dereference.go: "cycle detected"`), and `mergeallof.go` panics on residual
refs — a naive `CallFrame.calls.items.$ref → CallFrame` breaks `make build`.

The pattern that works: give the schema an absolute-URI `$id` and self-`$ref`
that URI:

```yaml
CallFrame:
  $id: 'https://ethereum.github.io/execution-apis/schemas/calltracer/callframe'
  properties:
    calls:
      items:
        $ref: 'https://ethereum.github.io/execution-apis/schemas/calltracer/callframe'
```

specgen passes absolute-URI (non-`#`) refs through verbatim; JSON Schema
2019-09 `$id` semantics make the self-ref resolve wherever the schema is
embedded, at any depth, in santhosh-tekuri/jsonschema v5/v6 (speccheck, hive,
specgen metaschema). Fragment refs that aren't `#/components/schemas/` still
error, so typos fail the build. Constraint: one `$id` may appear only once per
compiled method document.

## Gotcha: the generated openrpc types don't round-trip

`open-rpc/spec-types` union types (e.g. `Type`) have marshal/unmarshal that
are not inverses: re-marshaling an already-normalized `"type": ["object"]`
produces `[["object"]]` — invalid schema JSON. Never round-trip a schema
through `openrpc.JSONSchemaObject` twice; work on raw `map[string]any` after
the first marshal (this is why speccheck's `validateRaw` exists).

## callTracer reference facts (verified July 2026, raw over SSH)

The following observations describe that survey, not all future releases.
Reproduce relevant differences on the target revisions before treating them as
current behavior. The approved spec takes precedence over the reference client.

geth `eth/tracers/native/call.go` is the de-facto reference. Wire format:
`type/from/gas/gasUsed/input` always present (`input` = `"0x"` when empty);
`to/value/output/error/revertReason/calls/logs` omitted-when-empty (never
null). Root frame: `gas` = tx gas limit, `gasUsed` = receipt gasUsed.
Reverts: `error:"execution reverted"` + raw `output` + `revertReason` when
`Error(string)` decodes. Failed CREATE omits `to`; STATICCALL omits `value`
but **DELEGATECALL carries the parent context value**; precompile calls are
frames; failed frames' logs are cleared recursively. Block methods wrap as
`{txHash, result?, error?}`.

Cross-client divergences (July 2026 releases; full report:
MysticRyuujin/ethereum-trace-compare `investigations/2026-07-calltracer/`):

- **besu 26.6.1**: ignores `onlyTopCall`/`withLog`, no `logs` field, chained
  DELEGATECALL `from` uses code addr not context addr, root `gasUsed`
  excludes intrinsic gas, different inner-frame `gas`, rebuilds the tree from
  opcode frames (`CallTracerResultConverter`).
- **nethermind 1.39**: drops a CALL frame following a STATICCALL to the same
  target; `output` missing on some frames; callLog lacks `index`.
- **geth/erigon/reth**: agree on everything except callLog `index`/`position`
  — geth block-global, erigon/reth tx-local, and all three shift under
  `onlyTopCall`. Un-spec-able as-is; the spec leaves `index` optional and
  semantically undefined.
- **reth (revm-inspectors)**: keeps logs on reverted frames.
- **erigon**: extra `includePrecompiles` config (default true); validates fee
  cap vs base fee in `debug_traceCall` where others don't.
- **ethrex ≤ v20**: no `debug_trace*` at all in releases (main has
  callTracer/prestateTracer/opcode; defaults to callTracer when tracer is
  absent — non-geth; no debug_traceCall/traceBlockByHash).

Tracer impl locations per client: geth `eth/tracers/native/call.go`; erigon
`execution/tracing/tracers/native/call.go` (geth fork); nethermind
`src/Nethermind/Nethermind.Blockchain/Tracing/GethStyle/Custom/Native/Call/`;
besu `ethereum/api/.../results/CallTracerResult.java` + `.../calltrace/`;
reth: external `revm-inspectors` + `alloy-rpc-types-trace` crates (not in
repo); ethrex `crates/vm/backends/levm/tracing.rs` + `crates/common/tracing.rs`.

## Comparing tracer output across clients

If available, use MysticRyuujin/ethereum-trace-compare: `compare_traces.py
--tracer calltracer --methods tx,block,call-replay --configs
default,onlyTopCall,withLog,onlyTopCallWithLog`, then
`aggregate_calltracer.py <traces-dir>` for the divergence matrix.
Check those scripts and their flags in the selected checkout. If unavailable,
send the same requests directly to each node and save the raw responses with
client versions and configuration. The helper repository is optional.

**Never compare through a caching/normalizing proxy (eRPC).** eRPC caches
`debug_trace*` responses in a memory cache shared across upstreams — the
client-specific subdomains all got one upstream's cached bytes, which faked
perfect cross-client agreement — and it re-serializes JSON, destroying
wire-format evidence (omitted-vs-null, key order). Go direct: SSH to each
node, `ssh -f -N -L <port>:localhost:8545 <node>`, and point the tool at the
forwards. Byte-identical responses across clients are a red flag, not a
result.

For chain-controlled scenarios, the test chain has a `calltree` predeploy
(`0x9dcd…27d0`, callees at …d1/d2/d3) whose single invocation produces every
frame type — `tx-calltree`/`tx-callrevert` entries in `txinfo.json` locate the
on-chain invocations, and `debug_traceCall` to the predeploy reproduces the
tree without a tx.
