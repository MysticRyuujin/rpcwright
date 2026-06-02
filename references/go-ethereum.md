# go-ethereum: building, testing, and RPC method patterns

go-ethereum (geth) is the primary client here because it is also where the
testgen framework runs its reference client. Get fluent in it first.

## Build

```sh
cd $GETH
make geth                 # -> build/bin/geth   (preferred; embeds version info)
# or, for a quick package build:
go build ./cmd/geth
```

Build just the package you changed to catch compile errors fast:

```sh
go build ./internal/ethapi/...
go vet ./internal/ethapi/
gofmt -l internal/ethapi/api.go     # lists files needing formatting; -w to fix
```

## Test

```sh
go test ./internal/ethapi/                          # whole package
go test ./internal/ethapi/ -run TestSomeName -v     # one test
```

## Where RPC methods live

Public JSON-RPC methods are Go methods on API structs, mostly in
`internal/ethapi/api.go`. They are registered by namespace and auto-exposed: a
method `GetBalance` on the `eth` service becomes `eth_getBalance`. The backend
abstraction is `internal/ethapi/backend.go`; the concrete backend is
`eth/api_backend.go`.

Method signature shape:

```go
func (api *BlockChainAPI) GetBalance(
    ctx context.Context,
    address common.Address,
    blockNrOrHash rpc.BlockNumberOrHash,   // <- positional JSON-RPC params
) (*hexutil.Big, error)
```

Return values use `hexutil` wrappers (`*hexutil.Big`, `hexutil.Bytes`,
`*hexutil.Uint64`) so they JSON-encode as the `0x…` quantities the spec wants.

## THE key gotcha: optional trailing parameters must be pointers

geth's `rpc` package decides whether a caller may omit a trailing positional
argument by looking at the Go type. See `rpc/json.go`,
`parsePositionalArguments`:

```go
// any missing trailing args:
for i := len(args); i < len(types); i++ {
    if types[i].Kind() != reflect.Ptr {
        return nil, fmt.Errorf("missing value for required argument %d", i)
    }
    args = append(args, reflect.Zero(types[i]))   // nil pointer
}
```

Consequences:

- A **value-type** trailing param (e.g. `blockNrOrHash rpc.BlockNumberOrHash`)
  is **mandatory**. Omitting it yields `-32602 missing value for required
  argument N`.
- A **pointer** trailing param (`*rpc.BlockNumberOrHash`) may be omitted; the
  handler receives `nil`. An explicit JSON `null` also decodes to `nil`.

So to make a parameter optional (e.g. "default the block to latest when
omitted"), change the signature to a pointer and default `nil`:

```go
// helper used by all the state methods
func blockNrOrHashOrLatest(blockNrOrHash *rpc.BlockNumberOrHash) rpc.BlockNumberOrHash {
    if blockNrOrHash != nil {
        return *blockNrOrHash
    }
    return rpc.BlockNumberOrHashWithNumber(rpc.LatestBlockNumber)
}

func (api *BlockChainAPI) GetBalance(ctx context.Context, address common.Address,
    blockNrOrHash *rpc.BlockNumberOrHash) (*hexutil.Big, error) {
    state, _, err := api.b.StateAndHeaderByNumberOrHash(ctx, blockNrOrHashOrLatest(blockNrOrHash))
    ...
}
```

`eth_call` already uses exactly this pattern (`*rpc.BlockNumberOrHash`,
defaulting to `LatestBlockNumber`) — copy it.

When you flip a signature from value to pointer, fix any in-repo callers and the
backend mock in tests (e.g. `internal/ethapi/api_test.go`) — they'll fail to
compile with `cannot use X (value of type ...) as *... value`.

## Test a parameter change through the REAL RPC server

Calling the Go method directly does **not** prove the JSON-RPC layer accepts an
omitted parameter — that behavior lives in the `rpc` package, not your handler.
Stand up an in-process server and call over it:

```go
func TestStateMethodsDefaultToLatest(t *testing.T) {
    backend := newTestBackend(t, 1, genesis, beacon.New(ethash.NewFaker()),
        func(i int, b *core.BlockGen) { b.SetPoS() })

    srv := rpc.NewServer()
    srv.RegisterName("eth", NewBlockChainAPI(backend))
    srv.RegisterName("eth", NewTransactionAPI(backend, new(AddrLocker)))
    client := rpc.DialInProc(srv)
    defer client.Close()

    // Omit the block param entirely (only 1 positional arg):
    var got hexutil.Big
    if err := client.CallContext(ctx, &got, "eth_getBalance", addr); err != nil {
        t.Fatalf("omitted block: %v", err)
    }
    // Compare to the explicit "latest" result — they must be identical.
    var want hexutil.Big
    client.CallContext(ctx, &want, "eth_getBalance", addr, "latest")
    // assert got == want
}
```

`rpc.DialInProc(srv)` + `client.CallContext(ctx, dst, method, args...)` with
fewer args is how you exercise omission. This is the highest-value test for any
optional-parameter change.

## Genesis/state for tests

`newTestBackend(t, nBlocks, genesis, engine, genFn)` builds a chain. Seed
accounts with balance/code/nonce/storage via `core.Genesis{Alloc: types.GenesisAlloc{
addr: {Balance: ..., Code: ..., Nonce: ..., Storage: map[common.Hash]common.Hash{...}}}}`.
Use `params.MergedTestChainConfig` for a post-merge chain.
