defmodule Mix.Tasks.WikiRace.Start do
  @moduledoc """
  Starts a group's already-deployed release as a daemon and waits for it to
  join the cluster.

      mix wiki_race.start GROUP

  Needs a prior `mix wiki_race.deploy GROUP` run. It can be an earlier,
  separate invocation: the target/cookie it recorded are reattached here.
  """

  use Mix.Task

  alias WikiRacePlatform.Deploy.CliState
  alias WikiRacePlatform.Deploy.Server, as: Deploy

  @shortdoc "Starts a group's deployed release and waits for it to join"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    group_name =
      case args do
        [name] -> name
        _ -> Mix.raise("usage: mix wiki_race.start GROUP")
      end

    case CliState.fetch(group_name) do
      {:ok, %{target: target, cookie: cookie}} ->
        Deploy.subscribe(group_name)
        Deploy.reattach!(group_name, target, cookie)

        case Deploy.start!(group_name) do
          :ok -> await_terminal(group_name)
          {:error, message} -> Mix.raise("start failed: #{message}")
        end

      :error ->
        Mix.raise(
          "no deploy recorded for #{inspect(group_name)}, run `mix wiki_race.deploy #{group_name}` first"
        )
    end
  end

  defp await_terminal(group_name) do
    receive do
      {:deploy_update, ^group_name, status, line} ->
        if line, do: Mix.shell().info(line)
        handle_status(group_name, status)
    after
      30_000 -> Mix.raise("timed out waiting for #{group_name} to join the cluster")
    end
  end

  defp handle_status(group_name, :running) do
    Mix.shell().info("#{group_name}: running and connected")
  end

  defp handle_status(group_name, {:error, reason}) do
    Mix.raise("#{group_name}: start failed: #{inspect(reason)}")
  end

  defp handle_status(group_name, _in_progress_status), do: await_terminal(group_name)
end
