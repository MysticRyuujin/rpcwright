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
  `ENV GIT_REF`) and copies its `tests/` into the image.
- `main.go` + `testload.go` load every `.io` file under `tests/` and replay it.
- **It does NOT validate against the OpenRPC spec.** It compares the client
  response to the recorded `<<` response with `jsondiff` (exact match). For a
  `speconly:` test it only checks the response *structure*. Error messages are
  redacted from the comparison **only** when both expected and actual are errors.

So: to change what hive checks, you change the `.io` fixtures (and the client),
**not** the spec.

## Run against LOCAL fixtures (your modified tests)

By default the Dockerfile pulls execution-apis from GitHub at `GIT_REF`. To use
your local fixtures, the Dockerfile has a documented override — copy your tests
into the simulator dir and uncomment the `ADD` line:

```dockerfile
# in simulators/ethereum/rpc-compat/Dockerfile:
# ADD tests /execution-apis/tests        # <- uncomment this
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
