defmodule WikiRacePlatform.Deploy.CliState do
  @moduledoc """
  Persists a group's deploy target/cookie between separate
  `mix wiki_race.deploy`/`.start`/`.stop` invocations.

  `Deploy.Server` itself is in-memory only, which keeps it simple to test.
  But each mix task is its own short-lived BEAM process, so a `deploy`
  run's target and randomly-generated cookie would otherwise be lost the
  moment that process exits, leaving a later `start`/`stop` run with
  nothing to reattach to (see `Deploy.Server.reattach!/4`). This module is
  the terminal-only bridge across that process boundary. The admin LiveView
  never needed one, since it kept one `Deploy.Server` alive for the whole
  browser session.
  """

  alias WikiRacePlatform.Deploy.Server

  @dir "priv/data/deploy"

  @doc "Remembers `target`/`cookie` as the last known deploy for `group_name`."
  @spec put(String.t(), Server.target(), String.t()) :: :ok
  def put(group_name, target, cookie) do
    File.mkdir_p!(@dir)

    File.write!(
      path(group_name),
      :erlang.term_to_binary(%{target: target, cookie: cookie})
    )
  end

  @doc "The last known target/cookie for `group_name`, if `put/3` has ever been called for it."
  @spec fetch(String.t()) ::
          {:ok, %{target: Server.target(), cookie: String.t()}} | :error
  def fetch(group_name) do
    case File.read(path(group_name)) do
      {:ok, binary} -> {:ok, :erlang.binary_to_term(binary)}
      {:error, _reason} -> :error
    end
  end

  defp path(group_name) do
    slug = group_name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
    Path.join(@dir, "#{slug}.bin")
  end
end
