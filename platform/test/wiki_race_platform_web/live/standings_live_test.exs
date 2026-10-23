defmodule WikiRacePlatformWeb.StandingsLiveTest do
  use WikiRacePlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias WikiRacePlatform.Tournament.Server, as: Tournament

  test "shows every configured roster group, played or not", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/standings")

    assert html =~ "Standings"

    standings = Tournament.standings()
    assert map_size(standings) > 0

    for {name, standing} <- standings do
      assert html =~ name
      assert html =~ if(standing.games == 0, do: "no data yet", else: "score")
    end
  end
end
