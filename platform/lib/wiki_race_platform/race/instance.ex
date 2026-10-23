defmodule WikiRacePlatform.Race.Instance do
  @moduledoc """
  One race, start to finish.

  Spawned fresh by `WikiRacePlatform.Race.Dispatcher` for exactly one race.
  It starts running immediately and terminates the moment that race ends.
  This is the same state machine `WikiRacePlatform.Race.Server` used to run
  as the single global harness. The logic (start crawlers, poll, verify
  reports, score) is unchanged; only who owns the `:global` name and how
  many of these can run at once has moved to the dispatcher.

  A race ends when every player has settled or when the time limit expires.
  Finding a path counts as settled, so two successful crawlers end the race
  early rather than running out the clock.
  """

  use GenServer

  require Logger

  alias WikiRace.Status
  alias WikiRacePlatform.Race.Config
  alias WikiRacePlatform.Race.Discovery
  alias WikiRacePlatform.Race.Player
  alias WikiRacePlatform.Race.Result
  alias WikiRacePlatform.Race.Verifier
  alias WikiRacePlatform.Tournament.Store

  @legacy_topic "race"
  @task_supervisor WikiRacePlatform.Race.TaskSupervisor
  @verification_grace_ms 5_000

  defmodule State do
    @moduledoc false
    defstruct race_id: nil,
              dispatcher: nil,
              status: :starting,
              config: nil,
              players: %{},
              order: [],
              started_at: nil,
              started_at_utc: nil,
              ended_at_utc: nil,
              poll_timer: nil,
              limit_timer: nil,
              result: nil,
              verifications: %{},
              seen_paths: MapSet.new(),
              scheduler_start: %{}
  end

  # Client

  # Each instance runs exactly one race and stops :normal when it's over.
  # That's a completed job, not a crash, so the supervisor must never treat
  # it as something to restart. (The default child spec is :permanent,
  # which would otherwise respawn a finished race in a loop.)
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "The PubSub topic every instance broadcasts on, regardless of race id."
  @spec legacy_topic() :: String.t()
  def legacy_topic, do: @legacy_topic

  @doc "The PubSub topic this one race's updates broadcast on."
  @spec topic(reference()) :: String.t()
  def topic(race_id), do: "#{@legacy_topic}:#{inspect(race_id)}"

  @doc "Ends this race early, scoring whatever has been verified."
  @spec abort(pid()) :: {:ok, map()} | {:error, String.t()}
  def abort(pid), do: GenServer.call(pid, :abort, 30_000)

  @doc "This race's state, in the shape broadcast on its topic."
  @spec snapshot(pid()) :: map()
  def snapshot(pid), do: GenServer.call(pid, :snapshot)

  # Server

  @impl true
  def init(opts) do
    state = %State{
      race_id: Keyword.fetch!(opts, :race_id),
      dispatcher: Keyword.fetch!(opts, :dispatcher),
      config: Keyword.fetch!(opts, :config)
    }

    {:ok, state, {:continue, :start_race}}
  end

  @impl true
  def handle_continue(:start_race, state) do
    case resolve_modules(state.config) do
      {:ok, resolved} -> do_start_race(state, resolved)
      {:error, reason} -> stop_with_error(state, reason)
    end
  end

  @impl true
  def handle_call(:abort, _from, %State{status: :running} = state) do
    state = finish(state, :aborted)
    {:stop, :normal, {:ok, build_snapshot(state)}, state}
  end

  def handle_call(:abort, _from, state) do
    {:reply, {:error, "no race is running"}, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, build_snapshot(state), state}
  end

  @impl true
  def handle_info(:poll, %State{status: :running} = state) do
    state = state |> poll_players() |> schedule_poll() |> broadcast()
    {:noreply, state}
  end

  def handle_info(:time_limit, %State{status: :running} = state) do
    {:stop, :normal, finish(state, :time_limit)}
  end

  def handle_info({:path_found, node, path}, %State{status: :running} = state) do
    {:noreply, state |> submit(node, path) |> broadcast()}
  end

  def handle_info({:exhausted, node}, %State{status: :running} = state) do
    state
    |> update_player(node, fn
      %Player{state: :running} = player -> %{player | state: :exhausted}
      player -> player
    end)
    |> broadcast()
    |> maybe_finish()
  end

  def handle_info({ref, verdict}, %State{} = state) when is_reference(ref) do
    case pop_verification(state, ref) do
      {nil, state} ->
        {:noreply, state}

      {job, state} ->
        Process.demonitor(ref, [:flush])
        state |> apply_verdict(job, verdict) |> broadcast() |> maybe_finish()
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case pop_verification(state, ref) do
      {nil, state} ->
        handle_player_down(state, ref, reason)

      {job, state} ->
        verdict = {:error, "verification crashed: #{inspect(reason)}"}
        state |> apply_verdict(job, verdict) |> broadcast() |> maybe_finish()
    end
  end

  def handle_info(message, state) do
    Logger.debug("race instance ignored #{inspect(message)}")
    {:noreply, state}
  end

  # Starting

  defp resolve_modules(%Config{players: players}) do
    resolved =
      players
      |> Task.async_stream(fn spec -> {spec, Discovery.resolve(spec)} end,
        max_concurrency: max(length(players), 1),
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {spec, {:ok, module}}} -> {:ok, %{spec | module: module}}
        {:ok, {_spec, {:error, reason}}} -> {:error, reason}
        {:exit, _reason} -> {:error, "timed out looking for a crawler module"}
      end)

    case Enum.filter(resolved, &match?({:error, _}, &1)) do
      [] -> {:ok, Enum.map(resolved, fn {:ok, spec} -> spec end)}
      errors -> {:error, errors |> Enum.map_join("; ", fn {:error, e} -> e end)}
    end
  end

  defp do_start_race(state, specs) do
    config = state.config
    started_at = System.monotonic_time()
    outcomes = start_crawlers(specs, config)
    players = Enum.map(outcomes, &build_player/1)

    if Enum.any?(players, &(&1.state == :running)) do
      scheduler_start =
        players
        |> Enum.filter(&(&1.state == :running))
        |> Map.new(&{&1.node, scheduler_snapshot(&1.node)})

      state = %{
        state
        | status: :running,
          players: Map.new(players, &{&1.node, &1}),
          order: Enum.map(players, & &1.node),
          started_at: started_at,
          started_at_utc: DateTime.utc_now(),
          scheduler_start: scheduler_start
      }

      state =
        state
        |> monitor_crawlers()
        |> schedule_poll()
        |> schedule_limit()
        |> broadcast()

      send(state.dispatcher, {:race_started, state.race_id, {:ok, build_snapshot(state)}})
      {:noreply, state}
    else
      stop_with_error(state, start_failure_message(players))
    end
  end

  defp stop_with_error(state, reason) do
    nodes = Enum.map(state.config.players, & &1.node)
    send(state.dispatcher, {:race_start_failed, state.race_id, {:error, reason}, nodes})
    {:stop, :normal, state}
  end

  # All crawlers are started concurrently so the reveal is as close to
  # simultaneous as the network allows.
  defp start_crawlers(specs, config) do
    specs
    |> Task.async_stream(
      fn spec ->
        {spec, remote_start(spec, config)}
      end,
      max_concurrency: max(length(specs), 1),
      timeout: 15_000 + 1_000,
      on_timeout: :kill_task
    )
    |> Enum.zip(specs)
    |> Enum.map(fn
      {{:ok, outcome}, _spec} -> outcome
      {{:exit, _reason}, spec} -> {spec, {:error, "start/2 timed out"}}
    end)
  end

  defp remote_start(spec, config) do
    args = [config.start_url, config.target_url]

    case :rpc.call(spec.node, spec.module, :start, args, 15_000) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      {:error, reason} -> {:error, "start/2 refused: #{inspect(reason)}"}
      {:badrpc, reason} -> {:error, "start/2 unreachable: #{inspect(reason)}"}
      other -> {:error, "start/2 returned #{inspect(other)}"}
    end
  end

  # Scheduler utilization, sampled here (race start) and again in `finish/2`
  # (race end). It's a pure external measurement, so it costs the student
  # contract nothing. `:scheduler_wall_time_all` includes dirty schedulers,
  # for a complete picture of how busy the node actually was.
  #
  # `:erlang.system_flag(:scheduler_wall_time, true)` only stays in effect
  # as long as some process on that node is known to want it: the VM turns
  # it back off the instant the enabling process exits. A plain `:rpc.call`
  # runs on a throwaway worker process that dies the moment the call
  # returns, so enabling it that way would turn it straight back off before
  # the next call ever reads it (every race would then read `{0, 0}` at
  # both ends, silently zeroing every score's utilization term).
  # `ensure_scheduler_wall_time/1` spawns a small detached process on the
  # target node instead, via `Code.eval_string` (this needs nothing from
  # our own codebase to exist there, only the Elixir runtime every student
  # release already ships). That process outlives the RPC call and holds
  # the flag on for the rest of that node's uptime.
  @scheduler_keeper :wiki_race_scheduler_wall_time_keeper

  defp scheduler_snapshot(node) do
    case :rpc.call(node, :erlang, :statistics, [:scheduler_wall_time_all]) do
      list when is_list(list) ->
        sum_scheduler_time(list)

      _not_enabled ->
        ensure_scheduler_wall_time(node)

        case :rpc.call(node, :erlang, :statistics, [:scheduler_wall_time_all]) do
          list when is_list(list) -> sum_scheduler_time(list)
          _still_unavailable -> {0, 0}
        end
    end
  end

  defp ensure_scheduler_wall_time(node) do
    source = """
    case Process.whereis(#{inspect(@scheduler_keeper)}) do
      nil ->
        pid =
          spawn(fn ->
            :erlang.system_flag(:scheduler_wall_time, true)
            Process.sleep(:infinity)
          end)

        Process.register(pid, #{inspect(@scheduler_keeper)})

      _pid ->
        :already_running
    end
    """

    :rpc.call(node, Code, :eval_string, [source])
  end

  defp sum_scheduler_time(list) do
    Enum.reduce(list, {0, 0}, fn {_id, active, total}, {a, t} ->
      {a + active, t + total}
    end)
  end

  defp build_player({spec, {:ok, pid}}) do
    %Player{
      node: spec.node,
      label: spec.label,
      module: spec.module,
      pid: pid,
      state: :running
    }
  end

  defp build_player({spec, {:error, reason}}) do
    %Player{
      node: spec.node,
      label: spec.label,
      module: spec.module,
      state: :error,
      error: reason
    }
  end

  defp monitor_crawlers(state) do
    players =
      Map.new(state.players, fn
        {node, %Player{pid: pid} = player} when is_pid(pid) ->
          {node, %{player | monitor_ref: Process.monitor(pid)}}

        {node, player} ->
          {node, player}
      end)

    %{state | players: players}
  end

  defp start_failure_message(players) do
    players
    |> Enum.map_join("; ", fn player -> "#{player.label}: #{player.error}" end)
  end

  # Polling

  defp poll_players(state) do
    timeout = poll_timeout(state.config)

    state.order
    |> Enum.map(&Map.fetch!(state.players, &1))
    |> Enum.filter(&Player.live?/1)
    |> Task.async_stream(fn player -> {player.node, remote_status(player, timeout)} end,
      max_concurrency: max(map_size(state.players), 1),
      timeout: timeout + 1_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(state, fn
      {:ok, {node, {:ok, status}}}, acc -> apply_status(acc, node, status)
      _other, acc -> acc
    end)
  end

  defp remote_status(player, timeout) do
    case :rpc.call(player.node, player.module, :status, [player.pid], timeout) do
      %Status{} = status -> {:ok, status}
      other -> {:error, other}
    end
  end

  # A status that claims a path is treated as a report too, so a crawler that
  # never called `report/1` can still be scored.
  defp apply_status(state, node, %Status{} = status) do
    state = update_player(state, node, &%{&1 | status: status})

    if status.state == :found and status.path != [] do
      submit(state, node, status.path)
    else
      state
    end
  end

  defp poll_timeout(%Config{poll_interval_ms: interval}) do
    interval |> max(200) |> min(2_000)
  end

  defp schedule_poll(state) do
    %{
      state
      | poll_timer: Process.send_after(self(), :poll, state.config.poll_interval_ms)
    }
  end

  defp schedule_limit(state) do
    %{
      state
      | limit_timer: Process.send_after(self(), :time_limit, state.config.time_limit_ms)
    }
  end

  # Verification

  defp submit(state, node, path) do
    elapsed = elapsed_ms(state)
    player = Map.get(state.players, node)
    key = {node, Enum.map(path, &Verifier.canonical/1)}

    cond do
      is_nil(player) ->
        Logger.debug("report from unknown node #{inspect(node)}")
        state

      MapSet.member?(state.seen_paths, key) ->
        state

      not Player.better?(player, path) ->
        %{state | seen_paths: MapSet.put(state.seen_paths, key)}

      true ->
        state = %{state | seen_paths: MapSet.put(state.seen_paths, key)}
        screen(state, node, path, elapsed)
    end
  end

  # Structural problems are caught here so junk paths cost no HTTP requests.
  defp screen(state, node, path, elapsed) do
    config = state.config

    case Verifier.check_shape(path, config.start_url, config.target_url) do
      :ok ->
        task =
          Task.Supervisor.async_nolink(@task_supervisor, fn ->
            Verifier.verify(path, config.start_url, config.target_url)
          end)

        job = %{task: task, node: node, path: path, elapsed_ms: elapsed}
        %{state | verifications: Map.put(state.verifications, task.ref, job)}

      {:error, reason} ->
        update_player(state, node, &Player.put_rejection(&1, path, reason))
    end
  end

  defp pop_verification(state, ref) do
    case Map.pop(state.verifications, ref) do
      {nil, _} -> {nil, state}
      {job, rest} -> {job, %{state | verifications: rest}}
    end
  end

  defp apply_verdict(state, job, :ok) do
    update_player(state, job.node, &Player.put_path(&1, job.path, job.elapsed_ms))
  end

  defp apply_verdict(state, job, {:error, reason}) do
    update_player(state, job.node, &Player.put_rejection(&1, job.path, reason))
  end

  defp await_verifications(%State{verifications: verifications} = state)
       when map_size(verifications) == 0 do
    state
  end

  defp await_verifications(state) do
    jobs = Map.values(state.verifications)

    jobs
    |> Enum.map(& &1.task)
    |> Task.yield_many(@verification_grace_ms)
    |> Enum.zip(jobs)
    |> Enum.reduce(%{state | verifications: %{}}, fn {{task, outcome}, job}, acc ->
      case outcome do
        {:ok, verdict} ->
          apply_verdict(acc, job, verdict)

        _ ->
          Task.shutdown(task, :brutal_kill)
          apply_verdict(acc, job, {:error, "verification did not finish in time"})
      end
    end)
  end

  # Player crashes

  defp handle_player_down(state, ref, reason) do
    case Enum.find(state.players, fn {_node, p} -> p.monitor_ref == ref end) do
      nil ->
        {:noreply, state}

      {node, _player} ->
        state
        |> update_player(node, fn player ->
          if Player.settled?(player) do
            %{player | pid: nil}
          else
            %{
              player
              | state: :down,
                pid: nil,
                error: "crawler went down: #{inspect(reason)}"
            }
          end
        end)
        |> broadcast()
        |> maybe_finish()
    end
  end

  # Finishing

  defp maybe_finish(%State{status: :running} = state) do
    if Enum.all?(Map.values(state.players), &Player.settled?/1) do
      {:stop, :normal, finish(state, :all_settled)}
    else
      {:noreply, state}
    end
  end

  defp maybe_finish(state), do: {:noreply, state}

  defp finish(state, ended_by) do
    duration = elapsed_ms(state)

    state =
      state
      |> cancel_timers()
      |> poll_players()
      |> await_verifications()
      |> kill_crawlers()

    result =
      Result.build(ordered_players(state), ended_by, duration, compute_utilization(state))

    # {name, node} addressing works the same whether Store is local or on a
    # split-off web node. Defaults to node() when unconfigured, so a single
    # combined node just addresses itself.
    web_node = Application.get_env(:wiki_race_platform, :web_node, node())
    Store.append(result, {Store, web_node})

    state = %{state | status: :finished, result: result, ended_at_utc: DateTime.utc_now()}

    send(
      state.dispatcher,
      {:race_finished, state.race_id, Map.keys(state.players), build_snapshot(state)}
    )

    broadcast(state)
  end

  # The end-of-race half of the scheduler utilization measurement. See
  # `scheduler_snapshot/1`. A node that died mid-race reads back `{0, 0}`
  # from that same fallback, which would make `end_total < start_total`, so
  # the result is clamped to zero instead of going negative.
  defp compute_utilization(state) do
    Map.new(state.scheduler_start, fn {node, {start_active, start_total}} ->
      {end_active, end_total} = scheduler_snapshot(node)
      total_delta = max(end_total - start_total, 0)

      utilization =
        if total_delta > 0, do: (end_active - start_active) / total_delta, else: 0.0

      {node, utilization}
    end)
  end

  defp cancel_timers(state) do
    Enum.each([state.poll_timer, state.limit_timer], fn
      nil -> :ok
      timer -> Process.cancel_timer(timer)
    end)

    %{state | poll_timer: nil, limit_timer: nil}
  end

  # The contract promises one last status snapshot and then a hard kill, with
  # no shutdown callback. `poll_players/1` above took that snapshot.
  defp kill_crawlers(state) do
    players =
      Map.new(state.players, fn {node, player} ->
        if is_pid(player.pid) do
          if player.monitor_ref, do: Process.demonitor(player.monitor_ref, [:flush])
          Process.exit(player.pid, :kill)
          {node, %{player | pid: nil, monitor_ref: nil}}
        else
          {node, player}
        end
      end)

    %{state | players: players}
  end

  # Shared helpers

  defp update_player(state, node, fun) do
    case Map.fetch(state.players, node) do
      {:ok, player} -> %{state | players: Map.put(state.players, node, fun.(player))}
      :error -> state
    end
  end

  defp ordered_players(state), do: Enum.map(state.order, &Map.fetch!(state.players, &1))

  defp elapsed_ms(%State{started_at: nil}), do: 0

  defp elapsed_ms(%State{started_at: started_at}) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :millisecond)
    |> max(0)
  end

  defp build_snapshot(state) do
    %{
      race_id: state.race_id,
      status: state.status,
      config: state.config,
      players: ordered_players(state),
      started_at_utc: state.started_at_utc,
      ended_at_utc: state.ended_at_utc,
      elapsed_ms:
        if(state.status == :finished,
          do: finished_duration(state),
          else: elapsed_ms(state)
        ),
      result: state.result
    }
  end

  defp finished_duration(%State{result: %Result{duration_ms: ms}}), do: ms
  defp finished_duration(state), do: elapsed_ms(state)

  defp broadcast(state) do
    snapshot = build_snapshot(state)

    Phoenix.PubSub.broadcast(
      WikiRacePlatform.PubSub,
      @legacy_topic,
      {:race_update, snapshot}
    )

    Phoenix.PubSub.broadcast(
      WikiRacePlatform.PubSub,
      topic(state.race_id),
      {:race_update, snapshot}
    )

    state
  end
end
