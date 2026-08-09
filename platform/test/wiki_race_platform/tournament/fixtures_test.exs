defmodule WikiRacePlatform.Tournament.FixturesTest do
  use ExUnit.Case, async: true

  alias WikiRacePlatform.Tournament.Fixtures

  @roster ["A", "B", "C", "D", "E", "F", "G"]

  defp standing(wins, score_sum \\ 0.0, byes \\ 0) do
    %{wins: wins, score_sum: score_sum, byes: byes}
  end

  defp pairs_only(fixtures), do: Enum.reject(fixtures, &match?({:bye, _}, &1))

  defp bye_of(fixtures) do
    Enum.find_value(fixtures, fn
      {:bye, name} -> name
      _pair -> nil
    end)
  end

  describe "swiss/3" do
    test "round one, with no history, pairs everyone and gives exactly one bye" do
      fixtures = Fixtures.swiss(@roster, %{}, MapSet.new())

      assert length(pairs_only(fixtures)) == 3
      assert Enum.count(fixtures, &match?({:bye, _}, &1)) == 1

      raced =
        fixtures
        |> Enum.flat_map(fn
          {:bye, name} -> [name]
          {a, b} -> [a, b]
        end)
        |> Enum.sort()

      assert raced == Enum.sort(@roster)
    end

    test "an even roster gets no bye at all" do
      fixtures = Fixtures.swiss(["A", "B", "C", "D"], %{}, MapSet.new())

      assert length(fixtures) == 2
      refute Enum.any?(fixtures, &match?({:bye, _}, &1))
    end

    test "pairs by standing: strongest with strongest, weakest with weakest" do
      standings = %{
        "A" => standing(3),
        "B" => standing(3),
        "C" => standing(2),
        "D" => standing(2),
        "E" => standing(1),
        "F" => standing(1),
        "G" => standing(0)
      }

      fixtures = Fixtures.swiss(@roster, standings, MapSet.new())

      pairs =
        pairs_only(fixtures)
        |> Enum.map(&Fixtures.normalize_pair(elem(&1, 0), elem(&1, 1)))

      # G is worst (0 wins) and nobody has had a bye yet, so G sits out;
      # the rest pair strictly adjacent by rank: (A,B) (C,D) (E,F).
      assert bye_of(fixtures) == "G"
      assert Enum.sort(pairs) == Enum.sort([{"A", "B"}, {"C", "D"}, {"E", "F"}])
    end

    test "a repeat pairing is avoided by swapping to the next-closest rank" do
      standings = %{
        "A" => standing(3),
        "B" => standing(3),
        "C" => standing(2),
        "D" => standing(2),
        "E" => standing(1),
        "F" => standing(1),
        "G" => standing(0, 0.0, 1)
      }

      # A already played B, so the naive adjacent pairing would repeat it.
      played = MapSet.new([Fixtures.normalize_pair("A", "B")])

      fixtures = Fixtures.swiss(@roster, standings, played)

      pairs =
        pairs_only(fixtures)
        |> Enum.map(&Fixtures.normalize_pair(elem(&1, 0), elem(&1, 1)))

      # G already had a bye, so the bye rotates to whoever's next fewest.
      # Everyone else is at 0, tied, so the worst-ranked of those (F) sits
      # out instead.
      assert bye_of(fixtures) == "F"
      refute {"A", "B"} in pairs
      assert length(pairs) == 3
    end

    test "the bye rotates to whoever has had the fewest byes, not just the weakest" do
      standings = %{
        "A" => standing(0, 0.0, 1),
        "B" => standing(0, 0.0, 1),
        "C" => standing(0, 0.0, 1),
        "D" => standing(0),
        "E" => standing(0),
        "F" => standing(0),
        "G" => standing(0)
      }

      fixtures = Fixtures.swiss(@roster, standings, MapSet.new())

      # A, B, C already had a bye; among D/E/F/G (0 byes each, tied on
      # wins), the worst-ranked (last alphabetically, our tiebreak) sits out.
      assert bye_of(fixtures) == "G"
    end
  end

  describe "round_robin/1" do
    test "every pair races exactly once, for an even roster" do
      roster = ["A", "B", "C", "D"]
      rounds = Fixtures.round_robin(roster)

      assert length(rounds) == 3

      all_pairs =
        rounds
        |> List.flatten()
        |> Enum.map(&Fixtures.normalize_pair(elem(&1, 0), elem(&1, 1)))

      expected =
        for a <- roster, b <- roster, a < b, do: {a, b}

      assert Enum.sort(all_pairs) == Enum.sort(expected)
      assert length(all_pairs) == length(Enum.uniq(all_pairs))
    end

    test "an odd roster gets a rotating bye each round, covering everyone" do
      roster = ["A", "B", "C", "D", "E"]
      rounds = Fixtures.round_robin(roster)

      assert length(rounds) == 5

      byes =
        rounds
        |> List.flatten()
        |> Enum.filter(&match?({:bye, _}, &1))
        |> Enum.map(fn {:bye, name} -> name end)

      assert length(byes) == 5
      assert Enum.sort(Enum.uniq(byes)) == Enum.sort(roster)

      all_pairs =
        rounds
        |> List.flatten()
        |> Enum.reject(&match?({:bye, _}, &1))
        |> Enum.map(&Fixtures.normalize_pair(elem(&1, 0), elem(&1, 1)))

      expected = for a <- roster, b <- roster, a < b, do: {a, b}
      assert Enum.sort(all_pairs) == Enum.sort(expected)
    end
  end
end
