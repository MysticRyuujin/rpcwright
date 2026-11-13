# hive: the rpc-compat cross-client conformance harness

hive builds Docker images for clients and simulators and runs them together. The
`rpc-compat` simulator replays execution-apis `.io` fixtures against a client and
compares responses. Requires Docker.

The runner guidance below is based on
[Hive revision 14d57b16](https://github.com/ethereum/hive/tree/14d57b1664cc832381ab12b62033b9f22e047957/simulators/ethereum/rpc-compat).
That revision gives the spec checker the recorded `<<` line, not the client
response; see the "Every test" item below. Check the selected revision before
relying on these features.

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
  `ENV GIT_REF`), runs `make build` there, and copies `tests/` and
  `refs-openrpc.json` into the image. `refs-openrpc.json` is a build artifact
  and gitignored in execution-apis, so the clone does not contain it.
- `main.go` loads fixtures and runs scripts with the `iofile` package, and checks
  messages with the `spec` package. Both come from the execution-apis `tools`
  module that the simulator's `go.mod` pins. A change to those packages reaches
  Hive only after that pin moves.
- **Every test:** a spec checker validates each request and response against the
  OpenRPC method. Request errors are only logged. Confirm that the runner gives
  the checker the client response, not the recorded `<<` line. If it gives the
  recorded line, no client response is schema-checked.
- **Ordinary test:** the client response must equal the recorded `<<` response
  (`jsondiff`). Error messages are redacted from the comparison **only** when
  both expected and actual are errors, including nested `error` objects.
  `error.code` and `error.data` stay in the comparison and must match exactly.
- **`speconly:` test:** the exact comparison is skipped when the client returns
  a result. Schema validation and the script remain. An error response is still
  compared with the recorded one.
- **Validation script:** after the exchange, the runner runs the script with the
  client responses. A thrown exception fails the test. A `speconly` test without
  a script checks only the schema, so a permissive `anyOf` branch can make it
  pass with any value. See [testgen.md](testgen.md#validation-scripts).

> Historical note / gotcha: `speconly` used to be a *structural* diff against the
> recorded `<<` example. It rejected both **missing** and **unexpected** keys.
> If you hit a `speconly` failure like `unexpected key in response` /
> `missing key`, you are on an old hive. Update it.

So: an ordinary test is changed via the `.io` fixtures (and the client); a
`speconly` test is governed by the **OpenRPC schema** in `src/` and its script.
The sim regenerates `refs-openrpc.json` from source on its next image build.

## Run against local or unmerged fixtures

The simulator image takes fixtures and the spec from three places. The builder
stage clones execution-apis at `GIT_REF` and runs `make build`. The final stage
copies the whole simulator directory (`ADD . /source`). It then copies the
builder's `tests/` and `refs-openrpc.json` over that directory. A directory copy
merges; it does not delete. So a file in the simulator directory's own `tests/`
stays in the image unless the clone has a file with the same name.

Consequences:

- A leftover `tests/` directory in the simulator directory adds stale fixtures
  to every later run, including a run that selects a PR with `branch=`.
- The commented `ADD tests /execution-apis/tests` override also merges. Cloned
  fixtures that your local set deleted or renamed still run.
- With `ADD tests` enabled, `--sim.buildarg branch=<ref>` still selects the spec
  but no longer selects the fixtures. The run looks like a test of that ref.
- A cached simulator image can serve old fixtures. Force a rebuild with
  `--docker.nocache <image-regex>` when the result does not match the inputs.

This description matches the Dockerfile at Hive revision 4ab0d323. Do not edit
the shared `rpc-compat` directory. Before a run from it, confirm
that `git status --short simulators/ethereum/rpc-compat` prints nothing.

**Fixtures from a branch or PR of ethereum/execution-apis:** use the unmodified
simulator. No copy is needed.

```sh
./hive --sim ethereum/rpc-compat --sim.buildarg branch=refs/pull/<N>/head ...
```

The clone URL is fixed, so a branch name alone does not select a fork.

**Local fixtures:** make a copy from tracked files only, then replace the
cloned fixtures and spec in that copy.

```sh
cd "$HIVE"
SIM=simulators/ethereum/rpc-compat-<topic>
mkdir "$SIM" && git archive HEAD:simulators/ethereum/rpc-compat | tar -x -C "$SIM"
rsync -a --delete "$EXECapis/tests/" "$SIM/tests/"
(cd "$EXECapis" && make build) && cp "$EXECapis/refs-openrpc.json" "$SIM/"
```

In the copy's Dockerfile, replace the two commented override lines with:

```dockerfile
RUN rm -rf /execution-apis/tests
ADD tests /execution-apis/tests
ADD refs-openrpc.json /execution-apis/refs-openrpc.json
```

Run it with `--sim ethereum/rpc-compat-<topic>`. Delete the copy when the task
ends; an old copy keeps an old Dockerfile and runner.

Copy the full `tests/` directory. It holds `chain.rlp`, `genesis.json`,
`forkenv.json`, `headfcu.json`, and the fixtures, and fixtures are valid only
for the chain that produced them. The spec must come from the same checkout:
fixtures that use a new method or component fail against a spec built from the
default ref.

The runner imports `iofile` and `spec` from the execution-apis `tools` module
that the simulator's `go.mod` pins. To test an unmerged change to those
packages, copy `tools` into the simulator copy and add a `replace` directive
for `github.com/ethereum/execution-apis/tools` that points at it.

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
rsync -a --delete --exclude='.git' --exclude='build/bin/' --exclude='/tests/' \
  $GETH/ $HIVE/clients/go-ethereum/go-ethereum/
```

- Write `--exclude='.git'` without a trailing slash. In a Git worktree `.git` is
  a file, and `.git/` matches directories only.
- Do not exclude all of `build`. geth's Makefile runs `build/ci.go`.
- geth's top-level `tests/` holds large consensus fixtures that the client build
  does not need.
- Check the client's `Dockerfile.local` for a build that reads Git metadata. For
  such a client, copy from a real clone, not from a worktree.

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
is set → different gasLimit→baseFee→blockHash. The simulator sets a default when
`forkenv.json` has no value (`main.go`). A client is pinned only when its wrapper
reads the variable: `grep -l HIVE_TARGET_GAS_LIMIT -r clients/`. At the inspected
revision the nimbus-el wrapper does not. Gas-limit-only divergence ⇒ check this
mapping before the client.

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

## Survey raw client behavior (no expected value needed)

For a client behavior survey, use temporary `.io` files in a simulator copy (see
"Run against local or unmerged fixtures") with an
impossible `<<` line (e.g. `"result":"SURVEY_PLACEHOLDER"`), give them a shared name
prefix, and run `--sim.limit "rpc-compat/<prefix>"`. Every case "fails" — that is the
point; the raw answers are in the per-test log. The request/response pairs are NOT in
the simulator log; they live in `workspace/logs/details/<sim-id>-0.log`, addressed by
byte offsets from the results JSON (`summaryResult.log.{begin,end}`), as `>> ` / `<< `
lines:

```sh
cd $HIVE; F=$(ls -t workspace/logs/*-*.json | head -1)
D=workspace/logs/details/$(basename $(jq -r .simLog $F) .log | sed "s/-simulator-/-/")-0.log
jq -r '.testCases|to_entries[]|select(.value.name|test("<prefix>"))|"\(.value.name)\t\(.value.summaryResult.log.begin)\t\(.value.summaryResult.log.end)"' $F \
| sort | while IFS=$'\t' read -r name b e; do
  printf '%s\t%s\n' "$name" "$(tail -c +$((b+1)) $D | head -c $((e-b)) | sed 's/\x1b\[[0-9;]*m//g' | grep -a -m1 '^<<' | sed 's/^<< *//')"
done
```

Use runtime results to confirm behavior inferred from source. Record client
revisions and configuration with the responses. Keep survey fixtures outside the
committed corpus and remove them from subsequent conformance runs.

Before you interpret a missing or empty result, compare the client's
`eth_blockNumber` with the chain head. A client that did not import the chain
answers every historical query from genesis.

## Iterating quickly

Built images are cached, so re-runs after the first are fast (straight to the
simulation) unless you changed client source (rebuilds that image) or simulator
code/tests (rebuilds the simulator image). A fixture edit in the simulator
copy's `tests/` directory changes the build context, so the next run rebuilds the
image. If a run still shows old fixtures, force the rebuild with `--docker.nocache`.
