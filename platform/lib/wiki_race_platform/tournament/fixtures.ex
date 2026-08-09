defmodule WikiRacePlatform.Tournament.Fixtures do
  @moduledoc """
  Pairing generators for a tournament round.

  Pure functions: given a roster and whatever context a generator needs,
  return the fixtures for a round (or, for round-robin, every round at
  once). Nothing here runs a race, tracks state, or touches persistence.
  `WikiRacePlatform.Tournament.Server` turns a fixture list into actual
  dispatched races.

  A fixture is either a pair to race (`{name, name}`) or a bye
  (`{:bye, name}`). Per the course rules a bye is a real, scored solo time
  trial, not a free win, so it counts as a fixture like any other.
  """

  @type name :: String.t()
  @type fixture :: {name(), name()} | {:bye, name()}
  @type standing :: %{
          wins: non_neg_integer(),
          score_sum: float(),
          byes: non_neg_integer()
        }

  @doc """
  The next Swiss round's fixtures.

  Pairs by current standing (adjacent ranks), so pairings get tougher as
  strong players climb. That is the point of Swiss over round-robin in a
  fixed, small number of rounds. Never repeats a pairing already in
  `played`; swaps forward to the next-closest rank when a repeat would
  occur. The bye goes to whoever has had the fewest byes so far, ties
  broken by worst standing, since a bye is fairest spent on a round a weak
  scorer was likely to lose anyway. Rotating on "fewest byes" keeps it from
  landing on the same person twice while anyone else is still due one.

  `standings` maps every name in `roster` to its current `t:standing/0`
  (see `WikiRacePlatform.Tournament.Standings`); a name with no entry yet
  is treated as 0 wins, 0 score, 0 byes. `played` is the set of pairs
  already raced, order-independent.
  """
  @spec swiss([name()], %{name() => standing()}, MapSet.t({name(), name()})) :: [
          fixture()
        ]
  def swiss(roster, standings, played) do
    ranked = rank(roster, standings)
    {bye, contenders} = pick_bye(ranked, standings)
    pairs = pair_adjacent(contenders, played)

    case bye do
      nil -> pairs
      name -> pairs ++ [{:bye, name}]
    end
  end

  @doc """
  A full round-robin schedule: every pair races exactly once, spread evenly
  across rounds via the standard "circle" method. Ignores standings
  entirely. Unlike Swiss, the whole schedule is fixed up front, so this
  returns every round at once rather than one round at a time. An odd
  roster gets a rotating bye, same as Swiss.
  """
  @spec round_robin([name()]) :: [[fixture()]]
  def round_robin(roster) do
    padded = if rem(length(roster), 2) == 1, do: roster ++ [nil], else: roster
    n = length(padded)
    half = div(n, 2)

    Enum.map(0..(n - 2), fn round ->
      padded
      |> rotate(round)
      |> Enum.split(half)
      |> then(fn {top, bottom} -> Enum.zip(top, Enum.reverse(bottom)) end)
      |> Enum.map(&to_fixture/1)
    end)
  end

  # Swiss internals

  defp rank(roster, standings) do
    Enum.sort_by(roster, fn name ->
      s = Map.get(standings, name, blank())
      {-s.wins, -s.score_sum, name}
    end)
  end

  defp pick_bye(ranked, _standings) when rem(length(ranked), 2) == 0, do: {nil, ranked}

  defp pick_bye(ranked, standings) do
    min_byes =
      ranked
      |> Enum.map(fn name -> Map.get(standings, name, blank()).byes end)
      |> Enum.min()

    # `ranked` is best-to-worst; filtering preserves that order, so the last
    # of the fewest-byes group is the worst-ranked among them.
    bye =
      ranked
      |> Enum.filter(fn name -> Map.get(standings, name, blank()).byes == min_byes end)
      |> List.last()

    {bye, List.delete(ranked, bye)}
  end

  defp pair_adjacent([], _played), do: []

  defp pair_adjacent([a | rest], played) do
    case Enum.find(rest, fn b -> not played?(played, a, b) end) do
      nil ->
        [b | remaining] = rest
        [{a, b} | pair_adjacent(remaining, played)]

      b ->
        [{a, b} | pair_adjacent(List.delete(rest, b), played)]
    end
  end

  defp played?(played, a, b), do: MapSet.member?(played, normalize_pair(a, b))

  @doc false
  @spec normalize_pair(name(), name()) :: {name(), name()}
  def normalize_pair(a, b), do: if(a <= b, do: {a, b}, else: {b, a})

  defp blank, do: %{wins: 0, score_sum: 0.0, byes: 0}

  # Round-robin internals

  defp rotate(list, 0), do: list

  defp rotate([first | rest], round) do
    len = length(rest)
    shift = rem(round, len)
    {kept, moved} = Enum.split(rest, len - shift)
    [first | moved ++ kept]
  end

  defp to_fixture({nil, b}), do: {:bye, b}
  defp to_fixture({a, nil}), do: {:bye, a}
  defp to_fixture({a, b}), do: {a, b}
end
