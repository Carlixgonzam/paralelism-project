defmodule WikiRacePlatform.Tournament.Standings do
  @moduledoc """
  Folds finished race history into a standings table.

  Entirely derived from `WikiRacePlatform.Tournament.Store.list/1` (or any
  list of `Race.Result.t()` history). There's nothing to persist here and
  nothing to keep in sync; just recompute whenever the current picture is
  needed.
  """

  alias WikiRacePlatform.Race.Result
  alias WikiRacePlatform.Tournament.Fixtures

  @type name :: String.t()
  @type standing :: %{
          wins: non_neg_integer(),
          score_sum: float(),
          byes: non_neg_integer(),
          games: non_neg_integer()
        }

  @doc """
  Standings and pairing history built from a list of finished results.

  A one-player ranking is a solo time trial: it counts as a bye, never a
  win, since there's no opponent to have beaten. A race with a determined
  winner credits that one win; a race nobody finished credits none. Every
  pairing that actually raced (byes excluded, there's no pairing to record)
  lands in the returned set, normalized so `{a, b}` and `{b, a}` collapse
  to the same entry.
  """
  @spec compute([Result.t()]) :: {%{name() => standing()}, MapSet.t({name(), name()})}
  def compute(results) do
    Enum.reduce(results, {%{}, MapSet.new()}, fn result, {standings, played} ->
      apply_result(result, standings, played)
    end)
  end

  defp apply_result(%Result{ranking: [only]}, standings, played) do
    standings =
      bump(standings, only.label, wins: false, byes: 1, score: Map.get(only, :score))

    {standings, played}
  end

  defp apply_result(%Result{ranking: [a, b]} = result, standings, played) do
    winner_label = result.winner && result.winner.label

    standings =
      standings
      |> bump(a.label, wins: win?(a, winner_label), byes: 0, score: Map.get(a, :score))
      |> bump(b.label, wins: win?(b, winner_label), byes: 0, score: Map.get(b, :score))

    {standings, MapSet.put(played, Fixtures.normalize_pair(a.label, b.label))}
  end

  defp apply_result(%Result{ranking: []}, standings, played), do: {standings, played}

  # Not part of the course rules (1v1 only), handled defensively rather
  # than assumed impossible: every entry gets its win/score credit, and
  # every pair among them is recorded as played.
  defp apply_result(%Result{ranking: ranking} = result, standings, played) do
    winner_label = result.winner && result.winner.label

    standings =
      Enum.reduce(ranking, standings, fn entry, acc ->
        bump(acc, entry.label,
          wins: win?(entry, winner_label),
          byes: 0,
          score: Map.get(entry, :score)
        )
      end)

    played =
      for a <- ranking, b <- ranking, a.label < b.label, reduce: played do
        acc -> MapSet.put(acc, {a.label, b.label})
      end

    {standings, played}
  end

  defp win?(entry, winner_label), do: entry.label == winner_label

  defp bump(standings, label, opts) do
    win? = Keyword.fetch!(opts, :wins)
    bye = Keyword.fetch!(opts, :byes)
    score = Keyword.fetch!(opts, :score)

    current = Map.get(standings, label, %{wins: 0, score_sum: 0.0, byes: 0, games: 0})

    updated = %{
      current
      | wins: current.wins + if(win?, do: 1, else: 0),
        byes: current.byes + bye,
        score_sum: current.score_sum + (score || 0.0),
        games: current.games + 1
    }

    Map.put(standings, label, updated)
  end
end
