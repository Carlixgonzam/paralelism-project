defmodule WikiRacePlatform.Deploy.IntegrationTest do
  # The real pipeline end to end: a real `mix release` via `release_builder`,
  # a real SSH upload/unpack/start against the docker-simulated `player_vm1`,
  # and a genuine distributed-Erlang join back to this test node. See `make
  # test-deploy`. Needs `player_vm1` already up and this suite running under
  # a distributed node (`--name`, matching `run_start/1`'s choice of long
  # names for a real-IP-reachable player VM).
  use ExUnit.Case, async: false

  alias WikiRacePlatform.Deploy.Manifest
  alias WikiRacePlatform.Deploy.Server

  @moduletag :integration
  @moduletag timeout: 180_000

  setup do
    unless Node.alive?() do
      flunk("""
      this suite needs a distributed node. Run it via:
        elixir --name tester@127.0.0.1 --cookie wikirace -S mix test --only integration
      (or `make test-deploy`, which does this for you)
      """)
    end

    ip = player_vm1_ip()
    group = Manifest.group!("Local fixture")
    on_exit(fn -> cleanup(group) end)
    %{ip: ip, group: group}
  end

  test "deploy! then start! ships a real release and joins the cluster", %{
    ip: ip,
    group: group
  } do
    target = %{host: ip, node: :"integration_player@#{ip}"}

    server =
      start_supervised!(
        {Server,
         name: :integration_deploy_server, join_timeout_ms: 30_000, join_poll_ms: 500}
      )

    Server.subscribe(group.name)

    assert :ok = Server.deploy!(group.name, target, server)
    assert_deploy_status(group.name, :stopped, 120_000)

    assert :ok = Server.start!(group.name, server)
    assert_deploy_status(group.name, :running, 35_000)

    assert Server.status(group.name, server) == %{deploy: :running, connected: true}
    assert target.node in Node.list()

    assert :ok = Server.stop!(group.name, server)
    assert_deploy_status(group.name, :stopped, 15_000)
  end

  defp assert_deploy_status(group_name, status, timeout) do
    receive do
      {:deploy_update, ^group_name, ^status, _line} ->
        :ok

      {:deploy_update, ^group_name, {:error, reason}, _line} ->
        flunk("deploy errored: #{inspect(reason)}")

      {:deploy_update, ^group_name, _other, _line} ->
        assert_deploy_status(group_name, status, timeout)
    after
      timeout -> flunk("never reached status #{inspect(status)}")
    end
  end

  defp player_vm1_ip do
    repo_root = Path.expand("..", File.cwd!())

    {container_id, 0} =
      System.cmd("docker", ["compose", "ps", "-q", "player_vm1"], cd: repo_root)

    container_id = String.trim(container_id)

    if container_id == "" do
      flunk("player_vm1 isn't running, run `docker compose up -d player_vm1` first")
    end

    {ip, 0} =
      System.cmd(
        "docker",
        [
          "inspect",
          "-f",
          "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
          container_id
        ]
      )

    String.trim(ip)
  end

  defp cleanup(group) do
    ip = player_vm1_ip()

    System.cmd("ssh", [
      "-o",
      "StrictHostKeyChecking=no",
      "-o",
      "UserKnownHostsFile=/dev/null",
      "-i",
      Path.expand("../deploy/keys/id_ed25519", File.cwd!()),
      "deploy@#{ip}",
      "pkill -f beam.smp; rm -rf /home/deploy/releases/*"
    ])

    System.cmd("docker", [
      "compose",
      "run",
      "--rm",
      "-v",
      "#{group.path}:/src",
      "release_builder",
      "sh",
      "-c",
      "rm -rf /src/_build /src/deps"
    ])
  end
end
