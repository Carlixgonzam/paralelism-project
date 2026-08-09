defmodule WikiRacePlatform.Tournament.StandingsTest do
  use ExUnit.Case, async: true

  alias WikiRacePlatform.Race.Player
  alias WikiRacePlatform.Race.Result
  alias WikiRacePlatform.Tournament.Standings

  defp player(label, opts) do
    %Player{
      node: :"#{label}@host",
      label: label,
      state: Keyword.get(opts, :state, :found),
      best_path: Keyword.get(opts, :path),
      best_elapsed_ms: Keyword.get(opts, :elapsed)
    }
  end

  defp path(length), do: Enum.map(1..length, &"http://kiwix.test/#{&1}")

  defp race(players), do: Result.build(players, :all_settled, 1_000)

  test "no history means no standings and no pairing history" do
    assert Standings.compute([]) == {%{}, MapSet.new()}
  end

  test "a decided race credits the winner one win and the loser none" do
    result =
      race([
        player("A", path: path(3), elapsed: 100),
        player("B", path: path(5), elapsed: 900)
      ])

    {standings, played} = Standings.compute([result])

    assert standings["A"].wins == 1
    assert standings["B"].wins == 0
    assert MapSet.member?(played, {"A", "B"})
  end

  test "a race nobody finished credits no wins to either side" do
    result = race([player("A", state: :exhausted), player("B", state: :down)])

    {standings, _played} = Standings.compute([result])

    assert standings["A"].wins == 0
    assert standings["B"].wins == 0
  end

  test "a solo time trial counts as a bye, not a win, and records no pairing" do
    result = race([player("A", path: path(3), elapsed: 100)])

    {standings, played} = Standings.compute([result])

    assert standings["A"].byes == 1
    assert standings["A"].wins == 0
    assert MapSet.size(played) == 0
  end

  test "wins accumulate across multiple races" do
    r1 =
      race([
        player("A", path: path(3), elapsed: 100),
        player("B", path: path(5), elapsed: 900)
      ])

    r2 =
      race([
        player("A", path: path(2), elapsed: 50),
        player("C", path: path(6), elapsed: 900)
      ])

    {standings, played} = Standings.compute([r1, r2])

    assert standings["A"].wins == 2
    assert standings["B"].wins == 0
    assert standings["C"].wins == 0
    assert MapSet.member?(played, {"A", "B"})
    assert MapSet.member?(played, {"A", "C"})
  end

  test "score sums only real scores, treating a non-finisher's nil score as zero" do
    result =
      race([player("A", path: path(3), elapsed: 100), player("B", state: :exhausted)])

    {standings, _played} = Standings.compute([result])

    assert standings["A"].score_sum > 0.0
    assert standings["B"].score_sum == 0.0
  end

  test "a result persisted before the score field existed doesn't crash, score sums as zero" do
    result =
      race([
        player("A", path: path(3), elapsed: 100),
        player("B", path: path(5), elapsed: 900)
      ])

    # Simulates old data read back from disk: `Race.Result.build/4` always
    # sets `:score` today, but a struct decoded from a file written before
    # the scoring redesign lacks the key entirely. `entry.score` dot-access
    # would raise; `Map.get/2` must not.
    stale_entry = Map.delete(hd(result.ranking), :score)
    stale_result = %{result | ranking: [stale_entry, List.last(result.ranking)]}

    {standings, _played} = Standings.compute([stale_result])

    assert standings["A"].wins == 1
    assert standings["A"].score_sum == 0.0
  end

  test "games counts every participation, wins, losses and byes alike" do
    r1 =
      race([
        player("A", path: path(3), elapsed: 100),
        player("B", path: path(5), elapsed: 900)
      ])

    r2 = race([player("A", path: path(2), elapsed: 50)])

    {standings, _played} = Standings.compute([r1, r2])

    assert standings["A"].games == 2
    assert standings["B"].games == 1
  end

  test "a pairing is normalized regardless of which side is listed first" do
    result =
      race([
        player("B", path: path(5), elapsed: 900),
        player("A", path: path(3), elapsed: 100)
      ])

    {_standings, played} = Standings.compute([result])

    assert MapSet.member?(played, {"A", "B"})
  end
end
