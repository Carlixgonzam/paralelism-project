defmodule WikiRacePlatform.Race do
  @moduledoc """
  The entry point the web layer uses to run and watch races.

  Everything here is a thin pass-through to `WikiRacePlatform.Race.Dispatcher`
  (and the `WikiRacePlatform.Race.Instance` it hands races off to). LiveViews
  never have to know the harness is split across two kinds of process.
  `start/1`, `abort/0` and `snapshot/0` all act on "the current race",
  whichever one `Dispatcher` most recently started. That is today's
  single-viewer behavior, even though the dispatcher underneath can track
  more than one race at a time.
  """

  alias WikiRacePlatform.Race.Config
  alias WikiRacePlatform.Race.Dispatcher
  alias WikiRacePlatform.Race.Instance

  @idle_snapshot %{
    race_id: nil,
    status: :idle,
    config: nil,
    players: [],
    started_at_utc: nil,
    ended_at_utc: nil,
    elapsed_ms: 0,
    result: nil
  }

  @doc "Starts a race from raw admin form values."
  @spec start(Enumerable.t()) :: {:ok, map()} | {:error, String.t()}
  def start(attrs) do
    with {:ok, config} <- Config.new(attrs) do
      Dispatcher.start_race(config, dispatcher())
    end
  end

  @doc "Ends the current race early."
  @spec abort() :: {:ok, map()} | {:error, String.t()}
  def abort do
    case Dispatcher.current(dispatcher()) do
      nil -> {:error, "no race is running"}
      race_id -> abort(race_id)
    end
  end

  @doc "Ends the given race early, scoring whatever has been verified."
  @spec abort(reference()) :: {:ok, map()} | {:error, String.t()}
  def abort(race_id) do
    case Dispatcher.abort(race_id, dispatcher()) do
      {:error, "no such race"} -> {:error, "no race is running"}
      other -> other
    end
  end

  @doc "The current race's state."
  @spec snapshot() :: map()
  def snapshot do
    case Dispatcher.current(dispatcher()) do
      nil -> @idle_snapshot
      race_id -> snapshot(race_id) || @idle_snapshot
    end
  end

  @doc "The given race's state, in the shape broadcast on its topic."
  @spec snapshot(reference()) :: map() | nil
  def snapshot(race_id), do: Dispatcher.snapshot(race_id, dispatcher())

  @doc "Subscribes the calling process to `{:race_update, snapshot}` messages."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(WikiRacePlatform.PubSub, Instance.legacy_topic())
  end

  @doc """
  Player nodes currently connected to the platform.

  Anything in the cluster that is not the platform itself counts as a
  candidate. That is enough on a private competition network.
  """
  @spec connected_nodes() :: [node()]
  def connected_nodes, do: Enum.sort(Node.list())

  # `Dispatcher` runs wherever `:harness_node` points. By default that is
  # this node, so the call below is a plain local call. See
  # `Deploy.Server`'s moduledoc for running the harness on a separate node.
  defp dispatcher,
    do: {Dispatcher, Application.get_env(:wiki_race_platform, :harness_node, node())}
end
