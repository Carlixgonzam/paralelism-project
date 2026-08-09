defmodule WikiRacePlatform.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {DNSCluster,
         query: Application.get_env(:wiki_race_platform, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: WikiRacePlatform.PubSub},
        {Task.Supervisor, name: WikiRacePlatform.Race.TaskSupervisor},
        {DynamicSupervisor,
         name: WikiRacePlatform.Race.InstanceSupervisor, strategy: :one_for_one}
      ] ++ web() ++ harness()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WikiRacePlatform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Can run on its own node, separate from the harness below. That way the
  # node players connect to holds no deploy secrets, results history, or
  # admin UI. A single-node dev/test setup runs both (the default).
  defp web do
    if Application.get_env(:wiki_race_platform, :start_web, true) do
      [
        WikiRacePlatformWeb.Telemetry,
        WikiRacePlatform.Tournament.Store,
        WikiRacePlatform.Tournament.Server,
        {Task.Supervisor, name: WikiRacePlatform.Deploy.TaskSupervisor}
      ] ++ deploy_server() ++ [WikiRacePlatformWeb.Endpoint]
    else
      []
    end
  end

  # Uses real :ssh/mix-release calls by default, so tests start their own
  # instance (with a fake transport/release builder) instead of the
  # application-wide one. Same reasoning as `harness/0` below.
  defp deploy_server do
    if Application.get_env(:wiki_race_platform, :start_deploy_server, true) do
      [WikiRacePlatform.Deploy.Server]
    else
      []
    end
  end

  # The dispatcher claims a `:global` name, so tests start their own instance
  # instead of fighting the application-wide one. Its task/instance
  # supervisors stay always-on above: empty, inert shells on a node that
  # never runs a race.
  defp harness do
    if Application.get_env(:wiki_race_platform, :start_harness, true) do
      [WikiRacePlatform.Race.Dispatcher]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WikiRacePlatformWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
