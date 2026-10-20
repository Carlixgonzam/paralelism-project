# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure the endpoint
config :wiki_race_platform, WikiRacePlatformWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WikiRacePlatformWeb.ErrorHTML, json: WikiRacePlatformWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WikiRacePlatform.PubSub,
  live_view: [signing_salt: "UWs4QS8a"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :wiki_race_platform, WikiRacePlatform.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  wiki_race_platform: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  wiki_race_platform: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Where the offline Wikipedia snapshot is served from. Crawlers and the path
# verifier both fetch articles here, never from wikipedia.org.
config :wiki_race_platform, :kiwix,
  base_url: "http://localhost:8080",
  book: "wikipedia_en_all_nopic"

# Where finished race results are appended. One term per race, read back on
# boot by `WikiRacePlatform.Tournament.Store`.
config :wiki_race_platform, :tournament_store, data_dir: "priv/data"

# How races are scored. Weights sum to how much each axis counts.
# Published to students before they write anything.
config :wiki_race_platform, :scoring,
  weights: [found: 0.5, hops: 0.3, time: 0.1, utilization: 0.1]

# The tournament roster. Kept separate from priv/groups.exs's deploy
# manifest (name, repo, tag, commit SHA, checkout path), since
# Tournament.Server only needs names and doesn't care which source they
# come from.
#
# `round_pairs` is the difficulty progression: one {start, target} per
# round, drawn from priv/article_pairs.exs, easiest first. Every group
# faces the same difficulty in a given round, but the challenge escalates
# round to round. The admin page can still override a round's pair by
# hand if needed; that override only lasts for the round it was set in.
#
# These are placeholder pairs for local development. Before a real
# tournament, replace them with pairs timed against the full snapshot,
# easiest first, so the last round is a real test for a properly
# concurrent crawler without being unfindable in the time limit.
config :wiki_race_platform, :tournament,
  roster: ["Mutex Maniacs", "Deadlock Debutantes", "Race Condition"],
  generator: :swiss,
  total_rounds: 4,
  round_pairs: [
    {"Tiger", "Antarctica"},
    {"Bird", "Nelson Mandela"},
    {"Dinosaur", "Video game"},
    {"Leopard", "YouTube"}
  ]

# How Deploy.Server reaches a player VM: the dev keypair `make deploy-keys`
# generates for the docker-simulated player_vm1/player_vm2, resolved relative
# to wherever `mix` is running from (platform/, per RUNNING.md). Point this at
# a real per-deployment key once real player VMs exist.
config :wiki_race_platform, :deploy,
  ssh_user: "deploy",
  ssh_user_dir: "../deploy/keys"

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
