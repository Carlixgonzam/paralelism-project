defmodule WikiRacePlatform.FakeCrawler do
  @moduledoc """
  A scriptable crawler used to drive the harness in tests.

  It implements the real contract, so the harness treats it exactly like a
  student release. What it does is set in application env before the race
  starts, which keeps the script working whether it runs on this node or on a
  peer node.

  Recognised keys:

    * `on_start` - `{:error, reason}` to refuse to start
    * `report_after_ms` - `{ms, path}` to call `WikiRace.Harness.report/1`
    * `exhaust_after_ms` - `ms` to call `WikiRace.Harness.report_exhausted/0`
    * `crash_after_ms` - `ms` to die with `:boom`
    * `status_after_ms` - `{ms, keyword}` to change what `status/1` returns
  """

  @behaviour WikiRace.Crawler

  use GenServer

  alias WikiRace.Harness
  alias WikiRace.Status

  @impl WikiRace.Crawler
  def start(start_url, target_url) do
    case Keyword.fetch(script(), :on_start) do
      {:ok, {:error, reason}} -> {:error, reason}
      _ -> GenServer.start(__MODULE__, {start_url, target_url})
    end
  end

  @impl WikiRace.Crawler
  def status(pid), do: GenServer.call(pid, :status)

  @doc "Installs a script for the next race and clears it afterwards."
  @spec script(keyword()) :: :ok
  def script(steps) do
    Application.put_env(:wiki_race_platform, :fake_crawler, steps)
  end

  @doc "The script currently installed."
  @spec script() :: keyword()
  def script, do: Application.get_env(:wiki_race_platform, :fake_crawler, [])

  @impl GenServer
  def init({start_url, _target_url}) do
    steps = script()

    schedule(steps, :report_after_ms)
    schedule(steps, :exhaust_after_ms)
    schedule(steps, :crash_after_ms)
    schedule(steps, :status_after_ms)

    {:ok, %{status: Status.new(current_url: start_url, frontier_size: 7)}}
  end

  @impl GenServer
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  @impl GenServer
  def handle_info({:report_after_ms, path}, state) do
    Harness.report(path)
    {:noreply, state}
  end

  def handle_info(:exhaust_after_ms, state) do
    Harness.report_exhausted()
    {:noreply, %{state | status: Status.new(state: :exhausted)}}
  end

  def handle_info(:crash_after_ms, _state), do: exit(:boom)

  def handle_info({:status_after_ms, fields}, state) do
    {:noreply, %{state | status: Status.new(fields)}}
  end

  defp schedule(steps, key) do
    case Keyword.fetch(steps, key) do
      {:ok, ms} when is_integer(ms) -> Process.send_after(self(), key, ms)
      {:ok, {ms, payload}} -> Process.send_after(self(), {key, payload}, ms)
      :error -> :ok
    end
  end
end
