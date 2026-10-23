ExUnit.start()

# The deploy integration tests need Docker (a real `release_builder` build,
# a real sshd in `player_vm1`). Excluded from the default `mix test`/
# `mix precommit` run. Run them with `make test-deploy` or
# `mix test --only integration`.
ExUnit.configure(exclude: [:integration])

WikiRacePlatform.Tournament.Store.clear()
