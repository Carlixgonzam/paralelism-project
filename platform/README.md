# WikiRacePlatform

Phoenix app for the WikiRace competition: harness, admin UI, dashboard.
See the repo root README.md and SCORING.md for what the project is and how
it's scored. See `../RUNNING.md` for how to run it locally, and `../DEPLOY.md` for how to
run a tournament.

## Definitions

- **Crawler**: a student group's program that searches for a link path
  between two articles.
- **Harness**: the referee that starts a race, watches both crawlers, and
  decides the result.

## Configuring a tournament

Files to edit before running a real tournament:

- `config/config.exs`, `:tournament`: the roster (group names), pairing generator
  (`:swiss` or `:round_robin`), the number of rounds, and the article pair of each round.
- `config/config.exs`, `:deploy`: the SSH user and key directory `mix wiki_race.deploy`
  connects with.
- `config/config.exs`, `:kiwix`: which Wikipedia snapshot crawlers race against.
- `priv/groups.exs`: one entry per group: name (must match the roster above), app, path to
  their checkout, and the `host`/`node` their release runs under, used by
  `mix wiki_race.deploy`/`.start`/`.stop` and by the admin page to find each group's node
  automatically.
- `priv/article_pairs.exs`: the curated start/target pool the admin page picks one fixed
  pair from, used for every match in the tournament.

## Directories

- `lib/wiki_race/`: the shared contract between the platform and every crawler, student or
  reference. It's what lets the platform treat any crawler the exact same way, regardless
  of who wrote it:
  - `crawler.ex`: the behavior a crawler must implement to start and be polled.
  - `status.ex`: the shape of a crawler's progress snapshot.
  - `harness.ex`: how a crawler reports a path it found.

- `lib/wiki_race_platform/`: the harness itself, everything that runs and scores a race:
  - `application.ex`: starts the app's supervision tree on boot.
  - `race.ex`: the entry point the web layer calls to run and watch a race.
  - `articles.ex`: the curated article pool, and the tournament's current pair.
  - `race/discovery.ex`: finds which module on a player node implements `WikiRace.Crawler`.
  - `race/dispatcher.ex`: owns the harness's global name, routes crawler reports to the right race.
  - `race/instance.ex`: runs one race start to finish.
  - `race/config.ex`: the time limit and poll interval for a race.
  - `race/player.ex`: one competitor's state during a race.
  - `race/verifier.ex`: checks a reported path is really a chain of links in Kiwix.
  - `race/result.ex`: ranks a finished race's standings.
  - `tournament/fixtures.ex`: generates a round's pairings.
  - `tournament/server.ex`: walks the tournament, reports standings.
  - `tournament/standings.ex`: folds race history into a standings table.
  - `tournament/store.ex`: persists finished race results to disk.
  - `deploy/manifest.ex`: the per-group deploy manifest (repo, tag, app name, host/node).
  - `deploy/release.ex`: builds a group's release for the player VM image.
  - `deploy/server.ex`: deploys, starts, stops, and reports on a group's release.
  - `deploy/transport.ex`: how the deploy server reaches a player VM (SSH).
  - `deploy/cli_state.ex`: persists a deploy's target/cookie between separate `mix wiki_race.*` runs.

- `lib/wiki_race_platform_web/`: the Phoenix web layer:
  - `live/race_live.ex`: the live race, with start/target/timer and head-to-head panels.
  - `live/schedule_live.ex`: the race day card, with matches played, the live one, and what's queued.
  - `live/standings_live.ex`: every group ranked by accumulated score.
  - `live/admin_live.ex`: race control, to pick the pair and start, advance, or abort a match.
  - `live/node_resolution.ex`: resolves a fixture's participants to connected nodes via `priv/groups.exs`.
  - `components/race_components.ex`: UI pieces shared by the dashboard and admin interface.
  - `components/core_components.ex`, `components/layouts.ex`: generated Phoenix UI/layout scaffolding.
  - `controllers/error_html.ex`, `controllers/error_json.ex`: generated error-response rendering.
  - `router.ex`, `endpoint.ex`, `telemetry.ex`, `gettext.ex`: standard Phoenix wiring.

- `lib/mix/tasks/`: custom `mix` tasks:
  - `wiki_race.deploy.ex`: builds, uploads, and unpacks a group's release onto its player VM over SSH.
  - `wiki_race.start.ex`: starts a group's deployed release as a daemon and waits for it to join the cluster.
  - `wiki_race.stop.ex`: stops a group's running release.

- `test/`: mirrors `lib/`'s structure, one test dir per source dir.
- `test/support/`: shared test helpers (fakes, cases).
- `priv/article_pairs.exs`: the curated start/target article pairs used for races.
- `priv/groups.exs`: the per-group deploy manifest (repo, tag, SHA, app name, host/node).
- `priv/data/`: persisted race results (one file, appended to).
- `priv/static/`, `priv/gettext/`: standard Phoenix asset/i18n dirs.
- `config/`: `config.exs` (shared), `dev.exs`/`test.exs`/`prod.exs` (per
  environment), `runtime.exs` (read at boot, e.g. from env vars).
- `assets/`: frontend source (JS/CSS) that Phoenix builds into `priv/static/`.
- `deps/`, `_build/`: fetched dependencies and compiled artifacts, not source.
