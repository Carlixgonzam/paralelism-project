defmodule WikiRacePlatformWeb.ScheduleLive do
  @moduledoc """
  The race day card. Shows every match played so far, the live one, and
  what is queued next. Read-only: starting or advancing a match happens on
  `AdminLive`, not here.

  Swiss pairings for round 2 and later are not known until the round
  before them finishes. So this only shows what is actually decided:
  finished matches, the live one, and this round's remaining queue. It
  never shows a full-tournament schedule ahead of time.
  """

  use WikiRacePlatformWeb, :live_view

  alias WikiRacePlatform.Race
  alias WikiRacePlatform.Race.Result
  alias WikiRacePlatform.Tournament.Server, as: Tournament

  embed_templates "schedule_live/*"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Race.subscribe()
    end

    {:ok, socket |> assign(snapshot: Race.snapshot()) |> refresh_tournament()}
  end

  defp refresh_tournament(socket) do
    socket =
      assign(socket,
        pair: Tournament.current_pair(),
        history: Tournament.history(),
        upcoming: Tournament.upcoming_round(),
        progress: Tournament.progress()
      )

    assign(socket, :rows, rows(socket.assigns))
  end

  @impl true
  def handle_info({:race_update, %{status: :finished} = snapshot}, socket) do
    {:noreply, socket |> assign(snapshot: snapshot) |> refresh_tournament()}
  end

  def handle_info({:race_update, snapshot}, socket) do
    {:noreply, socket |> assign(snapshot: snapshot) |> refresh_rows()}
  end

  defp refresh_rows(socket), do: assign(socket, :rows, rows(socket.assigns))

  @impl true
  def render(assigns)

  defp tagline(%{complete: true}), do: "Tournament complete"

  defp tagline(%{round: round, total_rounds: total}),
    do: "Round #{round} of #{total} · one race at a time"

  defp row_badge_class(:live), do: "bg-comic-red text-comic-paper-light"
  defp row_badge_class(:finished), do: "bg-comic-yellow text-black"

  defp row_badge_class(:upcoming),
    do: "border-dashed bg-comic-paper-dim text-comic-ink/50"

  defp finished_row(result) do
    %{
      label: result.ranking |> Enum.map(& &1.label) |> Enum.join(" vs "),
      status: :finished,
      detail: Result.summary(result)
    }
  end

  defp live_rows(%{status: :running, players: players}) when players != [] do
    [
      %{
        label: players |> Enum.map(& &1.label) |> Enum.join(" vs "),
        status: :live,
        detail: "● live"
      }
    ]
  end

  defp live_rows(_snapshot), do: []

  defp upcoming_row({:bye, name}),
    do: %{label: "#{name}, solo time trial", status: :upcoming, detail: "upcoming"}

  defp upcoming_row({a, b}),
    do: %{label: "#{a} vs #{b}", status: :upcoming, detail: "upcoming"}

  defp rows(assigns) do
    Enum.map(assigns.history, &finished_row/1) ++
      live_rows(assigns.snapshot) ++ Enum.map(assigns.upcoming, &upcoming_row/1)
  end
end
