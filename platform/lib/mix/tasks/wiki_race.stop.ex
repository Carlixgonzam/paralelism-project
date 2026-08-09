defmodule Mix.Tasks.WikiRace.Stop do
  @moduledoc """
  Stops a group's running release.

      mix wiki_race.stop GROUP

  Needs the target/cookie an earlier `mix wiki_race.deploy GROUP` recorded
  (reattached here, same as `mix wiki_race.start`).
  """

  use Mix.Task

  alias WikiRacePlatform.Deploy.CliState
  alias WikiRacePlatform.Deploy.Server, as: Deploy

  @shortdoc "Stops a group's running release"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    group_name =
      case args do
        [name] -> name
        _ -> Mix.raise("usage: mix wiki_race.stop GROUP")
      end

    case CliState.fetch(group_name) do
      {:ok, %{target: target, cookie: cookie}} ->
        Deploy.subscribe(group_name)
        Deploy.reattach!(group_name, target, cookie)

        case Deploy.stop!(group_name) do
          :ok -> await_terminal(group_name)
          {:error, message} -> Mix.raise("stop failed: #{message}")
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
      30_000 -> Mix.raise("timed out waiting for #{group_name} to stop")
    end
  end

  defp handle_status(group_name, :stopped) do
    Mix.shell().info("#{group_name}: stopped")
  end

  defp handle_status(group_name, {:error, reason}) do
    Mix.raise("#{group_name}: stop failed: #{inspect(reason)}")
  end

  defp handle_status(group_name, _in_progress_status), do: await_terminal(group_name)
end
