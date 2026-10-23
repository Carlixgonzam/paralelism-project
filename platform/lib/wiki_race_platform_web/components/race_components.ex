defmodule WikiRacePlatformWeb.RaceComponents do
  @moduledoc """
  Pieces shared by the dashboard and the admin interface.
  """

  use Phoenix.Component

  alias WikiRacePlatform.Race.Player
  alias WikiRacePlatform.Race.Result

  @doc """
  Two competitors joined into one bordered panel with a "VS" divider.
  """
  attr :accent_a, :atom, default: :red, values: [:red, :blue]
  attr :accent_b, :atom, default: :blue, values: [:red, :blue]
  slot :a, required: true
  slot :b, required: true

  def head_to_head(assigns) do
    ~H"""
    <div class="grid grid-cols-1 border-[3px] border-black bg-comic-paper-light sm:grid-cols-[1fr_auto_1fr]">
      <div class="min-w-0">{render_slot(@a)}</div>

      <div class="relative hidden items-stretch justify-center sm:flex">
        <div class="w-[3px] bg-black" />
        <div class="absolute top-1/2 left-1/2 flex h-12 w-12 -translate-x-1/2 -translate-y-1/2 -rotate-6 items-center justify-center rounded-full border-[3px] border-black bg-comic-yellow font-display text-lg shadow-comic-sm">
          VS
        </div>
      </div>

      <div class="min-w-0 border-t-[3px] border-black sm:border-t-0">{render_slot(@b)}</div>
    </div>
    """
  end

  @doc """
  One competitor's live panel, projector-scale, for the live race view.

  Stats (frontier, visited, hops, time, scheduler use) are stacked as
  dashed rows. Hops and time show this crawler's raw numbers as soon as
  it finds a path. Scheduler use and the blended score need the whole
  race to finish (see `WikiRacePlatform.Race.Result`), so they show "-"
  until `result` is passed in with this player's entry.
  """
  attr :player, Player, required: true
  attr :result, Result, default: nil
  attr :winner?, :boolean, default: false
  attr :accent, :atom, default: :red, values: [:red, :blue]
  attr :bordered, :boolean, default: true

  def spectator_player_panel(assigns) do
    assigns = assign(assigns, :entry, entry_for(assigns.result, assigns.player))

    ~H"""
    <section class={[
      "bg-comic-paper-light",
      @bordered && "border-4 border-black",
      @bordered && @winner? && "shadow-comic-lg",
      @bordered && !@winner? && "shadow-comic",
      @winner? && "bg-comic-yellow/10"
    ]}>
      <div class={["h-4 border-b-4 border-black", accent_bg(@accent)]} />
      <div class="p-8">
        <header class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class={["truncate font-display text-5xl tracking-wide", accent_text(@accent)]}>
              {@player.label}
            </h2>
            <p class="truncate font-comic-mono text-base text-comic-ink/50">{@player.node}</p>
          </div>
          <.state_badge state={@player.state} size={:large} />
        </header>

        <div class="mt-8 border-t-2 border-dashed border-black">
          <.stat label="Frontier" value={@player.status.frontier_size} size={:large} />
          <.stat label="Visited" value={@player.status.visited_count} size={:large} />
          <.stat label="Hops" value={hops(@player)} size={:large} />
          <.stat label="Time" value={time_label(@player)} size={:large} />
          <.stat label="Scheduler use" value={utilization_label(@entry)} size={:large} />
          <.stat :if={@entry} label="Score" value={score_label(@entry)} size={:large} />
        </div>

        <div class="mt-6">
          <p class="font-comic-mono text-base tracking-wide text-comic-ink/50 uppercase">
            Now reading
          </p>
          <p
            class="mt-1 truncate border-4 border-black bg-comic-paper px-4 py-3 text-3xl font-bold"
            title={@player.status.current_url}
          >
            {title_of(@player.status.current_url) || "waiting"}
          </p>
        </div>

        <div :if={@player.best_path} class="mt-6">
          <p class="font-comic-mono text-base tracking-wide text-comic-ink/50 uppercase">
            Verified path in {@player.best_elapsed_ms} ms
          </p>
          <.path_trail path={@player.best_path} size={:large} accent={@accent} />
        </div>

        <div :if={@player.best_path == nil and @player.status.path != []} class="mt-6">
          <p class="font-comic-mono text-base tracking-wide text-comic-ink/50 uppercase">
            Claimed path, not verified yet
          </p>
          <.path_trail path={@player.status.path} size={:large} accent={@accent} />
        </div>

        <p :if={@player.error} class="mt-6 font-comic-mono text-2xl font-bold text-comic-red">
          {@player.error}
        </p>
      </div>
    </section>
    """
  end

  @doc """
  Renders a path as a numbered vertical list of hops, with the most recent
  article highlighted. Vertical layout gives a long title the full width
  of the panel instead of competing with other hops for space.
  """
  attr :path, :list, required: true
  attr :size, :atom, default: :normal, values: [:normal, :large]
  attr :accent, :atom, default: :red, values: [:red, :blue]

  def path_trail(assigns) do
    ~H"""
    <ol class="mt-1.5 space-y-1">
      <li :for={{url, index} <- Enum.with_index(@path)} class="flex items-center gap-2">
        <span class={[
          "shrink-0 text-right font-comic-mono text-comic-ink/40",
          @size == :normal && "w-5 text-[10px]",
          @size == :large && "w-7 text-sm"
        ]}>
          {index + 1}.
        </span>
        <span
          title={title_of(url)}
          class={[
            "min-w-0 flex-1 truncate rounded border-2 border-black font-comic-mono font-bold",
            @size == :normal && "px-2 py-0.5 text-[11px]",
            @size == :large && "px-3 py-1 text-lg",
            if(index == length(@path) - 1,
              do: current_chip_class(@accent),
              else: "bg-comic-paper-dim text-comic-ink/70"
            )
          ]}
        >
          {title_of(url)}
        </span>
      </li>
    </ol>
    """
  end

  @doc "A colored badge showing a crawler's current state."
  attr :state, :atom, required: true
  attr :size, :atom, default: :normal, values: [:normal, :large]

  def state_badge(assigns) do
    ~H"""
    <span class={[
      "shrink-0 rounded-full border-2 border-black font-comic-mono font-bold tracking-wide uppercase",
      @size == :normal && "px-2.5 py-1 text-[10px]",
      @size == :large && "px-4 py-2 text-lg",
      badge_class(@state)
    ]}>
      {@state}
    </span>
    """
  end

  @doc """
  A labelled stat shown as a dashed row, with the label on the left and the
  value on the right.
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :size, :atom, default: :normal, values: [:normal, :large]

  def stat(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-between gap-3 border-b-2 border-dashed border-black font-comic-mono",
      @size == :normal && "py-1.5 text-xs",
      @size == :large && "py-2 text-base"
    ]}>
      <span class="tracking-wide text-comic-ink/50 uppercase">{@label}</span>
      <span class="font-bold text-comic-ink tabular-nums">{@value}</span>
    </div>
    """
  end

  @doc "Milliseconds as a clock a human can read at a glance."
  @spec format_ms(non_neg_integer() | nil) :: String.t()
  def format_ms(nil), do: "0:00.0"

  def format_ms(ms) do
    minutes = div(ms, 60_000)
    seconds = ms |> rem(60_000) |> div(1_000)
    tenths = ms |> rem(1_000) |> div(100)

    "#{minutes}:#{String.pad_leading("#{seconds}", 2, "0")}.#{tenths}"
  end

  @doc "The article title at the end of a Kiwix URL."
  @spec title_of(String.t() | nil) :: String.t() | nil
  def title_of(nil), do: nil

  def title_of(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> to_string()
    |> Path.basename()
    |> URI.decode()
    |> String.replace("_", " ")
  end

  defp hops(%Player{best_path: nil}), do: "-"
  defp hops(%Player{best_path: path}), do: length(path) - 1

  defp time_label(%Player{best_elapsed_ms: nil}), do: "-"
  defp time_label(%Player{best_elapsed_ms: ms}), do: format_ms(ms)

  # This player's entry in the final race result. Returns nil while the
  # race is running, or if this node is not in the ranking (should not
  # happen, but a missing match is safer than a crash here).
  defp entry_for(nil, _player), do: nil

  defp entry_for(%Result{ranking: ranking}, player),
    do: Enum.find(ranking, &(&1.node == player.node))

  defp utilization_label(nil), do: "-"

  defp utilization_label(entry),
    do: "#{:erlang.float_to_binary(entry.utilization * 100, decimals: 1)}%"

  defp score_label(entry), do: :erlang.float_to_binary(entry.score, decimals: 2)

  defp accent_bg(:red), do: "bg-comic-red"
  defp accent_bg(:blue), do: "bg-comic-blue"

  defp accent_text(:red), do: "text-comic-red"
  defp accent_text(:blue), do: "text-comic-blue"

  defp current_chip_class(:red), do: "bg-comic-red text-comic-paper-light"
  defp current_chip_class(:blue), do: "bg-comic-blue text-comic-paper-light"

  defp badge_class(:running), do: "bg-comic-blue text-comic-paper-light"
  defp badge_class(:found), do: "bg-black text-comic-yellow"
  defp badge_class(:exhausted), do: "border-dashed bg-comic-paper-dim text-comic-ink/70"
  defp badge_class(:down), do: "bg-comic-red text-comic-paper-light"
  defp badge_class(:error), do: "bg-comic-red text-comic-paper-light"
  defp badge_class(_state), do: "bg-comic-paper-dim text-comic-ink/60"
end
