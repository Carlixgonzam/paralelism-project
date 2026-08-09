defmodule WikiRacePlatform.Tournament.ServerTest do
  # Not async: races through a real Dispatcher, which claims a :global name.
  use ExUnit.Case, async: false

  alias WikiRacePlatform.Race.Dispatcher
  alias WikiRacePlatform.Race.Player
  alias WikiRacePlatform.Race.Result
  alias WikiRacePlatform.Tournament.Server
  alias WikiRacePlatform.Tournament.Store

  @roster ["A", "B", "C", "D"]

  defp unique_name(prefix), do: :"#{prefix}_#{System.unique_integer([:positive])}"

  defp start_store do
    name = unique_name("store")

    path =
      Path.join(
        System.tmp_dir!(),
        "tournament_server_test_#{System.unique_integer([:positive])}.terms"
      )

    on_exit(fn -> File.rm(path) end)

    spec = %{id: name, start: {Store, :start_link, [[path: path, name: name]]}}
    start_supervised!(spec)
    name
  end

  defp start_tournament(opts) do
    name = unique_name("tournament")
    spec = %{id: name, start: {Server, :start_link, [Keyword.put(opts, :name, name)]}}
    start_supervised!(spec)
    name
  end

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

  defp record_win(store, winner, loser) do
    result =
      Result.build(
        [
          player(winner, path: path(3), elapsed: 100),
          player(loser, path: path(5), elapsed: 900)
        ],
        :all_settled,
        1_000
      )

    Store.append(result, store)
  end

  defp zeroed_standings(roster) do
    Map.new(roster, &{&1, %{wins: 0, score_sum: 0.0, byes: 0, games: 0}})
  end

  test "with no history, the first round pairs the whole roster and gives one bye for an odd count" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 3)

    assert Server.next_fixture(tournament) in [{"A", "B"}, {"C", "D"}]
    assert Server.standings(tournament) == zeroed_standings(@roster)
  end

  test "upcoming returns the queued fixtures in dispatch order, capped at count" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 3)

    assert [first, second] = Server.upcoming(3, tournament)
    assert first == Server.next_fixture(tournament)
    assert Server.upcoming(1, tournament) == [first]
    assert Server.upcoming(2, tournament) == [first, second]
  end

  test "an odd roster is handled without crashing, producing a valid fixture" do
    store = start_store()
    tournament = start_tournament(roster: @roster ++ ["E"], store: store, total_rounds: 3)

    assert Server.next_fixture(tournament) != nil
  end

  test "refresh recomputes standings and advances the queue after new history lands" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 3)

    first_fixture = Server.next_fixture(tournament)
    assert {a, b} = first_fixture

    record_win(store, a, b)
    Server.refresh(tournament)

    standings = Server.standings(tournament)
    assert standings[a].wins == 1
    assert standings[b].wins == 0

    # The queue advances to the round's other fixture, not back to the one
    # just played.
    refute Server.next_fixture(tournament) == first_fixture
  end

  test "races with labels outside the roster don't count toward this tournament's progress" do
    store = start_store()

    # A practice/demo race using arbitrary labels, unrelated to the roster.
    # `Store` is a general results log shared by every race the platform
    # ever runs, not scoped to one tournament.
    record_win(store, "practice1", "practice2")

    tournament = start_tournament(roster: @roster, store: store, total_rounds: 3)

    # Still round one, fixture one. The unrelated race isn't miscounted as
    # progress, and doesn't show up in these standings either.
    assert Server.next_fixture(tournament) in [{"A", "B"}, {"C", "D"}]
    assert Server.standings(tournament) == zeroed_standings(@roster)
  end

  test "the tournament ends after total_rounds, leaving no next fixture" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 1)

    Enum.each(1..2, fn _ ->
      {a, b} = Server.next_fixture(tournament)
      record_win(store, a, b)
      Server.refresh(tournament)
    end)

    assert Server.next_fixture(tournament) == nil
  end

  test "start_next! builds a config and dispatches it through the given dispatcher" do
    dispatcher = unique_name("dispatcher")

    start_supervised!(%{
      id: dispatcher,
      start: {Dispatcher, :start_link, [[name: dispatcher]]}
    })

    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, dispatcher: dispatcher)

    {a, b} = Server.next_fixture(tournament)

    # One real (but crawler-less) node and one unreachable node is enough to
    # prove start_next! actually reaches the dispatcher and gets a real
    # discovery attempt back, without needing a working crawler for this.
    node_mapping = %{a => node(), b => :ghost@nowhere}

    assert {:error, message} = Server.start_next!(node_mapping, tournament)
    assert message =~ "not reachable"
  end

  test "start_next! reports a missing node mapping instead of guessing" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store)

    {a, _b} = Server.next_fixture(tournament)

    assert {:error, message} = Server.start_next!(%{a => node()}, tournament)
    assert message =~ "no node given"
  end

  test "no fixture queued is a clean error, not a crash" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 0)

    assert Server.next_fixture(tournament) == nil
    assert {:error, "no fixture is queued"} = Server.start_next!(%{}, tournament)
  end

  test "played_pairs starts empty and records each pairing that actually raced" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 3)

    assert Server.played_pairs(tournament) == MapSet.new()

    {a, b} = Server.next_fixture(tournament)
    record_win(store, a, b)
    Server.refresh(tournament)

    assert MapSet.member?(
             Server.played_pairs(tournament),
             Enum.sort([a, b]) |> List.to_tuple()
           )
  end

  test "progress reports round one of the configured total before anything has run" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 3)

    assert Server.progress(tournament) == %{round: 1, total_rounds: 3, complete: false}
  end

  test "progress advances a round only once every fixture in it has a result" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 2)

    {a, b} = Server.next_fixture(tournament)
    record_win(store, a, b)
    Server.refresh(tournament)

    assert Server.progress(tournament).round == 1

    {c, d} = Server.next_fixture(tournament)
    record_win(store, c, d)
    Server.refresh(tournament)

    assert Server.progress(tournament) == %{round: 2, total_rounds: 2, complete: false}
  end

  test "progress reports complete once total_rounds worth of history has landed" do
    store = start_store()
    tournament = start_tournament(roster: @roster, store: store, total_rounds: 1)

    Enum.each(1..2, fn _ ->
      {a, b} = Server.next_fixture(tournament)
      record_win(store, a, b)
      Server.refresh(tournament)
    end)

    assert Server.progress(tournament) == %{round: 1, total_rounds: 1, complete: true}
  end

  describe "round-pair progression" do
    @round_pairs [
      {"Round1 Start", "Round1 Target"},
      {"Round2 Start", "Round2 Target"}
    ]

    defp finish_round(store, tournament) do
      Enum.each(1..2, fn _ ->
        {a, b} = Server.next_fixture(tournament)
        record_win(store, a, b)
        Server.refresh(tournament)
      end)
    end

    test "applies the next round's configured pair as soon as the round advances" do
      store = start_store()

      tournament =
        start_tournament(
          roster: @roster,
          store: store,
          total_rounds: 2,
          round_pairs: @round_pairs
        )

      assert Server.current_pair(tournament) == %{
               start: "Round1 Start",
               target: "Round1 Target",
               note: ""
             }

      refute Server.pair_overridden?(tournament)

      finish_round(store, tournament)

      assert Server.progress(tournament).round == 2

      assert Server.current_pair(tournament) == %{
               start: "Round2 Start",
               target: "Round2 Target",
               note: ""
             }

      refute Server.pair_overridden?(tournament)
    end

    test "a manual override only lasts for the round it was set in" do
      store = start_store()

      tournament =
        start_tournament(
          roster: @roster,
          store: store,
          total_rounds: 2,
          round_pairs: @round_pairs
        )

      custom = %{start: "Custom Start", target: "Custom Target", note: ""}
      :ok = Server.set_pair(custom, tournament)
      assert Server.current_pair(tournament) == custom
      assert Server.pair_overridden?(tournament)

      {a, b} = Server.next_fixture(tournament)
      record_win(store, a, b)
      Server.refresh(tournament)

      # Only one of round 1's two fixtures has a result, still round 1,
      # override still holds.
      assert Server.progress(tournament).round == 1
      assert Server.current_pair(tournament) == custom
      assert Server.pair_overridden?(tournament)

      {c, d} = Server.next_fixture(tournament)
      record_win(store, c, d)
      Server.refresh(tournament)

      # Round 2 now. The configured progression takes back over.
      assert Server.progress(tournament).round == 2

      assert Server.current_pair(tournament) == %{
               start: "Round2 Start",
               target: "Round2 Target",
               note: ""
             }

      refute Server.pair_overridden?(tournament)
    end

    test "with no round_pairs configured, every round falls back to the curated pool's first pair" do
      store = start_store()
      tournament = start_tournament(roster: @roster, store: store, total_rounds: 2)

      [first_pair | _] = WikiRacePlatform.Articles.pairs()
      assert Server.current_pair(tournament) == first_pair

      finish_round(store, tournament)

      assert Server.progress(tournament).round == 2
      assert Server.current_pair(tournament) == first_pair
    end
  end
end
