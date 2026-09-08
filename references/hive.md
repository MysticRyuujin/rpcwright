# hive: the rpc-compat cross-client conformance harness

hive builds Docker images for clients and simulators and runs them together. The
`rpc-compat` simulator replays execution-apis `.io` fixtures against a client and
compares responses. Requires Docker.

The schema and local-spec guidance below matches
[Hive revision 43ea47be](https://github.com/ethereum/hive/tree/43ea47bef5761351e3da7b726050ea80ab362c52/simulators/ethereum/rpc-compat).
Check the selected revision before relying on these features.

## Build hive

```sh
cd $HIVE
go build .            # produces ./hive
```

## Use a CURRENT upstream hive — a stale fork wastes hours

Client wrappers and the simulator evolve; a stale `$HIVE` lacks recent wiring (RPC
namespaces, env plumbing) and fakes "bugs." **If `origin` is your fork,
`git rev-list HEAD..origin/master` says `0` while you're months behind upstream** —
compare against `ethereum/hive`:

```sh
git remote add upstream https://github.com/ethereum/hive.git 2>/dev/null
git fetch upstream master && git rev-list --count HEAD..upstream/master   # >0 → behind
git grep <token> upstream/master -- clients/      # is a merged-PR feature actually present?
```

Inspect the required changes before applying them. Preserve local wrapper edits.

## How rpc-compat sources tests and clients

`simulators/ethereum/rpc-compat/`:

- `Dockerfile` clones execution-apis at a git ref (`ARG branch=main`,
  `ENV GIT_REF`), copies its `tests/` into the image, and **builds `openrpc.json`
  from the cloned `src/` with specgen** so `speconly` tests can be validated
  against the spec — see below.
- `main.go` + `testload.go` load every `.io` file under `tests/` and replay it.
- **For an ordinary test it does NOT consult the OpenRPC spec.** It compares the
  client response to the recorded `<<` response with `jsondiff` (exact match).
  Error messages are redacted from the comparison **only** when both expected and
  actual are errors.
- **For a `speconly:` test it validates the result against the method's OpenRPC
  result schema** (the same `santhosh-tekuri/jsonschema` validation speccheck
  does), not against the recorded `<<` value. So any spec-valid response passes,
  regardless of which *optional* fields a given client/config includes. The
  recorded `<<` value is then just one illustrative example. There is **no
  structural fallback** — a `speconly` method missing from the spec fails the test
  loudly, and the sim **panics at startup** if `openrpc.json` can't be loaded.
- The sim **builds `openrpc.json` from the cloned spec source** (specgen) at image
  build time — `openrpc.json` is gitignored in execution-apis, so it is *not* in
  the clone. Generate it or provide a local compiled override. The Dockerfile runs specgen (which pulls
  zero go-ethereum packages, so it's cheap) with the same flags as execution-apis'
  `make build`.

> Historical note / gotcha: `speconly` used to be a *structural* diff against the
> recorded `<<` example — it rejected both **missing** keys and **unexpected**
> keys. That is too strict for any method whose response shape is client- or
> config-dependent (e.g. `eth_capabilities`, whose `oldestBlock`/`deleteStrategy`
> fields appear or not depending on gcmode/state-scheme/retention). The fix made
> `speconly` mean "valid per the OpenRPC schema" (hive #1531). If you hit a
> `speconly` failure like `unexpected key in response` / `missing key`, you are on
> an old hive that still does the structural diff — update it.

So: an ordinary test is changed via the `.io` fixtures (and the client); a
`speconly` test is governed by the **OpenRPC schema** in `src/` — fix the spec,
and the sim regenerates `openrpc.json` from source on its next image build.

## Run against LOCAL fixtures (your modified tests)

By default the Dockerfile pulls execution-apis from GitHub at `GIT_REF`. To use
your local fixtures, the Dockerfile has a documented override — copy your tests
into the simulator dir and uncomment the `ADD` line:

```dockerfile
# in simulators/ethereum/rpc-compat/Dockerfile:
# ADD tests /execution-apis/tests          # <- uncomment this
```

```sh
# put your fixtures where the Dockerfile will ADD them:
rsync -a $EXECapis/tests/ $HIVE/simulators/ethereum/rpc-compat/tests/
# (the tests dir is self-contained: chain.rlp, genesis.json, forkenv.json,
#  headfcu.json, and the per-method .io files)
```

Confirm the chain matches if you only copy a few fixtures: `cmp` the two
`chain.rlp` files. Fixtures are only valid against the chain they were generated
on.

For a local spec change, generate and copy `openrpc.json` into the simulator
build context. Its gitignored status does not prevent Docker from copying it.

```sh
cd "$EXECapis"
make build
cp openrpc.json "$HIVE/simulators/ethereum/rpc-compat/openrpc.json"
```

Enable this override after the Dockerfile's specgen step:

```dockerfile
ADD openrpc.json /execution-apis/openrpc.json
```

The inspected Hive revision includes this line as a commented override.
Check the target Dockerfile and `.dockerignore` before use. A remote spec is
another option: `branch` supplies `GIT_REF`, and the clone URL determines which
repository can provide that ref. A branch name alone does not select a fork.
Keep the spec, fixtures, and chain aligned.

## Run against YOUR client built from source

hive clients have up to three Dockerfiles:

- `Dockerfile` — `FROM <prebuilt image>` (e.g. `ethereum/client-go:latest`).
  **This is the default and does NOT contain your change.**
- `Dockerfile.git` — clone `github=<org/repo>` at `tag=<branch>` and build.
- `Dockerfile.local` — build from a local source copy placed at
  `clients/<name>/<name>/`.

For a local change, use `Dockerfile.local`:

```sh
# place your client source where the local Dockerfile expects it (gitignored):
rsync -a --delete --exclude='.git/' --exclude='build/bin/' \
  $GETH/ $HIVE/clients/go-ethereum/go-ethereum/
```

Select the Dockerfile variant via a **client-file** YAML (`--client-file`):

```yaml
# clients.yaml
- client: go-ethereum
  dockerfile: local          # -> Dockerfile.local, builds clients/go-ethereum/go-ethereum
  nametag: mychange
- client: nethermind
  nametag: master
  build_args:
    tag: master              # prebuilt nethermindeth/nethermind:master
```

Fields: `client` (subdir under clients/), `dockerfile` (extension; omit = plain
`Dockerfile`), `nametag` (label in the image/result name), `build_args`
(e.g. `tag`, `baseimage`, `github`).

## forkenv → client env → flags, and gas-limit pinning

rpc-compat loads `tests/forkenv.json` and passes it to each client as **`HIVE_*` env
vars** (`main.go`); the client's wrapper (`*.sh` / `mkconfig.jq`) turns those into
flags. A new forkenv knob is inert until **both** ends exist (env var + wrapper
consumer).

**`HIVE_TARGET_GAS_LIMIT`** (execution-apis #801 / hive #1496) is the example. Unpinned,
block-*producing* fixtures diverge: geth moves parent gasLimit toward `--miner.gaslimit`
by `parent/1024` per block; Nethermind holds parent unless `Blocks.TargetBlockGasLimit`
is set → different gasLimit→baseFee→blockHash. New clients must add the same mapping.
Gas-limit-only divergence ⇒ suspect this, not the client.

## The `testing_` namespace and state-mutating methods

`testing_buildBlockV1`/`testing_commitBlockV1` live in a **`testing` namespace OFF by
default** — enable per client (like registration, clients.md): geth `--http.api=...,testing`;
Nethermind `EnabledModules:[...,"Testing"]` (hive #1496 did this). Missing ⇒ `-32601 method
does not exist` / `namespace 'Testing' is disabled` — not a bug. Other clients implement
them, so they're real conformance targets.

`commit`-style methods **mutate state** (insert block, advance head). A fixture calling
them repeatedly (or after another commit on the shared client) needs the prior commit's
state persisted — exposes backend-specific state bugs (clients.md). First commit may pass,
later ones fail: check per-fixture sequencing, not "empty vs content".

## Run it

```sh
cd $HIVE
./hive --sim ethereum/rpc-compat \
       --client-file clients.yaml \
       --sim.limit "rpc-compat/default-block"
```

### THE `--sim.limit` trap (most common false-green)

`--sim.limit` is parsed as `<suitePattern>/<testPattern>` (hivesim
`parseTestPattern`, split on `/`). A bare string is the **suite** pattern.

- The rpc-compat suite is named `rpc-compat`. The suite is gated *first*
  (`hivesim/testapi.go`): if the suite name doesn't match, the whole suite is
  skipped → `suites=0 tests=0 failed=0` and exit 0. **Looks green, ran nothing.**
- So `--sim.limit "default-block"` runs nothing. You must write
  `--sim.limit "rpc-compat/default-block"`.
- The outer `client launch` test is `AlwaysRun` so the test-name pattern won't
  skip it, but the suite gate still applies.
- Inside, the simulator uses the test-name part as a regex to pick `.io` files,
  and each sub-test name is `<method>/<case> (<client>)`.

Confirm the intended fixture names appear for every selected client.
The total includes `client launch` tests, so `tests > 0` does not prove fixture
coverage. Require successful launches, the expected fixture cases, and zero failures.

## Read the results

```sh
# the finished line is the headline:
grep "finished" <runlog>          # -> suites=1 tests=14 failed=0

# structured results:
F=$(ls -t $HIVE/workspace/logs/*-*.json | head -1)
jq -r '.testCases | to_entries[] | "\(.value.summaryResult.pass)\t\(.value.name)"' "$F"

# List the log location and byte range for each failed case:
jq '.testCases[] | select(.summaryResult.pass == false) | {name, log: .summaryResult.log}' "$F"
```

Use the result JSON from the current run. Per-test request and response logs
can live under `workspace/logs/details/`, separate from `.simLog`.
See [hivechain.md](hivechain.md) for extraction from those logs.

A `response differs` block shows `-- client` (what the client returned) vs
`++ test` (the recorded expectation). A `-32602 missing value for required
argument 1` from a client means that client rejects the omitted param — i.e. it
hasn't implemented the optional-param behavior (see `clients.md` for a real
example and fix).

**Break failures down per client** — the same fixture can pass on one, fail on another:
`jq -r '.testCases|to_entries[]|"\(.value.summaryResult.pass)\t\(.value.name)"' "$F"`.

### A client that fails to LAUNCH skips its tests (another false-green)

A container that dies at startup fails its `client launch` test and its method tests
**never run** (skipped, not failed) — `tests=N` silently drops (e.g. 20→11) while the
run still "finishes." Confirm each client's `client launch` passed and ran its expected
sub-tests. To see *why* it died, re-run with **`--docker.output`** (streams container
stdout/stderr). Beware stale logs: `ls -t workspace/logs/<client>/*.log` can return a
*previous* run's file — check its timestamp.

## Iterating quickly

Built images are cached, so re-runs after the first are fast (straight to the
simulation) unless you changed client source (rebuilds that image) or simulator
code/tests (rebuilds the simulator image). Editing a fixture in the simulator's
`tests/` dir is picked up on the next run because the simulator image is rebuilt.
