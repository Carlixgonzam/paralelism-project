defmodule WikiRacePlatform.FakeTransport do
  @moduledoc """
  A scriptable deploy transport for testing `Deploy.Server` without Docker
  or a real SSH target.

  It implements the real `Deploy.Transport` behaviour. `Deploy.Server`'s
  state machine runs unmodified. Only the four callbacks are faked, each
  overridable via a function installed in the script. Uses the same
  scripting pattern as `WikiRacePlatform.FakeCrawler`.
  """

  @behaviour WikiRacePlatform.Deploy.Transport

  @doc "Installs a script for the next deploy and clears it afterwards."
  @spec script(map()) :: :ok
  def script(steps) do
    Application.put_env(:wiki_race_platform, :fake_transport, steps)
  end

  @doc "The script currently installed."
  @spec script() :: map()
  def script, do: Application.get_env(:wiki_race_platform, :fake_transport, %{})

  @impl WikiRacePlatform.Deploy.Transport
  def connect(host, opts) do
    case Map.get(script(), :connect) do
      nil -> {:ok, {:fake_conn, host}}
      fun -> fun.(host, opts)
    end
  end

  @impl WikiRacePlatform.Deploy.Transport
  def upload(conn, local_path, remote_path) do
    case Map.get(script(), :upload) do
      nil -> :ok
      fun -> fun.(conn, local_path, remote_path)
    end
  end

  @impl WikiRacePlatform.Deploy.Transport
  def exec(conn, command) do
    case Map.get(script(), :exec) do
      nil -> {:ok, "", 0}
      fun -> fun.(conn, command)
    end
  end

  @impl WikiRacePlatform.Deploy.Transport
  def close(_conn), do: :ok
end
