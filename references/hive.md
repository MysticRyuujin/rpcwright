# hive: the rpc-compat cross-client conformance harness

hive builds Docker images for clients and simulators and runs them together. The
`rpc-compat` simulator replays execution-apis `.io` fixtures against a client and
compares responses. Requires Docker.

## Build hive

```sh
cd $HIVE
go build .            # produces ./hive
```

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
  the clone and cannot simply be copied. The Dockerfile runs specgen (which pulls
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

**Don't copy `openrpc.json` — you can't.** It's gitignored in execution-apis, and
the sim builds it from the cloned `src/` with specgen at image-build time (see
above). So a local *spec* change reaches `speconly` tests only by changing the
**source the sim clones**: point the build at your execution-apis branch (the
`branch`/`GIT_REF` build-arg) so specgen regenerates the schema from your `src/`.
Overriding only `tests/` while the spec is cloned from a different ref leaves
`speconly` tests validating against the old schema.

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

Always confirm the run actually executed tests: look for `tests=N` with `N>0` in
the final `simulation ... finished` line.

## Read the results

```sh
# the finished line is the headline:
grep "finished" <runlog>          # -> suites=1 tests=14 failed=0

# structured results:
F=$(ls -t $HIVE/workspace/logs/*-*.json | head -1)
jq -r '.testCases | to_entries[] | "\(.value.summaryResult.pass)\t\(.value.name)"' "$F"

# failure detail: each failing case has summaryResult.log {begin,end} into the
# simulator log named by .simLog. Or just grep the sim log:
SIM=$(jq -r '.simLog' "$F")
grep -n "response differs from expected" "$HIVE/workspace/logs/$SIM"
```

A `response differs` block shows `-- client` (what the client returned) vs
`++ test` (the recorded expectation). A `-32602 missing value for required
argument 1` from a client means that client rejects the omitted param — i.e. it
hasn't implemented the optional-param behavior (see `clients.md` for a real
example and fix).

## Iterating quickly

Built images are cached, so re-runs after the first are fast (straight to the
simulation) unless you changed client source (rebuilds that image) or simulator
code/tests (rebuilds the simulator image). Editing a fixture in the simulator's
`tests/` dir is picked up on the next run because the simulator image is rebuilt.
