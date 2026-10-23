defmodule WikiRace.ContractTest do
  @moduledoc """
  Exercises the student-facing contract the way the harness will, using a
  reference crawler that implements it. If this file stops compiling, the
  contract changed and every group's deliverable just broke.
  """
  use ExUnit.Case, async: true

  alias WikiRace.Status

  defmodule ReferenceCrawler do
    @moduledoc false
    @behaviour WikiRace.Crawler

    use GenServer

    @impl WikiRace.Crawler
    def start(start_url, target_url) do
      GenServer.start(__MODULE__, {start_url, target_url})
    end

    @impl WikiRace.Crawler
    def status(pid), do: GenServer.call(pid, :status)

    @impl GenServer
    def init({start_url, target_url}) do
      {:ok,
       Status.new(current_url: start_url, path: [start_url, target_url], frontier_size: 3)}
    end

    @impl GenServer
    def handle_call(:status, _from, status), do: {:reply, status, status}
  end

  describe "Status" do
    test "defaults describe a crawler that has just started" do
      assert %Status{state: :running, path: [], frontier_size: 0, visited_count: 0} =
               Status.new()
    end

    test "rejects unknown keys instead of silently dropping them" do
      assert_raise KeyError, fn -> Status.new(frontier_sise: 1) end
    end
  end

  describe "a conforming crawler" do
    test "start/2 returns a monitorable pid and status/1 returns a Status" do
      assert {:ok, pid} =
               ReferenceCrawler.start("http://wiki/A/Chess", "http://wiki/A/Bee")

      ref = Process.monitor(pid)

      assert %Status{current_url: "http://wiki/A/Chess", frontier_size: 3} =
               ReferenceCrawler.status(pid)

      # The harness kills rather than asking politely. A crawler must not
      # depend on cleanup running.
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    end
  end

  describe "Harness.report/1" do
    test "delivers the reporting pid, path and nothing else to the registered harness" do
      :yes = :global.register_name(WikiRace.Harness.registered_name(), self())
      on_exit(fn -> :global.unregister_name(WikiRace.Harness.registered_name()) end)

      path = ["http://wiki/A/Chess", "http://wiki/A/Bee"]
      assert :ok = WikiRace.Harness.report(path)

      # The reporting pid, not a bare node atom the crawler could fake by
      # hand-crafting a message outside this helper. The harness derives
      # the real origin node from the pid itself.
      me = self()
      assert_receive {:path_found, ^me, ^path}
    end

    test "is a no-op when no harness is registered, rather than crashing the crawl" do
      assert :undefined = :global.whereis_name(WikiRace.Harness.registered_name())
      assert :ok = WikiRace.Harness.report(["http://wiki/A/Chess"])
      assert :ok = WikiRace.Harness.report_exhausted()
    end
  end
end
