# execution-apis: the OpenRPC spec, specgen, and speccheck

execution-apis is the source of truth for the JSON-RPC *contract*. The repo has
two halves you care about:

- `src/` — the OpenRPC spec, authored as YAML.
- `tools/` — a Go module with `specgen`, `rpctestgen`, and `speccheck`.
- `tests/` — the committed `.io` fixtures (git-tracked), consumed by hive.

## The spec YAML

Methods live under `src/<namespace>/*.yaml` (e.g. `src/eth/state.yaml` holds the
state-reading methods). Shared schemas live under `src/schemas/*.yaml`. A method
parameter looks like:

```yaml
- name: eth_getBalance
  params:
    - name: Address
      required: true
      schema: { $ref: '#/components/schemas/address' }
    - name: Block
      required: true                       # <- making this optional is a spec change
      schema: { $ref: '#/components/schemas/BlockNumberOrTagOrHash' }
```

**Example — making a parameter optional** with a documented default (idiom
mirrors `eth_simulateV1`); this is the default-to-latest change:

```yaml
    - name: Block
      required: false
      description: "default: 'latest'"
      schema: { $ref: '#/components/schemas/BlockNumberOrTagOrHash' }
```

## Adding a new method (and its schemas)

A method is a full OpenRPC object under `src/<namespace>/<file>.yaml`:

```yaml
- name: eth_getThing
  summary: Returns the thing for an address.
  params:
    - name: Address
      required: true
      schema: { $ref: '#/components/schemas/address' }
    - name: Block
      required: false
      description: "default: 'latest'"
      schema: { $ref: '#/components/schemas/BlockNumberOrTagOrHash' }
  result:
    name: Thing
    schema: { $ref: '#/components/schemas/Thing' }
  examples:
    - name: eth_getThing example
      params: [ { name: Address, value: '0x...' } ]
      result: { name: Thing, value: '0x...' }
```

- **New types** become named components in `src/schemas/*.yaml` and are `$ref`'d.
  Reuse existing schemas (`address`, `uint`, `bytes`, `hash32`,
  `BlockNumberOrTagOrHash`, …) wherever possible — reviewers prefer reuse over a
  new bespoke type.
- **Wiring:** `specgen` assembles from the directories in the `Makefile`'s
  `SPECFLAGS` (`-methods 'src/eth'`, `-schemas 'src/schemas'`, …). A file added
  under an already-listed directory is picked up automatically; a brand-new
  directory must be added to `SPECFLAGS`. Run `make build` and confirm the method
  appears in `openrpc.json`.

## Result schemas & errors

- **Changing a result shape** is a spec change: edit the method's `result.schema`
  (or its referenced component). speccheck validates each fixture's `result`
  against this schema, so a too-loose schema lets wrong shapes through and a
  too-strict one rejects valid output.
- speccheck skips result validation for error responses, after validating parameters.
  A case name containing `invalid` skips both parameter and result validation.
  Use that convention for deliberately invalid requests, not every error case.
  Hive checks error codes and other retained fields, but redacts error messages
  when both responses contain errors. Add a client assertion when error text matters.
  Record standardized errors in the method's `errors` block or `src/error-groups/`.

## Open vs closed object schemas (`additionalProperties`)

JSON Schema objects are **open by default**: `required` enforces that fields are
*present*, but nothing forbids extra keys. "Exactly these fields" takes both
`required` and `additionalProperties: false`.

This matters because the conformance stack has two enforcement layers of
different strictness. Schema validation (speccheck, hive `speconly`) enforces
only what the schema says; ordinary hive tests replay geth-recorded fixtures
exact-match. With an open schema, a client emitting an extra field is
**spec-valid yet fails exact-match** — the spec and the tests disagree, and the
extra field is legislated by an accident of fixture generation instead of by the
contract.

- Set `additionalProperties: false` when the agreed contract forbids extra fields.
  Do not tighten the contract solely to match one client's fixtures.
  Closed schemas still allow differences in optional fields and values, so they
  do not make exact comparison equivalent to schema validation.
- **When open is right:** the object genuinely admits client- or
  config-specific members that can't be enumerated. Prefer naming them as
  optional properties if you can.
- **Cost to know:** a closed schema is fork-versioned — a client already
  emitting a next-fork field is schema-invalid against the older spec ref.
  Spec, fixtures, and the hive sim build from one ref, so CI stays consistent;
  standalone validators pinned to an old `openrpc.json` will reject newer
  clients.
- **Composition trap:** `additionalProperties: false` breaks `allOf`-style
  reuse (each subschema rejects the other's properties). Declare fields inline
  in a closed schema; don't compose it from parts.

Prove enforcement with a negative test: inject a bogus key into one fixture's
result → speccheck must fail on it; restore, all green. Without
`additionalProperties: false` that injected key passes silently.

## Regenerate the compiled spec

```sh
cd $EXECapis
make build
# runs specgen twice:
#   ./tools/specgen -o refs-openrpc.json ...        (with $ref links)
#   ./tools/specgen -o openrpc.json -deref ...       (dereferenced — speccheck uses this)
```

`openrpc.json` and `refs-openrpc.json` are **build artifacts and gitignored** —
regenerate them, don't hand-edit. `make build` also builds the `tools/` binaries
(`specgen`, `speccheck`, `rpctestgen`).

Verify your change landed:

```sh
jq -r '.methods[] | select(.name=="eth_getBalance").params[] | select(.name=="Block").required' openrpc.json
# -> false
```

## speccheck: validate fixtures against the spec

```sh
cd $EXECapis
./tools/speccheck -v                              # all fixtures
./tools/speccheck --regexp 'default-block'        # only matching tests
# flags: --spec openrpc.json  --tests tests  --regexp <re>
```

What speccheck actually checks (`tools/cmd/speccheck/check.go`):

These rules match
[execution-apis revision 6570b550](https://github.com/ethereum/execution-apis/blob/6570b550090c53cc44d7a498da8415dd72bc850d/tools/cmd/speccheck/check.go).
Recheck exclusions when the validator changes.

- The request's params count must be `<=` the method's declared params.
- For each declared param: if the fixture **omits** it, that's only OK when the
  param is `required: false`. Otherwise → `missing required parameter
  <method>.param[N]`.
- Each present param value validates against its schema.
- The result validates against the result schema, except for error responses.
- Names containing `invalid` skip both parameter and result validation after method lookup.

This is why a spec change to `required: false` is load-bearing: it's the only
thing that lets an omitted-param fixture pass speccheck.

## Prove the spec change matters (negative test)

Confirm enforcement so you know the test isn't vacuously green:

```sh
cd $EXECapis
negative_spec=$(mktemp)
jq '(.methods[] | select(.name=="eth_getBalance") | .params[] |
  select(.name=="Block") | .required) = true' openrpc.json > "$negative_spec"
./tools/speccheck --spec "$negative_spec" --regexp 'get-balance-default-block'
# Expect a nonzero exit and "missing required parameter eth_getBalance.param[1]".
rm "$negative_spec"
```

## What to commit in a spec PR

- The `src/**/*.yaml` change.
- The testgen change in `tools/testgen/generators.go` and the new `tests/**/*.io`
  fixtures.
- **Not** `openrpc.json` / `refs-openrpc.json` (artifacts), and **not** the
  `tools/go.mod` local `replace` (see `testgen.md`).
