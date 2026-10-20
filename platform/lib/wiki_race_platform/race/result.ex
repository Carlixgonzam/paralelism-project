defmodule WikiRacePlatform.Race.Result do
  @moduledoc """
  The final standings for one race.

  Every entry gets a single blended score, roughly 0.0 to 1.0, and the ranking
  is that score sorted descending, highest wins. Finding a path dominates
  in practice (its weight alone outweighs everything else combined), but
  two crawlers that both fail to find a path still produce a ranking:
  found/first/hops/time all score zero for a non-finisher, and scheduler
  utilization is measured regardless of outcome. See `SCORING.md` for the
  published formula.

  One exception sits outside that blend: a crawler that ever reports a path
  the verifier rejects (structurally wrong, or claiming links that don't
  exist) scores `-1.0` flat, overriding found/first/hops/time/utilization
  entirely. Honestly not finding a path (worth 0.0-0.1) always beats lying
  about finding one.
  """

  alias WikiRace.Status
  alias WikiRacePlatform.Race.Player

  @false_path_penalty -1.0

  @type entry :: %{
          node: node(),
          label: String.t(),
          state: Player.state(),
          path: Status.path() | nil,
          path_length: non_neg_integer() | nil,
          elapsed_ms: non_neg_integer() | nil,
          first_elapsed_ms: non_neg_integer() | nil,
          visited_count: non_neg_integer(),
          error: String.t() | nil,
          utilization: float(),
          rejected?: boolean(),
          score: float()
        }

  @type decided_by :: :score | :only_finisher | :nobody_finished

  @type t :: %__MODULE__{
          ranking: [entry()],
          winner: entry() | nil,
          decided_by: decided_by(),
          ended_by: :all_settled | :time_limit | :aborted,
          duration_ms: non_neg_integer()
        }

  @enforce_keys [:ranking, :winner, :decided_by, :ended_by, :duration_ms]
  defstruct [:ranking, :winner, :decided_by, :ended_by, :duration_ms]

  @doc """
  Scores a finished race.

  `utilization_by_node` maps a player's node to its scheduler utilization
  for the race (0.0-1.0), measured externally by `Race.Instance` via two
  RPC snapshots taken at race start and end. Defaults to empty so a caller
  without that data (or old persisted results replayed through here) still
  gets a valid score, just with the utilization term at zero.
  """
  @spec build(
          [Player.t()],
          :all_settled | :time_limit | :aborted,
          non_neg_integer(),
          %{node() => float()}
        ) :: t()
  def build(players, ended_by, duration_ms, utilization_by_node \\ %{}) do
    ranking =
      players
      |> Enum.map(&entry(&1, utilization_by_node))
      |> with_score()
      |> Enum.sort_by(& &1.score, :desc)

    # A crawler that ever reported an unverifiable path is never the winner,
    # even if it also separately found (and got credit for) a real one.
    # "No matter the other metrics" covers the win itself, not just the
    # score.
    finishers = Enum.filter(ranking, &(&1.path && !&1.rejected?))

    %__MODULE__{
      ranking: ranking,
      winner: List.first(finishers),
      decided_by: decided_by(finishers),
      ended_by: ended_by,
      duration_ms: duration_ms
    }
  end

  @doc "A one-line explanation of the outcome, for the dashboard banner."
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{} = result) do
    [outcome_summary(result), false_path_summary(result)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp outcome_summary(%__MODULE__{winner: nil}), do: "No crawler found a valid path."

  defp outcome_summary(%__MODULE__{winner: winner, decided_by: :only_finisher}),
    do: "#{winner.label} wins, the only crawler to find a path."

  defp outcome_summary(%__MODULE__{winner: winner, decided_by: :score}),
    do:
      "#{winner.label} wins with a path of #{winner.path_length} articles " <>
        "in #{winner.elapsed_ms} ms."

  # `:path_length`/`:cost_score` can only appear in a `Result` persisted to
  # `Tournament.Store` before the blended-score redesign and read back as
  # historical data. `build/4` itself never produces them anymore. Same
  # "tolerate old data, don't crash" approach as `Standings`/`Fixtures`
  # reading a missing `:score` key off an old entry.
  defp outcome_summary(%__MODULE__{winner: winner, decided_by: :path_length}),
    do: "#{winner.label} wins with a path of #{winner.path_length} articles."

  defp outcome_summary(%__MODULE__{winner: winner, decided_by: :cost_score}),
    do:
      "#{winner.label} wins on time, #{winner.elapsed_ms} ms for " <>
        "#{winner.path_length} articles."

  defp false_path_summary(%__MODULE__{ranking: ranking}) do
    case Enum.filter(ranking, & &1[:rejected?]) do
      [] ->
        nil

      cheaters ->
        names = Enum.map_join(cheaters, " and ", & &1.label)
        penalty = @false_path_penalty

        "#{names} reported a path that failed verification and " <>
          "#{if length(cheaters) > 1, do: "score", else: "scores"} #{penalty}, no matter anything else."
    end
  end

  defp entry(%Player{} = player, utilization_by_node) do
    %{
      node: player.node,
      label: player.label,
      state: player.state,
      path: player.best_path,
      path_length: player.best_path && length(player.best_path),
      elapsed_ms: player.best_elapsed_ms,
      first_elapsed_ms: player.first_elapsed_ms,
      visited_count: player.status.visited_count,
      error: player.error,
      utilization: Map.get(utilization_by_node, player.node, 0.0),
      rejected?: player.rejected != [],
      score: 0.0
    }
  end

  # Found/hops/time are ratios against this race's best finisher, so a slow
  # VM or a wide margin can't decide the race by itself, and they stay at
  # zero for anyone who never found a path. Utilization is the only term
  # measured regardless of outcome, which is what decides a race nobody
  # finishes: whoever used their schedulers better. A crawler that ever
  # reported an unverifiable path skips this blend entirely and gets
  # `@false_path_penalty` flat, always below every honest non-finisher's
  # 0.0-0.1.
  #
  # First is all or nothing: 1.0 for the crawler whose first verified path
  # arrived earliest, 0.0 for everyone else. Unlike hops and time, a crawler
  # that also reported a false path is left out of that comparison, so it
  # cannot take the bonus away from an honest crawler.
  defp with_score(entries) do
    finishers = Enum.filter(entries, & &1.path)
    best_hops = finishers |> Enum.map(& &1.path_length) |> min_or_nil()
    best_elapsed = finishers |> Enum.map(& &1.elapsed_ms) |> min_or_nil()

    first_elapsed =
      finishers
      |> Enum.reject(& &1.rejected?)
      |> Enum.map(& &1.first_elapsed_ms)
      |> min_or_nil()

    best = %{hops: best_hops, elapsed: best_elapsed, first_elapsed: first_elapsed}
    Enum.map(entries, &%{&1 | score: score(&1, best)})
  end

  defp min_or_nil([]), do: nil
  defp min_or_nil(list), do: Enum.min(list)

  defp score(%{rejected?: true}, _best), do: @false_path_penalty

  defp score(entry, best) do
    weights = Application.get_env(:wiki_race_platform, :scoring, [])[:weights] || []

    found_score = if entry.path, do: 1.0, else: 0.0

    first_score =
      if entry.path && entry.first_elapsed_ms == best.first_elapsed, do: 1.0, else: 0.0

    hops_score = if entry.path, do: best.hops / entry.path_length, else: 0.0
    time_score = if entry.path, do: best.elapsed / max(entry.elapsed_ms, 1), else: 0.0

    Keyword.get(weights, :found, 0) * found_score +
      Keyword.get(weights, :first, 0) * first_score +
      Keyword.get(weights, :hops, 0) * hops_score +
      Keyword.get(weights, :time, 0) * time_score +
      Keyword.get(weights, :utilization, 0) * entry.utilization
  end

  defp decided_by([]), do: :nobody_finished
  defp decided_by([_only]), do: :only_finisher
  defp decided_by([_first, _second | _rest]), do: :score
end
