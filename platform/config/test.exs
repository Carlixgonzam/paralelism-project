import Config

# Tests that need the harness start their own, so the `:global` name is free
# for the contract tests to stand in as a fake harness.
config :wiki_race_platform, start_harness: false

# Same reasoning as start_harness above, for the same reason: the app-wide
# instance defaults to real :ssh/mix-release calls, which no test should
# exercise by accident. `deploy/server_test.exs` starts its own under the
# same registered name, with a fake transport/release builder.
config :wiki_race_platform, start_deploy_server: false

# Kept out of priv/data so a test run never touches dev/prod race history.
config :wiki_race_platform, :tournament_store, data_dir: "tmp/test/tournament"

# The app-wide roster, kept distinct from anything real or dev-local
# (`config/config.exs`'s value, `priv/groups.exs`'s entries) so tests never
# accidentally start matching or failing to match a group name someone
# happens to be using for local manual testing.
config :wiki_race_platform, :tournament,
  roster: ["Test Group A", "Test Group B", "Test Group C"],
  generator: :swiss,
  total_rounds: 3,
  round_pairs: []

# A placeholder. Nothing in the test suite fetches real content from this
# host; crawler/verifier tests inject their own fake Kiwix per test.
config :wiki_race_platform, :kiwix, base_url: "http://127.0.0.1:4593", book: "test_wiki"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :wiki_race_platform, WikiRacePlatformWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "FtBoZn7lDncX8E7p9/kBdejEOx7GqvPQdet+3GqbhCaNlM8fzlQ6n10S5qlTF4mb",
  server: false

# In test we don't send emails
config :wiki_race_platform, WikiRacePlatform.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
