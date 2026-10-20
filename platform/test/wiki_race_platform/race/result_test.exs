defmodule WikiRacePlatform.Race.ResultTest do
  # Not async: one test mutates the global :scoring app env.
  use ExUnit.Case, async: false

  alias WikiRacePlatform.Race.Player
  alias WikiRacePlatform.Race.Result

  defp player(label, opts) do
    %Player{
      node: :"#{label}@host",
      label: label,
      state: Keyword.get(opts, :state, :found),
      best_path: Keyword.get(opts, :path),
      best_elapsed_ms: Keyword.get(opts, :elapsed),
      first_elapsed_ms: Keyword.get(opts, :first, Keyword.get(opts, :elapsed)),
      rejected: Keyword.get(opts, :rejected, [])
    }
  end

  defp path(length), do: Enum.map(1..length, &"http://kiwix.test/#{&1}")

  test "with equal times, the shorter path wins" do
    players = [
      player("A", path: path(5), elapsed: 500),
      player("B", path: path(3), elapsed: 500)
    ]

    result = Result.build(players, :all_settled, 1_000)

    assert result.winner.label == "B"
    assert result.decided_by == :score
    assert Enum.map(result.ranking, & &1.label) == ["B", "A"]
  end

  test "the first path wins over a shorter one that arrived later" do
    players = [
      player("A", path: path(5), elapsed: 100),
      player("B", path: path(3), elapsed: 900)
    ]

    result = Result.build(players, :all_settled, 1_000)

    # A: 0.4 + 0.15 (first) + 0.2*(3/5) + 0.15*1.0
    # B: 0.4 + 0.0 + 0.2*1.0 + 0.15*(100/900)
    scored = Map.new(result.ranking, &{&1.label, &1.score})
    assert_in_delta scored["A"], 0.4 + 0.15 + 0.12 + 0.15, 0.0001
    assert_in_delta scored["B"], 0.4 + 0.2 + 0.15 * 100 / 900, 0.0001
    assert result.winner.label == "A"
  end

  test "first goes to the earliest verified path, not to the best one" do
    players = [
      player("A", path: path(3), elapsed: 900, first: 100),
      player("B", path: path(3), elapsed: 400)
    ]

    result = Result.build(players, :all_settled, 1_000)

    # A: 0.4 + 0.15 (first) + 0.2 + 0.15*(400/900)
    # B: 0.4 + 0.0 + 0.2 + 0.15*1.0
    scored = Map.new(result.ranking, &{&1.label, &1.score})
    assert_in_delta scored["A"], 0.4 + 0.15 + 0.2 + 0.15 * 400 / 900, 0.0001
    assert_in_delta scored["B"], 0.4 + 0.2 + 0.15, 0.0001
  end

  test "a crawler that reported a false path cannot take first from an honest one" do
    players = [
      player("A", path: path(3), elapsed: 100, rejected: [{path(2), "no such link"}]),
      player("B", path: path(3), elapsed: 400)
    ]

    result = Result.build(players, :all_settled, 1_000)

    scored = Map.new(result.ranking, &{&1.label, &1.score})
    assert scored["A"] == -1.0
    # B: 0.4 + 0.15 (first among honest crawlers) + 0.2 + 0.15*(100/400)
    assert_in_delta scored["B"], 0.4 + 0.15 + 0.2 + 0.15 * 0.25, 0.0001
  end

  test "equal path lengths are broken by wall-clock time" do
    players = [
      player("A", path: path(4), elapsed: 800),
      player("B", path: path(4), elapsed: 250)
    ]

    result = Result.build(players, :all_settled, 1_000)

    assert result.winner.label == "B"
    assert result.decided_by == :score
    assert Result.summary(result) =~ "wins with a path"
  end

  test "the score is a blend of found/first/hops/time/utilization, higher wins" do
    players = [
      player("A", path: path(4), elapsed: 800),
      player("B", path: path(4), elapsed: 200)
    ]

    utilization = %{:A@host => 0.2, :B@host => 0.8}
    result = Result.build(players, :all_settled, 1_000, utilization)

    [winner, loser] = result.ranking
    assert winner.label == "B"
    # B: 0.4 (found) + 0.15 (first) + 0.2 (best hops) + 0.15 (best time) + 0.1*0.8 (util)
    assert_in_delta winner.score, 0.4 + 0.15 + 0.2 + 0.15 + 0.08, 0.0001
    # A: 0.4 (found) + 0.0 (not first) + 0.2 (same hops) + 0.15*(200/800) + 0.1*0.2 (util)
    assert_in_delta loser.score, 0.4 + 0.2 + 0.15 * 0.25 + 0.1 * 0.2, 0.0001
  end

  test "score weights come from config, not a hardcoded pass-through" do
    original = Application.fetch_env!(:wiki_race_platform, :scoring)

    Application.put_env(:wiki_race_platform, :scoring,
      weights: [found: 0.0, first: 0.0, hops: 0.0, time: 0.0, utilization: 1.0]
    )

    on_exit(fn -> Application.put_env(:wiki_race_platform, :scoring, original) end)

    players = [
      player("A", path: path(4), elapsed: 800),
      player("B", path: path(4), elapsed: 200)
    ]

    utilization = %{:A@host => 0.4, :B@host => 0.9}
    result = Result.build(players, :all_settled, 1_000, utilization)

    scored = Map.new(result.ranking, &{&1.label, &1.score})
    assert_in_delta scored["A"], 0.4, 0.0001
    assert_in_delta scored["B"], 0.9, 0.0001
  end

  test "finding any path beats finding none" do
    players = [
      player("A", state: :exhausted),
      player("B", path: path(9), elapsed: 4_000)
    ]

    result = Result.build(players, :all_settled, 5_000)

    assert result.winner.label == "B"
    assert result.decided_by == :only_finisher
    assert Result.summary(result) =~ "the only crawler"
  end

  test "a crawler that went down still ranks, just below any finisher" do
    players = [
      player("A", state: :down, path: nil),
      player("B", path: path(2), elapsed: 30)
    ]

    result = Result.build(players, :time_limit, 60_000)

    assert Enum.map(result.ranking, & &1.label) == ["B", "A"]
    assert List.last(result.ranking).state == :down
  end

  test "nobody finishing leaves the race without a winner, decided by utilization alone" do
    players = [player("A", state: :exhausted), player("B", state: :down)]
    utilization = %{:A@host => 0.1, :B@host => 0.6}

    result = Result.build(players, :time_limit, 60_000, utilization)

    assert result.winner == nil
    assert result.decided_by == :nobody_finished
    assert Result.summary(result) == "No crawler found a valid path."
    assert Enum.map(result.ranking, & &1.label) == ["B", "A"]
  end

  test "reporting a path that fails verification scores -1.0, no matter the other metrics" do
    players = [
      # A high hop count and slow time would normally hurt B's score, and a
      # low utilization wouldn't help it either. None of that should
      # matter once it's lied about a path.
      player("A", path: path(2), elapsed: 50, rejected: [{path(2), "does not link to"}]),
      player("B", path: path(9), elapsed: 4_000)
    ]

    utilization = %{A@host: 0.9, B@host: 0.1}
    result = Result.build(players, :all_settled, 5_000, utilization)

    scored = Map.new(result.ranking, &{&1.label, &1.score})
    assert scored["A"] == -1.0
    assert result.winner.label == "B"
  end

  test "a crawler is never the winner after lying, even if it also found a real path" do
    players = [
      player("A",
        path: path(3),
        elapsed: 100,
        rejected: [{["bogus"], "does not start with the start URL"}]
      ),
      player("B", state: :exhausted)
    ]

    result = Result.build(players, :all_settled, 5_000)

    assert result.winner == nil
    assert result.decided_by == :nobody_finished
  end

  test "the false-path penalty is called out by name in the summary" do
    players = [
      player("A", path: path(2), elapsed: 50, rejected: [{path(2), "does not link to"}]),
      player("B", path: path(9), elapsed: 4_000)
    ]

    result = Result.build(players, :all_settled, 5_000)
    summary = Result.summary(result)

    assert summary =~ "B wins"
    assert summary =~ "A reported a path that failed verification"
    assert summary =~ "-1.0"
  end

  test "old results persisted before the false-path penalty existed don't crash" do
    result = Result.build([player("A", path: path(3), elapsed: 100)], :all_settled, 1_000)
    stale_entry = Map.delete(hd(result.ranking), :rejected?)
    stale_result = %{result | ranking: [stale_entry]}

    assert Result.summary(stale_result) =~ "wins"
  end

  test "the reason the race ended is carried through" do
    result = Result.build([player("A", state: :exhausted)], :aborted, 12)

    assert result.ended_by == :aborted
    assert result.duration_ms == 12
  end
end
