defmodule WikiRacePlatform.Deploy.Transport do
  @moduledoc """
  How `Deploy.Server` reaches a player VM: connect, upload a release
  tarball, run a remote command, disconnect.

  A behaviour, not a hardcoded `:ssh` call. This gives `Deploy.Server`'s
  state machine a fast, Docker-free unit test path against
  `WikiRacePlatform.FakeTransport`. The real `:ssh`/`:ssh_sftp` traffic in
  `Deploy.Transport.SSH` only gets exercised against the
  docker-compose-simulated `player_vm1`/`player_vm2`.
  """

  @type conn :: term()

  @callback connect(host :: String.t(), opts :: keyword()) ::
              {:ok, conn()} | {:error, term()}
  @callback upload(conn(), local_path :: String.t(), remote_path :: String.t()) ::
              :ok | {:error, term()}
  @callback exec(conn(), command :: String.t()) ::
              {:ok, output :: String.t(), exit_status :: non_neg_integer()}
              | {:error, term()}
  @callback close(conn()) :: :ok
end
