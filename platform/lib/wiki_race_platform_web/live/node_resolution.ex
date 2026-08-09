defmodule WikiRacePlatformWeb.NodeResolution do
  @moduledoc """
  Resolves a fixture's participants to connected nodes using
  `priv/groups.exs`, so starting a match never needs a manual node picker.

  Used by `AdminLive` and `RaceLive`. Both let the professor start the next
  match: `AdminLive` as its main job, `RaceLive` as a shortcut so running
  the tournament does not require switching pages.
  """

  alias WikiRacePlatform.Deploy.Manifest

  @doc "The `%{name => node}` mapping `Tournament.Server.start_next!/2` needs for this fixture."
  @spec resolve(WikiRacePlatform.Tournament.Fixtures.fixture()) ::
          {:ok, %{String.t() => node()}} | {:error, String.t()}
  def resolve({:bye, name}) do
    with {:ok, node} <- fetch_node(name), do: {:ok, %{name => node}}
  end

  def resolve({a, b}) do
    with {:ok, node_a} <- fetch_node(a),
         {:ok, node_b} <- fetch_node(b) do
      {:ok, %{a => node_a, b => node_b}}
    end
  end

  defp fetch_node(name) do
    case Enum.find(Manifest.groups(), &(&1.name == name)) do
      %{node: node} when not is_nil(node) ->
        {:ok, node}

      _ ->
        {:error, "no node configured for #{name} in priv/groups.exs"}
    end
  end
end
