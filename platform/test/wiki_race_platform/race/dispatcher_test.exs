defmodule WikiRacePlatform.Race.DispatcherTest do
  # Not async: the dispatcher claims a `:global` name and the stubbed Kiwix
  # lives in application env, both of which are node-wide.
  use ExUnit.Case, async: false

  alias WikiRace.Harness
  alias WikiRacePlatform.FakeCrawler
  alias WikiRacePlatform.Race
  alias WikiRacePlatform.Race.Config
  alias WikiRacePlatform.Race.Dispatcher
  alias WikiRacePlatform.Tournament.Store

  @base "http://kiwix.test/content/wiki"
  @start "#{@base}/Elixir"
  @target "#{@base}/Erlang"
  @good_path [@start, "#{@base}/BEAM", @target]

  @pages %{
    "/content/wiki/Elixir" => ~s(<a href="BEAM">beam</a><a href="Ruby">ruby</a>),
    "/content/wiki/BEAM" => ~s(<a href="Erlang">erlang</a>),
    "/content/wiki/Ruby" => ~s(<a href="Elixir">back</a>),
    "/content/wiki/Erlang" => ~s(<a href="BEAM">beam</a>)
  }

  setup do
    Application.put_env(:wiki_race_platform, :req_options,
      plug: fn conn ->
        case Map.fetch(@pages, conn.request_path) do
          {:ok, body} -> Req.Test.html(conn, body)
          :error -> Plug.Conn.send_resp(conn, 404, "not found")
        end
      end
    )

    start_supervised!(Dispatcher)
    :ok = Race.subscribe()

    on_exit(fn ->
      Application.delete_env(:wiki_race_platform, :req_options)
      Application.delete_env(:wiki_race_platform, :fake_crawler)
    end)

    :ok
  end

  defp config(overrides \\ []) do
    {:ok, config} =
      [
        start_url: @start,
        target_url: @target,
        time_limit_ms: Keyword.get(overrides, :time_limit_ms, 5_000),
        poll_interval_ms: 40,
        players: [%{node: node(), label: "Group A", module: FakeCrawler}]
      ]
      |> Config.new()

    config
  end

  # Race updates arrive on every poll, so walk them until the race is over.
  defp await_finish(timeout \\ 8_000) do
    assert_receive {:race_update, snapshot}, timeout

    case snapshot.status do
      :finished -> snapshot
      _ -> await_finish(timeout)
    end
  end

  defp only_player(snapshot), do: hd(snapshot.players)

  test "the harness answers to the name the student client looks up" do
    assert Dispatcher.global_name() == Harness.registered_name()
    assert :global.whereis_name(Harness.registered_name()) == Process.whereis(Dispatcher)
  end

  test "a report from a node outside any race is logged, not silently dropped" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(Process.whereis(Dispatcher), {:path_found, self(), @good_path})
        # Let the async handle_info land before the capture window closes.
        :sys.get_state(Dispatcher)
      end)

    assert log =~ "inbound path_found from #{inspect(node())}, which is not in any race"
  end

  test "a hand-crafted message claiming a bare node atom (not a pid) is ignored, not routed" do
    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    # Bypassing WikiRace.Harness.report/1 entirely and sending the old
    # node()-based shape by hand. This is exactly the spoofing vector a
    # bare-atom wire format allowed: claiming to be a node you aren't.
    harness_pid = :global.whereis_name(Harness.registered_name())
    send(harness_pid, {:path_found, node(), @good_path})

    refute_receive {:race_update, %{status: :finished}}, 200
  end

  test "a verified report wins the race and ends it early" do
    FakeCrawler.script(report_after_ms: {50, @good_path})

    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    snapshot = await_finish()

    assert snapshot.result.ended_by == :all_settled
    assert snapshot.result.winner.label == "Group A"
    assert snapshot.result.winner.path == @good_path
    assert only_player(snapshot).state == :found
    assert only_player(snapshot).best_elapsed_ms >= 0
  end

  test "polling fills in the dashboard fields between reports" do
    FakeCrawler.script(status_after_ms: {10, [frontier_size: 42, visited_count: 99]})

    assert {:ok, _snapshot} = Dispatcher.start_race(config(time_limit_ms: 400))

    snapshot = await_finish()

    assert only_player(snapshot).status.frontier_size == 42
    assert only_player(snapshot).status.visited_count == 99
  end

  test "a path the crawler never really walked is rejected" do
    bogus = [@start, "#{@base}/Ruby", @target]
    FakeCrawler.script(report_after_ms: {30, bogus}, exhaust_after_ms: 200)

    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    snapshot = await_finish()
    player = only_player(snapshot)

    assert player.state == :exhausted
    assert player.best_path == nil
    assert [{^bogus, reason}] = player.rejected
    assert reason =~ "does not link to"
    assert snapshot.result.winner == nil
  end

  test "a structurally wrong path is rejected without any HTTP request" do
    bogus = ["#{@base}/Ruby", @target]
    FakeCrawler.script(report_after_ms: {30, bogus}, exhaust_after_ms: 200)

    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    player = await_finish() |> only_player()

    assert [{^bogus, reason}] = player.rejected
    assert reason =~ "does not start"
  end

  test "scheduler utilization survives past the RPC call that enables it" do
    # Regression test: `:erlang.system_flag(:scheduler_wall_time, true)`
    # only stays on for as long as *some* process that turned it on is
    # still alive. A plain `:rpc.call` runs on a throwaway worker that dies
    # the instant the call returns, so naively enabling it that way
    # silently turns it back off before anything ever reads it, and every
    # race's utilization term reads back as 0.0 forever, deterministically,
    # every time. `Race.Instance` has to leave a detached process behind on
    # the player node to hold it on. After a race, the flag must still
    # read as enabled from an entirely fresh call, not just have been
    # enabled momentarily during the race.
    FakeCrawler.script(report_after_ms: {20, @good_path})

    assert {:ok, _snapshot} = Dispatcher.start_race(config())
    snapshot = await_finish()

    assert is_list(:erlang.statistics(:scheduler_wall_time_all))
    assert Enum.all?(snapshot.result.ranking, &is_float(&1.utilization))
  end

  test "a path shown only in status/1 is still verified and scored" do
    FakeCrawler.script(status_after_ms: {10, [state: :found, path: @good_path]})

    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    snapshot = await_finish()

    assert snapshot.result.winner.path == @good_path
  end

  test "reporting exhausted settles the crawler with no winner" do
    FakeCrawler.script(exhaust_after_ms: 30)

    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    snapshot = await_finish()

    assert only_player(snapshot).state == :exhausted
    assert snapshot.result.ended_by == :all_settled
    assert snapshot.result.winner == nil
  end

  test "a crawler that crashes is recorded as down and the race moves on" do
    FakeCrawler.script(crash_after_ms: 30)

    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    player = await_finish() |> only_player()

    assert player.state == :down
    assert player.error =~ "went down"
  end

  test "the time limit ends the race and kills the crawler" do
    FakeCrawler.script([])

    assert {:ok, started} = Dispatcher.start_race(config(time_limit_ms: 250))
    pid = hd(started.players).pid
    assert Process.alive?(pid)

    snapshot = await_finish()

    assert snapshot.result.ended_by == :time_limit
    refute Process.alive?(pid)
  end

  test "a crawler that refuses to start fails the race instead of hiding it" do
    FakeCrawler.script(on_start: {:error, :no_workers})

    assert {:error, message} = Dispatcher.start_race(config())
    assert message =~ "start/2 refused"
    assert Race.snapshot().status == :idle
  end

  test "a second race for a different node is evaluated on its own, not refused outright" do
    FakeCrawler.script([])

    {:ok, config_b} =
      Config.new(
        start_url: @start,
        target_url: @target,
        time_limit_ms: 5_000,
        poll_interval_ms: 40,
        players: [%{node: :ghost2@nowhere, label: "Group B", module: nil}]
      )

    assert {:ok, snapshot_a} = Dispatcher.start_race(config())
    assert {:error, message} = Dispatcher.start_race(config_b)

    # config_b's node is unreachable, so it fails on discovery, not on
    # "already racing". This proves the dispatcher's guard is per-node (does
    # this fixture's nodes overlap an active race?), not "is anything
    # running at all," which is what actually makes non-overlapping races
    # possible at once.
    refute message =~ "already racing"
    assert Dispatcher.list_active() == [snapshot_a.race_id]

    Dispatcher.abort(snapshot_a.race_id)
  end

  test "starting a race with a node already racing is refused" do
    FakeCrawler.script([])

    assert {:ok, snapshot} = Dispatcher.start_race(config())
    assert {:error, message} = Dispatcher.start_race(config())
    assert message =~ "already racing"

    Dispatcher.abort(snapshot.race_id)
  end

  test "aborting with no race running is an error, not a crash" do
    assert {:error, "no race is running"} = Race.abort()
    assert {:error, "no such race"} = Dispatcher.abort(make_ref())
  end

  test "an unknown crawler module is reported before anything starts" do
    {:ok, config} =
      Config.new(
        start_url: @start,
        target_url: @target,
        time_limit_ms: 1_000,
        poll_interval_ms: 40,
        players: [%{node: :ghost@nowhere, label: "Ghost", module: nil}]
      )

    assert {:error, message} = Dispatcher.start_race(config)
    assert message =~ "not reachable"
  end

  test "a finished race is appended to the tournament store" do
    FakeCrawler.script(report_after_ms: {50, @good_path})

    assert {:ok, _snapshot} = Dispatcher.start_race(config())

    snapshot = await_finish()

    entry = List.last(Store.list())
    assert entry.result == snapshot.result
  end

  test "the store append still lands when :web_node is explicitly configured" do
    # The harness (where Instance runs) can run on its own node, separate
    # from Store's. Instance then addresses the append as `{Store, web_node}`
    # instead of a plain local call. This node happens to equal `node()`
    # here (no real second node in this test), but setting the config
    # explicitly, instead of leaving it unset, still exercises the
    # {name, node} call form a real split relies on.
    Application.put_env(:wiki_race_platform, :web_node, node())
    on_exit(fn -> Application.delete_env(:wiki_race_platform, :web_node) end)

    FakeCrawler.script(report_after_ms: {50, @good_path})
    assert {:ok, _snapshot} = Dispatcher.start_race(config())
    snapshot = await_finish()

    entry = List.last(Store.list())
    assert entry.result == snapshot.result
  end
end
