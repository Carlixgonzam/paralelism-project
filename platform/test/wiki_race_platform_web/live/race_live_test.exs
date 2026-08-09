defmodule WikiRacePlatformWeb.RaceLiveTest do
  use WikiRacePlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias WikiRacePlatform.FakeCrawler
  alias WikiRacePlatform.Race
  alias WikiRacePlatform.Race.Config
  alias WikiRacePlatform.Race.Dispatcher

  @base "http://kiwix.test/content/wiki"
  @start "#{@base}/Elixir"
  @target "#{@base}/Erlang"
  @good_path [@start, "#{@base}/BEAM", @target]

  setup do
    Application.put_env(:wiki_race_platform, :req_options,
      plug: fn conn ->
        body =
          case conn.request_path do
            "/content/wiki/Elixir" -> ~s(<a href="BEAM">beam</a>)
            "/content/wiki/BEAM" -> ~s(<a href="Erlang">erlang</a>)
            _ -> ""
          end

        Req.Test.html(conn, body)
      end
    )

    start_supervised!(Dispatcher)

    on_exit(fn ->
      Application.delete_env(:wiki_race_platform, :req_options)
      Application.delete_env(:wiki_race_platform, :fake_crawler)
    end)

    :ok
  end

  defp start_race(steps, time_limit_ms \\ 5_000) do
    FakeCrawler.script(steps)

    {:ok, config} =
      Config.new(
        start_url: @start,
        target_url: @target,
        time_limit_ms: time_limit_ms,
        poll_interval_ms: 40,
        players: [%{node: node(), label: "Group A", module: FakeCrawler}]
      )

    Dispatcher.start_race(config)
  end

  test "shows an invitation to set up a race when nothing is running", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "NO RACE RUNNING" or html =~ "TOURNAMENT COMPLETE"
    assert html =~ "check the schedule tab"
  end

  test "shows the article pair, both crawlers, and live score metrics once a race starts",
       %{
         conn: conn
       } do
    {:ok, live, _html} = live(conn, ~p"/")

    :ok = Race.subscribe()
    {:ok, _snapshot} = start_race(status_after_ms: {20, [frontier_size: 42]})
    assert_receive {:race_update, %{status: :running}}, 2_000

    html = render(live)
    assert html =~ "Elixir"
    assert html =~ "Erlang"
    assert html =~ "Group A"
    assert html =~ "Scheduler use"
    assert html =~ "Time"
    refute html =~ "Score"
  end

  test "shows the verified path and highlights the winner when the race ends", %{
    conn: conn
  } do
    {:ok, live, _html} = live(conn, ~p"/")

    :ok = Race.subscribe()
    {:ok, _snapshot} = start_race(report_after_ms: {20, @good_path})
    await_finish()

    html = render(live)
    # No separate result box. The panel itself carries everything worth
    # showing: the verified path, the final state badge, and the winner
    # highlight.
    assert html =~ "found"
    assert html =~ "BEAM"
    assert html =~ "bg-comic-yellow/10"
    assert html =~ "Score"
  end

  defp await_finish do
    assert_receive {:race_update, snapshot}, 8_000
    if snapshot.status != :finished, do: await_finish(), else: snapshot
  end
end
