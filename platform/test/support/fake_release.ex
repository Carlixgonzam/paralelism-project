defmodule WikiRacePlatform.FakeRelease do
  @moduledoc """
  A scriptable stand-in for `Deploy.Release` used by `Deploy.ServerTest` so
  its state-machine tests don't shell out to Docker. Same scripting pattern
  as `FakeCrawler`/`FakeTransport`.
  """

  @doc "Installs a script for the next build and clears it afterwards."
  @spec script(map()) :: :ok
  def script(steps), do: Application.put_env(:wiki_race_platform, :fake_release, steps)

  @doc "The script currently installed."
  @spec script() :: map()
  def script, do: Application.get_env(:wiki_race_platform, :fake_release, %{})

  def build(group, on_output) do
    case Map.get(script(), :build) do
      nil ->
        on_output.("fake build of #{group.name}")
        {:ok, "/tmp/fake_release.tar.gz"}

      fun ->
        fun.(group, on_output)
    end
  end
end
