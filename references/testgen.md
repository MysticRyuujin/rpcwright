# testgen / rpctestgen: generating and validating .io fixtures

testgen is the bridge between a running client and the committed test corpus. It
lives at `execution-apis/tools/testgen` (Go). The `rpctestgen` binary runs the
test cases against a real client and records `.io` fixtures into
`execution-apis/tests/`.

> Historical note: there was a standalone `lightclient/rpctestgen` repo. It is
> superseded — the copy inside `execution-apis/tools` is the one wired to the
> committed `tests/` corpus and to hive. Use only that one.

## Layout

```
execution-apis/tools/
  go.mod                 # Go module; depends on go-ethereum (the reference client)
  Makefile               # build / fill / test targets
  cmd/rpctestgen/        # the generator binary
  cmd/speccheck/         # the validator binary
  cmd/specgen/           # the spec compiler
  testgen/
    generators.go        # ALL test cases live here (MethodTests / Test structs)
    chain.go, utils.go   # chain helpers used by the cases
  chain/                 # the FIXED chain the fixtures are generated against
    chain.rlp genesis.json accounts.json forkenv.json headfcu.json txinfo.json
```

## The Makefile targets

```sh
cd $EXECapis/tools
make build     # build rpctestgen, speccheck, specgen
make geth      # go build -o geth github.com/ethereum/go-ethereum/cmd/geth  (uses go.mod)
make fill      # = build geth, then: ./rpctestgen --bin ./geth -chain ./chain --out ../tests
```

`make fill` is the canonical way to (re)generate fixtures. It builds the geth
binary from whatever the module resolves, starts it on the fixed chain, runs
every test case, and writes `../tests/<method>/<case>.io`.

`rpctestgen` flags: `--bin <client>` `--chain <dir>` `--out <dir>`
`--tests <regex>` (generate only matching cases) `--client <type>`.

## Generate fixtures with YOUR modified client

`make fill` builds geth from the module's pinned version, which does **not**
contain your change. Point it at your local checkout with a `replace`:

```sh
cd $EXECapis/tools
go mod edit -replace github.com/ethereum/go-ethereum=$GETH
go mod tidy
make fill              # now builds YOUR geth and records its responses
```

- This `replace` uses an absolute local path — it is a **local dev artifact**.
  Do **not** commit it to the spec PR. (When the client change is merged, the
  proper change is a version bump of the go-ethereum dependency, not a replace.)
- If your local client is newer than the pinned one, `make fill` will also
  rewrite **unrelated** fixtures whose output drifted (classic example:
  `eth_simulateV1` error codes like `-32602` → `-38012`). Keep the diff focused:

  ```sh
  cd $EXECapis
  git status --short tests/                 # see what changed
  git checkout -- tests/eth_simulateV1/     # revert unrelated drift
  # keep only the new fixtures your change introduced
  ```

- To regenerate just your method and avoid touching others, filter:
  `./tools/rpctestgen --bin ./tools/geth -chain ./tools/chain --out ./tests --tests 'eth_getStorageValues'`

## Determinism

Fixtures are generated against the **fixed** chain in `tools/chain`. A clean
`make fill` reproduces existing fixtures **byte-for-byte** when client behavior
is unchanged. Therefore: any modified `.io` file represents a real behavior
difference. Use this — regenerate, then `git status` to see exactly what your
change altered.

## Adding a test case

Cases are Go in `tools/testgen/generators.go`. Each method has a `MethodTests`
var (e.g. `EthGetBalance`) holding a slice of `Test{Name, About, Run}`. The
`Run` func gets a `*T` with `t.rpc` (raw `*rpc.Client`), `t.eth`
(`*ethclient.Client`), `t.geth` (`*gethclient.Client`), and `t.chain`.

To test an **omitted** parameter, call the raw client with fewer args (the typed
clients always send the block, so use `t.rpc.CallContext`):

```go
{
    Name:  "get-balance-default-block",
    About: "retrieves an account balance with the block parameter omitted, which defaults to latest",
    Run: func(ctx context.Context, t *T) error {
        var got hexutil.Big
        if err := t.rpc.CallContext(ctx, &got, "eth_getBalance", emitContract); err != nil {
            return err   // note: NO block arg
        }
        want := t.chain.Balance(emitContract)
        if got.ToInt().Cmp(want) != 0 {
            return fmt.Errorf("unexpected balance (got %d want %d)", got.ToInt(), want)
        }
        return nil
    },
},
```

Build-check the package after editing (note: single-file LSP analysis may report
false "undefined: Chain/TxInfo" errors because helpers live in sibling files —
trust `go build`):

```sh
cd $EXECapis/tools && go build ./testgen/ && gofmt -w testgen/generators.go && go vet ./testgen/
```

## The .io fixture format

```
// free-text comment becomes the hive test description
// speconly:   <- optional marker: hive checks response STRUCTURE only, not exact value
>> {"jsonrpc":"2.0","id":1,"method":"eth_getBalance","params":["0x7dcd...df"]}
<< {"jsonrpc":"2.0","id":1,"result":"0x56"}
```

`>>` is a request, `<<` the recorded response. An omitted-param fixture simply
has fewer entries in `params`. hive replays these verbatim.
