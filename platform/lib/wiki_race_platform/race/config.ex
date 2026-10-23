defmodule WikiRacePlatform.Race.Config do
  @moduledoc """
  Settings for a single race, validated before anything runs on a player node.

  There are no defaults for the timings on purpose. The caller sets both the
  time limit and the poll interval. Tournament races take them from
  `WikiRacePlatform.Tournament.Server`, which fixes them at 120 seconds and 250ms.
  """

  @type player_spec :: %{node: node(), label: String.t(), module: module() | nil}

  @type t :: %__MODULE__{
          start_url: String.t(),
          target_url: String.t(),
          time_limit_ms: pos_integer(),
          poll_interval_ms: pos_integer(),
          players: [player_spec()]
        }

  @enforce_keys [:start_url, :target_url, :time_limit_ms, :poll_interval_ms, :players]
  defstruct [:start_url, :target_url, :time_limit_ms, :poll_interval_ms, :players]

  @doc """
  Builds a config from a map or keyword list, checking it is runnable.

  `players` is a list of maps with a `:node`, a display `:label` and an optional
  `:module`. Leave `:module` as `nil` to let `WikiRacePlatform.Race.Discovery`
  find the crawler on the node.
  """
  @spec new(Enumerable.t()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) do
    attrs = Map.new(attrs)

    with {:ok, start_url} <- fetch_url(attrs, :start_url),
         {:ok, target_url} <- fetch_url(attrs, :target_url),
         :ok <- check_distinct(start_url, target_url),
         {:ok, time_limit} <- fetch_positive(attrs, :time_limit_ms),
         {:ok, poll} <- fetch_positive(attrs, :poll_interval_ms),
         :ok <- check_poll_fits(poll, time_limit),
         {:ok, players} <- fetch_players(attrs) do
      {:ok,
       %__MODULE__{
         start_url: start_url,
         target_url: target_url,
         time_limit_ms: time_limit,
         poll_interval_ms: poll,
         players: players
       }}
    end
  end

  @doc "The nodes taking part in this race."
  @spec nodes(t()) :: [node()]
  def nodes(%__MODULE__{players: players}), do: Enum.map(players, & &1.node)

  defp fetch_url(attrs, key) do
    case Map.get(attrs, key) do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, "#{key} must be a non-empty URL"}
    end
  end

  defp check_distinct(same, same), do: {:error, "start and target must differ"}
  defp check_distinct(_start, _target), do: :ok

  defp fetch_positive(attrs, key) do
    case Map.get(attrs, key) do
      n when is_integer(n) and n > 0 -> {:ok, n}
      _ -> {:error, "#{key} must be a positive integer"}
    end
  end

  defp check_poll_fits(poll, limit) when poll <= limit, do: :ok

  defp check_poll_fits(_poll, _limit),
    do: {:error, "poll_interval_ms must not exceed time_limit_ms"}

  defp fetch_players(attrs) do
    case Map.get(attrs, :players) do
      players when is_list(players) and players != [] ->
        validate_players(players)

      _ ->
        {:error, "players must be a non-empty list"}
    end
  end

  defp validate_players(players) do
    specs = Enum.map(players, &normalise_player/1)

    cond do
      Enum.any?(specs, &(&1 == :invalid)) ->
        {:error, "every player needs a node and a label"}

      not unique?(Enum.map(specs, & &1.node)) ->
        {:error, "the same node cannot play against itself"}

      true ->
        {:ok, specs}
    end
  end

  defp normalise_player(spec) do
    spec = Map.new(spec)
    node = Map.get(spec, :node)
    label = Map.get(spec, :label)
    module = Map.get(spec, :module)

    if is_atom(node) and not is_nil(node) and is_binary(label) and label != "" and
         (is_nil(module) or is_atom(module)) do
      %{node: node, label: label, module: module}
    else
      :invalid
    end
  end

  defp unique?(list), do: length(Enum.uniq(list)) == length(list)
end
