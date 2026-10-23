defmodule WikiRacePlatformWeb.RaceComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import WikiRacePlatformWeb.RaceComponents

  alias WikiRacePlatform.Race.Player
  alias WikiRacePlatform.Race.Result

  test "stat/1 defaults to normal size and switches to large" do
    normal = render_component(&stat/1, label: "Frontier", value: 3)
    assert normal =~ "text-xs"
    refute normal =~ "text-base"

    large = render_component(&stat/1, label: "Frontier", value: 3, size: :large)
    assert large =~ "text-base"
    refute large =~ "text-xs"
  end

  test "path_trail/1 defaults to normal size and switches to large" do
    path = [
      "http://kiwix.test/content/wiki/Elixir",
      "http://kiwix.test/content/wiki/Erlang"
    ]

    normal = render_component(&path_trail/1, path: path)
    assert normal =~ "text-[11px]"

    large = render_component(&path_trail/1, path: path, size: :large)
    assert large =~ "text-lg"
    refute large =~ "text-[11px]"
  end

  test "state_badge/1 defaults to normal size and switches to large" do
    normal = render_component(&state_badge/1, state: :running)
    assert normal =~ "text-[10px]"

    large = render_component(&state_badge/1, state: :running, size: :large)
    assert large =~ "text-lg"
    refute large =~ "text-[10px]"
  end

  test "spectator_player_panel/1 shows dashes for time/scheduler use and no score while running" do
    player = %Player{
      node: :groupa@host,
      label: "Group A",
      state: :running,
      status: WikiRace.Status.new(current_url: "http://kiwix.test/content/wiki/Elixir")
    }

    html = render_component(&spectator_player_panel/1, player: player)

    assert html =~ "Time"
    assert html =~ "Scheduler use"
    refute html =~ "Score"
    assert html =~ "Group A"
  end

  test "spectator_player_panel/1 shows the actual score and utilization once the race result is in" do
    player = %Player{
      node: :groupa@host,
      label: "Group A",
      state: :found,
      best_path: ["http://kiwix.test/a", "http://kiwix.test/b"],
      best_elapsed_ms: 500,
      status: WikiRace.Status.new(current_url: "http://kiwix.test/content/wiki/Elixir")
    }

    result = Result.build([player], :all_settled, 1_000, %{player.node => 0.5})

    html = render_component(&spectator_player_panel/1, player: player, result: result)

    assert html =~ "Score"
    assert html =~ "0.95"
    assert html =~ "50.0%"
  end
end
