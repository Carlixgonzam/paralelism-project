defmodule WikiRacePlatform.Race.Dispatcher do
  @moduledoc """
  Owns the `:wiki_race_harness` global name and routes crawler reports to
  whichever race currently owns that node.

  `WikiRace.Harness.report/1` sends the reporting pid, not a bare node atom
  a crawler could fake by hand-crafting a message outside the helper.
  `node(pid)` is what the runtime actually witnessed, not a claim. Exactly
  one process holds this global name. It has to know which in-flight race a
  given node belongs to before forwarding, and that routing is what makes
  more than one race possible at once. Running the actual race (polling,
  verification, scoring) is `WikiRacePlatform.Race.Instance`'s job; this
  process never runs one itself.

  Each instance terminates the moment its race ends, so its final snapshot
  is cached here instead of lost. Callers can still ask for a finished
  race's result long after its process is gone.
  """

  use GenServer

  require Logger

  alias WikiRacePlatform.Race.Config
  alias WikiRacePlatform.Race.Instance

  @global_name :wiki_race_harness
  @instance_supervisor WikiRacePlatform.Race.InstanceSupervisor
  @start_timeout 20_000

  defmodule State do
    @moduledoc false
    defstruct node_races: %{},
              instances: %{},
              pending: %{},
              last_snapshots: %{},
              current: nil
  end

  # Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "The `:global` name the student `WikiRace.Harness` client looks up."
  @spec global_name() :: atom()
  def global_name, do: @global_name

  @doc "Starts a race. Fails if a requested node is already racing."
  @spec start_race(Config.t(), GenServer.server()) :: {:ok, map()} | {:error, String.t()}
  def start_race(%Config{} = config, server \\ __MODULE__) do
    GenServer.call(server, {:start_race, config}, @start_timeout)
  end

  @doc "Ends the given race early, scoring whatever has been verified."
  @spec abort(reference(), GenServer.server()) :: {:ok, map()} | {:error, String.t()}
  def abort(race_id, server \\ __MODULE__) do
    case GenServer.call(server, {:lookup, race_id}) do
      {:ok, pid} -> Instance.abort(pid)
      :error -> {:error, "no such race"}
    end
  end

  @doc "The given race's state, in the shape broadcast on its topic. `nil` if unknown."
  @spec snapshot(reference(), GenServer.server()) :: map() | nil
  def snapshot(race_id, server \\ __MODULE__) do
    GenServer.call(server, {:snapshot, race_id})
  end

  @doc "The most recently touched race, for single-viewer callers."
  @spec current(GenServer.server()) :: reference() | nil
  def current(server \\ __MODULE__), do: GenServer.call(server, :current)

  @doc "Every race currently in flight."
  @spec list_active(GenServer.server()) :: [reference()]
  def list_active(server \\ __MODULE__), do: GenServer.call(server, :list_active)

  # Server

  @impl true
  def init(_opts) do
    case :global.register_name(@global_name, self()) do
      :yes ->
        :ok

      :no ->
        Logger.warning(
          "#{inspect(@global_name)} is already registered elsewhere, " <>
            "crawler reports will not reach this node"
        )
    end

    {:ok, %State{}}
  end

  @impl true
  def handle_call({:start_race, config}, from, state) do
    nodes = Enum.map(config.players, & &1.node)

    cond do
      nodes == [] ->
        {:reply, {:error, "no players in this race"}, state}

      Enum.any?(nodes, &Map.has_key?(state.node_races, &1)) ->
        {:reply, {:error, "a node in this fixture is already racing"}, state}

      true ->
        race_id = make_ref()

        {:ok, pid} =
          DynamicSupervisor.start_child(
            @instance_supervisor,
            {Instance, race_id: race_id, config: config, dispatcher: self()}
          )

        Process.monitor(pid)
        node_races = Enum.reduce(nodes, state.node_races, &Map.put(&2, &1, race_id))
        instances = Map.put(state.instances, race_id, pid)
        pending = Map.put(state.pending, race_id, from)

        {:noreply,
         %{
           state
           | node_races: node_races,
             instances: instances,
             pending: pending,
             current: race_id
         }}
    end
  end

  def handle_call({:lookup, race_id}, _from, state) do
    case Map.fetch(state.instances, race_id) do
      {:ok, pid} -> {:reply, {:ok, pid}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:snapshot, race_id}, _from, state) do
    reply =
      case Map.fetch(state.instances, race_id) do
        {:ok, pid} -> instance_snapshot(pid) || Map.get(state.last_snapshots, race_id)
        :error -> Map.get(state.last_snapshots, race_id)
      end

    {:reply, reply, state}
  end

  def handle_call(:current, _from, state), do: {:reply, state.current, state}

  def handle_call(:list_active, _from, state),
    do: {:reply, Map.keys(state.instances), state}

  @impl true
  def handle_info({:path_found, pid, path}, state) when is_pid(pid) do
    forward(state, node(pid), {:path_found, node(pid), path})
  end

  def handle_info({:exhausted, pid}, state) when is_pid(pid) do
    forward(state, node(pid), {:exhausted, node(pid)})
  end

  # Routed through here rather than the instance replying to the original
  # caller directly, so the caller never sees a reply before this process's
  # own bookkeeping (node_races/instances) reflects it. Replying and
  # updating state happen in this one atomic handler, so there is no window
  # for `list_active/1` or another `start_race/1` call to observe a stale
  # state in between.
  def handle_info({:race_started, race_id, outcome}, state) do
    {from, pending} = Map.pop(state.pending, race_id)
    if from, do: GenServer.reply(from, outcome)
    {:noreply, %{state | pending: pending}}
  end

  def handle_info({:race_start_failed, race_id, outcome, nodes}, state) do
    {from, state} = pop_pending(state, race_id)
    state = free(state, race_id, nodes)
    if from, do: GenServer.reply(from, outcome)
    {:noreply, state}
  end

  def handle_info({:race_finished, race_id, nodes, snapshot}, state) do
    state = free(state, race_id, nodes)

    {:noreply,
     %{state | last_snapshots: Map.put(state.last_snapshots, race_id, snapshot)}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case Enum.find(state.instances, fn {_race_id, instance_pid} -> instance_pid == pid end) do
      nil ->
        {:noreply, state}

      {race_id, _pid} ->
        nodes = for {node, id} <- state.node_races, id == race_id, do: node
        {from, state} = pop_pending(state, race_id)

        # A clean stop already replied via :race_started/:race_start_failed
        # before terminating, so `from` is only still here if the instance
        # crashed without ever reporting an outcome. Without this, the
        # caller would hang until its own call timeout.
        if from,
          do: GenServer.reply(from, {:error, "race instance crashed: #{inspect(reason)}"})

        {:noreply, free(state, race_id, nodes)}
    end
  end

  def handle_info(message, state) do
    Logger.debug("dispatcher ignored #{inspect(message)}")
    {:noreply, state}
  end

  defp pop_pending(state, race_id) do
    {from, pending} = Map.pop(state.pending, race_id)
    {from, %{state | pending: pending}}
  end

  # Every inbound call from a player node is logged here, by the node the
  # runtime actually witnessed (see the moduledoc). This way tampering, or
  # just a node reporting outside any race it's in, leaves a trace instead
  # of silently vanishing.
  defp forward(state, node, msg) do
    case Map.fetch(state.node_races, node) do
      {:ok, race_id} ->
        Logger.info(
          "inbound #{elem(msg, 0)} from #{inspect(node)} (race #{inspect(race_id)})"
        )

        case Map.fetch(state.instances, race_id) do
          {:ok, pid} -> send(pid, msg)
          :error -> :ok
        end

      :error ->
        Logger.warning(
          "inbound #{elem(msg, 0)} from #{inspect(node)}, which is not in any race"
        )
    end

    {:noreply, state}
  end

  defp free(state, race_id, nodes) do
    node_races = Enum.reduce(nodes, state.node_races, &Map.delete(&2, &1))
    instances = Map.delete(state.instances, race_id)
    %{state | node_races: node_races, instances: instances}
  end

  # The instance may terminate between the `Map.fetch/2` above and this call
  # (its `:race_finished` message and our own mailbox order are not
  # guaranteed relative to each other), so a dead pid here is expected, not
  # a bug. Fall back to the cached snapshot instead of crashing on it.
  defp instance_snapshot(pid) do
    Instance.snapshot(pid)
  catch
    :exit, _ -> nil
  end
end
