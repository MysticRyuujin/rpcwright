# Worked example: "default an omitted block param to latest"

A complete, real change across all four repos. The task: make the `Block`
parameter optional (defaulting to `latest`) on the six state-reading methods
`eth_getBalance`, `eth_getCode`, `eth_getStorageAt`, `eth_getTransactionCount`,
`eth_getProof`, `eth_getStorageValues` — matching an execution-apis spec change
and `eth_call`'s existing behavior.

Use this as a template; substitute your own method/behavior.

## 1. Client behavior (go-ethereum)

In `internal/ethapi/api.go`, add a helper and change each method's block param
from value to pointer:

```go
func blockNrOrHashOrLatest(b *rpc.BlockNumberOrHash) rpc.BlockNumberOrHash {
    if b != nil { return *b }
    return rpc.BlockNumberOrHashWithNumber(rpc.LatestBlockNumber)
}

func (api *BlockChainAPI) GetBalance(ctx context.Context, address common.Address,
    blockNrOrHash *rpc.BlockNumberOrHash) (*hexutil.Big, error) {
    state, _, err := api.b.StateAndHeaderByNumberOrHash(ctx, blockNrOrHashOrLatest(blockNrOrHash))
    ...
}
```

Fix the test backend mock and any callers that passed the value type. Add an
in-process RPC test that omits the block and asserts it equals `"latest"` (see
`go-ethereum.md`). Then:

```sh
cd $GETH && gofmt -w internal/ethapi/api.go internal/ethapi/api_test.go
go vet ./internal/ethapi/ && go test ./internal/ethapi/ -run TestStateMethodsDefaultToLatest
```

## 2. Spec (execution-apis)

Edit `src/eth/state.yaml`: for each method's `Block` param, `required: true` →
`required: false` + `description: "default: 'latest'"`. Regenerate:

```sh
cd $EXECapis && make build
jq -r '.methods[]|select(.name=="eth_getBalance").params[]|select(.name=="Block").required' openrpc.json   # false
```

## 3. testgen cases (execution-apis)

In `tools/testgen/generators.go`, add a `*-default-block` case to each method's
`MethodTests`, calling `t.rpc.CallContext` with the block arg omitted (see
`testgen.md`). `go build ./testgen/` to check.

## 4. Generate fixtures with the modified client

```sh
cd $EXECapis/tools
go mod edit -replace github.com/ethereum/go-ethereum=$GETH
go mod tidy
make fill
cd $EXECapis
git status --short tests/                 # expect: new *-default-block.io files
git checkout -- tests/eth_simulateV1/     # revert unrelated drift from a newer geth
```

## 5. Validate against the spec

```sh
cd $EXECapis && ./tools/speccheck -v          # all passing
# negative test (prove the required:false is load-bearing):
# temporarily set Block required:true in openrpc.json, run speccheck --regexp,
# confirm "missing required parameter", restore. (See execution-apis.md.)
```

## 6. hive rpc-compat

```sh
# fixtures -> simulator (and uncomment `ADD tests /execution-apis/tests` in its Dockerfile)
rsync -a $EXECapis/tests/ $HIVE/simulators/ethereum/rpc-compat/tests/
# client source -> local build location
rsync -a --delete --exclude='.git/' --exclude='build/bin/' $GETH/ $HIVE/clients/go-ethereum/go-ethereum/
```

```yaml
# $HIVE/clients.yaml
- client: go-ethereum
  dockerfile: local
  nametag: mychange
- client: nethermind
  nametag: master
  build_args: { tag: master }
```

```sh
cd $HIVE
./hive --sim ethereum/rpc-compat --client-file clients.yaml --sim.limit "rpc-compat/default-block"
# headline: simulation ethereum/rpc-compat finished suites=1 tests=N failed=0
```

Note the `--sim.limit` form (`rpc-compat/...`, not bare) — see `gotchas.md` #2.

## 7. Cross-client reality

In this exact change, geth passed all six. **Nethermind passed five but failed
`eth_getStorageValues/get-storage-values-default-block`** with
`-32602 missing value for required argument 1`. Cause: that one method declared a
**non-nullable** `BlockParameter` while its five siblings used
`BlockParameter? ... = null`. Two-line fix in Nethermind's `IEthRpcModule.cs` +
`EthRpcModule.cs` (see `clients.md`); rebuilt Nethermind locally
(`dockerfile: local`); the combined run then reported `tests=14 failed=0`. The
client fix was reported upstream.

Lesson: a single failing fixture in an otherwise-passing family almost always
means one method's signature diverges from its siblings.

## What gets committed where

- **client repo** (e.g. go-ethereum): the handler change + unit test, on a branch.
- **execution-apis**: `src/**/*.yaml`, `tools/testgen/generators.go`, and the new
  `tests/**/*.io` — NOT `openrpc.json`/`refs-openrpc.json` (artifacts), NOT the
  `tools/go.mod` local `replace`.
- **hive**: usually nothing permanent — the local tests/clients copies are
  scaffolding for the run. If you fixed another client, that fix belongs in an
  upstream PR to that client, not in hive.
