defmodule WikiRacePlatform.Race.Player do
  @moduledoc """
  Everything the harness knows about one competitor during a race.

  `status` is the last snapshot polled out of the crawler and only drives the
  dashboard. Scoring uses `best_path` and `best_elapsed_ms`, which are set from
  verified path reports, never from a status snapshot alone.
  """

  alias WikiRace.Status

  @type state :: :pending | :running | :found | :exhausted | :down | :error

  @type t :: %__MODULE__{
          node: node(),
          label: String.t(),
          module: module() | nil,
          pid: pid() | nil,
          monitor_ref: reference() | nil,
          state: state(),
          status: Status.t(),
          best_path: Status.path() | nil,
          best_elapsed_ms: non_neg_integer() | nil,
          rejected: [{Status.path(), String.t()}],
          error: String.t() | nil
        }

  defstruct node: nil,
            label: nil,
            module: nil,
            pid: nil,
            monitor_ref: nil,
            state: :pending,
            status: %Status{},
            best_path: nil,
            best_elapsed_ms: nil,
            rejected: [],
            error: nil

  @settled [:found, :exhausted, :down, :error]

  @doc """
  Whether this player is done racing.

  A player that has found a valid path counts as settled, so a race where both
  crawlers succeed ends immediately instead of running out the clock.
  """
  @spec settled?(t()) :: boolean()
  def settled?(%__MODULE__{state: state}), do: state in @settled

  @doc "Whether the harness can still poll and kill this player's crawler."
  @spec live?(t()) :: boolean()
  def live?(%__MODULE__{pid: pid, state: state}),
    do: is_pid(pid) and state not in [:down, :error]

  @doc "Records a verified path, keeping it only if it beats what we had."
  @spec put_path(t(), Status.path(), non_neg_integer()) :: t()
  def put_path(%__MODULE__{} = player, path, elapsed_ms) do
    if better?(player, path) do
      %{player | best_path: path, best_elapsed_ms: elapsed_ms, state: :found}
    else
      player
    end
  end

  @doc "Records a path the verifier turned down, for display on the dashboard."
  @spec put_rejection(t(), Status.path(), String.t()) :: t()
  def put_rejection(%__MODULE__{} = player, path, reason) do
    %{player | rejected: Enum.take([{path, reason} | player.rejected], 5)}
  end

  @doc "Whether `path` would improve on this player's current best."
  @spec better?(t(), Status.path()) :: boolean()
  def better?(%__MODULE__{best_path: nil}, _path), do: true
  def better?(%__MODULE__{best_path: best}, path), do: length(path) < length(best)
end
