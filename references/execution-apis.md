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

To mark a parameter optional with a documented default (idiom mirrors
`eth_simulateV1`):

```yaml
    - name: Block
      required: false
      description: "default: 'latest'"
      schema: { $ref: '#/components/schemas/BlockNumberOrTagOrHash' }
```

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

- The request's params count must be `<=` the method's declared params.
- For each declared param: if the fixture **omits** it, that's only OK when the
  param is `required: false`. Otherwise → `missing required parameter
  <method>.param[N]`.
- Each present param value validates against its schema.
- The result validates against the result schema (errors are skipped; tests with
  `invalid` in the name skip schema validation).

This is why a spec change to `required: false` is load-bearing: it's the only
thing that lets an omitted-param fixture pass speccheck.

## Prove the spec change matters (negative test)

Confirm enforcement so you know the test isn't vacuously green:

```sh
cd $EXECapis
cp openrpc.json /tmp/openrpc.bak
# temporarily flip the param back to required in the COMPILED spec:
node -e 'const fs=require("fs");const d=JSON.parse(fs.readFileSync("openrpc.json"));
for(const m of d.methods) if(m.name==="eth_getBalance")
  for(const p of m.params) if(p.name==="Block") p.required=true;
fs.writeFileSync("openrpc.json",JSON.stringify(d,null,2));'
./tools/speccheck --regexp 'get-balance-default-block'
#   -> missing required parameter eth_getBalance.param[1]   (expected failure)
cp /tmp/openrpc.bak openrpc.json   # restore
```

## What to commit in a spec PR

- The `src/**/*.yaml` change.
- The testgen change in `tools/testgen/generators.go` and the new `tests/**/*.io`
  fixtures.
- **Not** `openrpc.json` / `refs-openrpc.json` (artifacts), and **not** the
  `tools/go.mod` local `replace` (see `testgen.md`).
