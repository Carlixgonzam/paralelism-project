# Running a race locally

`docker-compose.yml` and the `Makefile` live here, at the repo root. All
commands below run from here unless a step says otherwise.

## 1. Bring everything up

```
make up
```

This downloads the Wikipedia snapshot first if you don't already have it
(see "Choosing a snapshot" below), then builds and starts four containers:

- `kiwix1`: serves the offline Wikipedia snapshot.
- `platform`: the Phoenix app (harness, admin, dashboard).
- `player1`, `player2`: two nodes built from your `player/` checkout.

Dashboard: <http://localhost:4000>. Admin: <http://localhost:4000/admin>.
`make down` stops everything. `make logs` follows every container's output.

### Choosing a snapshot

The default is the full encyclopedia (`wikipedia_en_all_nopic`, ~52 GB),
so local content matches competition day exactly. `make up` fetches it
automatically the first time. If you already have a copy, place it at
`.data/zim/wikipedia_en_all_nopic.zim` (exact name, no date suffix) and
it'll be reused.

For faster local iteration, two smaller snapshots are available:

```
make up KIWIX_BOOK=wikipedia_en_100_nopic   # tiny smoke-test pack, ~15 MB
make up KIWIX_BOOK=wikipedia_en_top_nopic   # real linking, ~2.2 GB
```

`wikipedia_en_100_nopic` is so small that most links get pruned when the
snapshot is built, so it's good for checking the wiring works but not for
testing real crawler search logic. `wikipedia_en_top_nopic` has real
inter-article linking and is a much faster download than the full
snapshot. Kiwix reads whichever book you picked, and the platform is told
the same book automatically.

## 2. Give a player a crawler

`player/` is the skeleton students get. See `player/README.md`. Both the
`player1` and `player2` containers mount and build from this same source
tree, but compile and run independently, so it's still two separate
nodes racing each other with identical code, a mirror match against
yourself. `player/lib/player/crawler.ex` declares `@behaviour
WikiRace.Crawler`, so the admin page can discover it, but `start/2` and
`status/1` both raise until you implement them.

Implement `start/2` and `status/1` there, then restart both player
containers so each recompiles against the change:

```
docker compose restart player1 player2
```

To give one side a handicap for a demo, read a runtime config knob your
own crawler defines, rather than diverging the two sides' code.

Edits to `player/lib/` take effect on the next restart. The source tree
is bind-mounted, not baked into the image.

## 3. Run it

Open `/admin`. It shows the next match, `player1` vs `player2`, since the
dev config's tournament roster is exactly those two names (see
`platform/config/dev.exs` and `platform/priv/groups.exs`). You can pick
a different article pair from the dropdown. The time limit (120 seconds)
and the poll interval (250 ms) are not something you pick per race. They
are fixed in `WikiRacePlatform.Tournament.Server`.

Click "Start race". With an untouched checkout, both sides raise the
same way, so the race never actually starts: `/admin` shows an inline
error like `player1: start/2 unreachable: ...; player2: start/2
unreachable: ...` instead of taking you to the dashboard. That is the
expected result before you have written anything, and confirms the
harness, the dashboard, and both player nodes can all talk to each
other. Once you have implemented your crawler, clicking "Start race"
again lands you on the dashboard, where you can watch both sides race
live.

The dev roster only has one match in it, so once a race finishes,
`/admin` shows the tournament as complete. Use "Restart tournament", in
the danger zone at the bottom of `/admin`, to clear it and run another
one while you iterate on your crawler.

Finished races are appended to `platform/priv/data/results.terms` (inside
the `platform` container) and read back on boot, so restarting the
platform node doesn't lose race history.

## Article pairs

Races don't draw a random start/target pair. Every race, manual or
tournament, uses one fixed pair from the curated pool in
`platform/priv/article_pairs.exs` (`WikiRacePlatform.Articles.pairs/0`).
A random pair could be many hops apart or not connected at all, which
would make wait times unpredictable, so pairs are picked and vetted
ahead of time instead. A tournament's rounds use a configured sequence
of pairs from that same pool (`round_pairs` in
`platform/config/config.exs`). The dropdown on `/admin` overrides the
pair for the current round only.

After editing the pool, check it against the running Kiwix instance,
from `platform/`:

```
cd platform && iex -S mix
```

```elixir
WikiRacePlatform.Articles.check_pairs()
```

## Deploying a release

`/admin` starts a race by connecting to a player node that's already
running. Deploying is the step before that: building a group's `mix
release` and shipping it to a player VM over Erlang's own
`:ssh`/`:ssh_sftp`, then starting it and confirming it joins the
cluster. Never a shelled-out `ssh` binary. Deployment runs from the
terminal through `mix wiki_race.deploy`, `mix wiki_race.start` and `mix
wiki_race.stop`. There is no web UI for it.

This is a once-per-group setup step, not a once-per-match one. Deploy and
start every group's release before the tournament starts. Each release
then stays running and connected for every match it plays. Once every
group is connected, running the whole tournament is just clicking
through matches on `/admin`: it looks up each match's two groups by name
in `platform/priv/groups.exs` to find their already-connected nodes,
never redeploying anything.

There's no real player VM to deploy to yet (the GitHub Releases pull and
the actual VM provisioning aren't built), so docker-compose stands in
for a real one: `player_vm1`/`player_vm2` run actual `sshd`, so the
deploy code's `:ssh` traffic is genuine, not mocked. They don't start
with plain `make up`. Bring one up explicitly:

```
make deploy-keys
docker compose up -d player_vm1
```

`make deploy-keys` generates a dev-only keypair under `deploy/keys/`
(never committed) that the platform uses to authenticate.
`authorized_keys` on the simulated VM is bind-mounted from the generated
public key, so it has to exist before the container starts.

Groups are listed in `platform/priv/groups.exs`, the same
editable-without-a-restart pattern as `platform/priv/article_pairs.exs`.
It ships with one entry, "Local fixture," pointing at the in-repo
`player/` skeleton. That's enough to exercise the whole pipeline without
a real group's checkout. From `platform/`, deploy it to the simulated
VM and then start it:

```
mix wiki_race.deploy "Local fixture" --host HOST --node NODE
mix wiki_race.start "Local fixture"
```

`HOST` is the simulated VM's address and `NODE` is the node name the
release runs under (e.g. host `player_vm1`, node `groupa@player_vm1` if
the platform itself runs inside compose reaching it by service name, or
the container's IP and a matching IP-based node name if running the
platform on the host, see the note on distribution modes below). Both
default to the group's `host`/`node` fields in `platform/priv/groups.exs`.
`mix wiki_race.deploy` streams the build log. Once it reports the group
as deployed, the release is on the VM but not running yet. `mix
wiki_race.start` joins it to the cluster, and `mix wiki_race.stop` takes
it back down.

**Long names, not short.** Every other node in this project (`platform`,
`player1`, `player2`) uses `--sname` with docker-internal service-name
aliases. `Deploy.Server` uses `--name` (`RELEASE_DISTRIBUTION=name`)
instead, since a real player VM is identified by an IP or a real
hostname, not a compose-internal alias, and Erlang requires both sides
of a distributed connection to agree on short vs. long names. If you're
running the platform itself on the host (not inside the `platform`
compose service) to drive a deploy, start it distributed and long-named
to match:

```
cd platform && elixir --name platform@127.0.0.1 --cookie wikirace -S mix phx.server
```

**Sandboxing and resource limits.** The release should run as an
unprivileged user in a resource-limited sandbox. Docker already
provides both for the simulated VMs: the SSH session lands as the
unprivileged `deploy` user (`deploy/vm/Dockerfile`), and
`player_vm1`/`player_vm2`'s `mem_limit`/`cpus` in `docker-compose.yml`
are the resource limits, generous and identical on both sides (this
stops a runaway process, it doesn't cap the parallelism being graded).
On a real, non-containerized player VM, the equivalent is a systemd unit
running the release as its own unprivileged user, with
`MemoryMax=`/`CPUQuota=` (cgroup v2) set identically for both sides. Not
built here, since there's no real VM yet to build it against, but that's
the direct mapping when one exists.

`make test-deploy` runs the real integration suite (a real release
build, a real SSH round trip, a real cluster join) against `player_vm1`.
See `platform/test/wiki_race_platform/deploy/integration_test.exs`.
Plain `mix test` stays Docker-free. Anything tagged `:integration` is
excluded by default.

## Security hardening

Containment (`player_vm1`/`player_vm2`, already in the compose file,
nothing extra to run): a read-only root filesystem (`tmpfs` only for
`/tmp`, `/run`, and `/home/deploy/releases`, the last one with `exec`
since that's where the release actually runs from), generous identical
`mem_limit`/`cpus`, and network segmentation. `player1_net`/`player2_net`
are each `internal: true` (no internet egress) and never shared between
the two player VMs, so `player_vm1` cannot route to `player_vm2` at all,
even though both independently reach `kiwix1`/`platform`. Verify any of
this by hand:

```
docker exec wikirace-player_vm1-1 sh -c 'touch /etc/x'            # read-only fails
docker exec wikirace-player_vm1-1 elixir -e ':gen_tcp.connect(~c"1.1.1.1", 80, [], 3000) |> IO.inspect()'  # no egress
```

The harness split, per-race cookie rotation, and TLS distribution are
real, working code, verified with two genuinely separate Erlang nodes,
not just the single-node default this repo runs day to day. They're
opt-in, not wired into `docker compose up`, since turning them on for
the default `platform`/`player1`/`player2` dev loop would require
converting that loop to the same scheme too, which is out of scope until
there's a real second VM topology to justify it. To run them for real:

**Split harness.** `Deploy.Server` (`web`) never opens a distribution
link to a player itself. It asks whichever node `:harness_node` points
at to do it, over `:rpc.call/4`. Point `WEB_NODE`/`HARNESS_NODE` at two
different nodes and they behave as a real split (both default to
`node()`, i.e. themselves, today). `Race.Instance` addresses
`Tournament.Store` the same way via `:web_node`, so results still land
wherever `web` actually runs.

**Per-race cookie.** Already always on: every `deploy!/3` generates a
fresh random cookie, used as that specific release's `RELEASE_COOKIE`
and set as a per-node override (`Node.set_cookie/2`) only on the harness
node that connects to it, never adopted as this app's own default
cookie. A player never learns any cookie but its own.

**TLS distribution.**

```
make dist-certs
```

Generates a dev-only CA plus one certificate per role (`web`, `harness`,
`player`) under `deploy/certs/`, all signed by it. A node started
without a certificate that CA signed can't join distribution at all, not
just fail a cookie check. To actually turn it on:

- Start `web`/`harness` with `-proto_dist inet_tls -ssl_dist_optfile
  deploy/certs/<role>.conf` in `ELIXIR_ERL_OPTIONS`.
- Set `config :wiki_race_platform, :deploy, tls: true` (plus
  `:tls_certs_dir` if not the default `../deploy/certs`) in
  `platform/config/`. `Deploy.Server` then uploads the player
  cert/key/CA cert and a `RELEASE_VM_ARGS` file alongside every deploy,
  so the release boots under TLS too, no changes to the group's own
  project needed.

The certs `make dist-certs` generates are only valid for the
hostnames/IPs listed in `deploy/certs/san.cnf`. Regenerate with real
player VM hostnames added before using this against anything other than
the docker-simulated setup.

## Environment variables

| Variable | Default | What it does |
| --- | --- | --- |
| `KIWIX_BASE_URL` | `http://localhost:8080` | Where Kiwix is |
| `KIWIX_BOOK` | `wikipedia_en_all_nopic` | Which ZIM to read |
| `START_HARNESS` | `true` | Set to `false` on player nodes, or on a web-only split node |
| `START_WEB` | `true` | Set to `false` on a harness-only split node |
| `WEB_NODE` | this node | Where `Tournament.Store`/`Deploy.Server` actually run, if split |
| `HARNESS_NODE` | this node | Where `Race.Dispatcher`/`Race.Instance` actually run, if split |
| `PORT` | `4000` | HTTP port |
| `WIKI_RACE_DATA_DIR` | `priv/data` | Where finished race results are appended |

`docker-compose.yml` sets sensible defaults for all of these. You only
need them by hand for the appendix below.

## Appendix: running without docker-compose

Everything above on one machine, no containers, three extra terminals.
Useful for debugging the platform or a player node directly. The `mix`
and `elixir` commands below run from `platform/`, since that's where
`mix.exs` lives.

### Kiwix

Serve the snapshot you fetched with `make fetch-zim` directly:

```
docker run -d --name wikirace-kiwix -p 8080:8080 \
  -v "$(pwd)/.data/zim:/data:ro" \
  ghcr.io/kiwix/kiwix-serve:latest /data/wikipedia_en_all_nopic.zim
```

(run from the repo root, and adjust the path and filename to whichever
book you fetched). Check it works: `curl -sI http://localhost:8080/` should
return 200.

### The platform node

```
cd platform
mix setup
elixir --sname platform --cookie wikirace -S mix phx.server
```

### Two player nodes

Run the `player/` checkout as its own node, the same code `player1`/
`player2` build from in compose:

```
cd player
elixir --sname player1 --cookie wikirace -S mix run --no-halt
```

Then connect it to the platform. From an `iex` session on the player
node:

```elixir
Node.connect(:"platform@YOUR_HOSTNAME")
```

Repeat for `player2` from another terminal. `hostname -s` gives you the
short name. All nodes must share the same cookie.

Until `player/lib/player/crawler.ex`'s `start/2`/`status/1` are
implemented, both nodes behave exactly like the compose flow: the harness
can discover the module, but starting a race against it raises.
