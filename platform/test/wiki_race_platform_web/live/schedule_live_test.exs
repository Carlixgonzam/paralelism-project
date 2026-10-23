defmodule WikiRacePlatformWeb.ScheduleLiveTest do
  use WikiRacePlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias WikiRacePlatform.Race.Dispatcher
  alias WikiRacePlatform.Tournament.Server, as: Tournament

  setup do
    start_supervised!(Dispatcher)
    :ok
  end

  test "shows the race day card, the tournament status, and the fixed pair", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/schedule")

    assert html =~ "Race day card"
    assert html =~ "Round" or html =~ "Tournament complete"

    # Tournament.Server is app-wide and shared across the whole test run, so
    # another test file's set_pair call may have already changed it.
    # Assert against whatever's actually current, not a hardcoded pair.
    pair = Tournament.current_pair()
    assert html =~ pair.start
    assert html =~ pair.target
  end
end
