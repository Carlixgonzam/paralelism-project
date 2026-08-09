defmodule WikiRacePlatformWeb.StandingsLive do
  @moduledoc """
  The standings page. Ranks every roster group by accumulated score.
  Score alone decides the winner and every position behind them, same as
  in a single race. Shown as a bar chart. This page has no live race
  content, that is `RaceLive`'s job.
  """

  use WikiRacePlatformWeb, :live_view

  alias WikiRacePlatform.Race
  alias WikiRacePlatform.Tournament.Server, as: Tournament

  embed_templates "standings_live/*"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Race.subscribe()
    end

    {:ok, assign(socket, standings: Tournament.standings())}
  end

  @impl true
  def handle_info({:race_update, %{status: :finished}}, socket) do
    {:noreply, assign(socket, standings: Tournament.standings())}
  end

  def handle_info({:race_update, _snapshot}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns)

  defp sorted_standings(standings) do
    # Groups that have not played yet sort to the bottom, so a placeholder
    # zero score does not look like a leader. Score alone breaks every tie.
    # Win counts are shown for context only, they never affect the order.
    Enum.sort_by(standings, fn {_name, s} -> {s.games == 0, -s.score_sum} end)
  end

  @score_term_meta [
    %{
      key: :found,
      label: "Found",
      color: "bg-comic-red",
      desc: "1.0 for a verified path, 0 for none"
    },
    %{
      key: :hops,
      label: "Hops",
      color: "bg-comic-blue",
      desc: "this race's shortest path over this crawler's"
    },
    %{
      key: :time,
      label: "Time",
      color: "bg-comic-yellow",
      desc: "this race's fastest time over this crawler's"
    },
    %{
      key: :utilization,
      label: "Scheduler",
      color: "bg-comic-emerald",
      desc: "BEAM scheduler use, measured start to finish"
    }
  ]

  # Reads weights live from config instead of hardcoding them, so this
  # panel always matches `Race.Result`'s formula if the weights change.
  defp score_terms do
    weights = Application.get_env(:wiki_race_platform, :scoring, [])[:weights] || []

    Enum.map(@score_term_meta, fn term ->
      Map.put(term, :pct, round(Keyword.get(weights, term.key, 0) * 100))
    end)
  end

  # The false-path penalty in `Race.Result` can make `score_sum` negative,
  # so the result is clamped to [0, 100] instead of trusting the ratio
  # math. Without the clamp, a negative-over-negative division (everyone
  # penalized), or a heavily penalized group under a positive leader,
  # could render a nonsensical or negative bar.
  defp score_bar_pct(standing, standings) do
    max_score =
      standings |> Map.values() |> Enum.map(& &1.score_sum) |> Enum.max(fn -> 0.0 end)

    if max_score <= 0.0 do
      0
    else
      standing.score_sum
      |> Kernel./(max_score)
      |> Kernel.*(100)
      |> max(0.0)
      |> min(100.0)
      |> Float.round(1)
    end
  end
end
