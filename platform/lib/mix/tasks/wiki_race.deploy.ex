defmodule Mix.Tasks.WikiRace.Deploy do
  @moduledoc """
  Builds, uploads, and unpacks a group's release onto its player VM over SSH.

      mix wiki_race.deploy GROUP
      mix wiki_race.deploy GROUP --host player_vm1 --node groupa@player_vm1

  HOST/NODE default to that group's `host`/`node` fields in `priv/groups.exs`;
  pass `--host`/`--node` to override or when the manifest doesn't set them.
  Streams the build/upload log to the terminal and exits non-zero on
  failure. Deployment is terminal-only, there is no web UI for it. Follow
  up with `mix wiki_race.start GROUP` once this succeeds.
  """

  use Mix.Task

  alias WikiRacePlatform.Deploy.CliState
  alias WikiRacePlatform.Deploy.Manifest
  alias WikiRacePlatform.Deploy.Server, as: Deploy

  @shortdoc "Deploys a group's release to its player VM over SSH"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _invalid} =
      OptionParser.parse(args, strict: [host: :string, node: :string])

    group_name =
      case positional do
        [name] -> name
        _ -> Mix.raise("usage: mix wiki_race.deploy GROUP [--host HOST --node NODE]")
      end

    group = Manifest.group!(group_name)
    target = resolve_target(group, opts)
    cookie = :crypto.strong_rand_bytes(16) |> Base.encode16()

    Deploy.subscribe(group_name)

    case Deploy.deploy!(group_name, target, Deploy, cookie) do
      :ok ->
        await_terminal(group_name, target, cookie)

      {:error, message} ->
        Mix.raise("deploy failed: #{message}")
    end
  end

  defp resolve_target(group, opts) do
    host =
      opts[:host] || Map.get(group, :host) ||
        Mix.raise(
          "no --host given and no host configured in priv/groups.exs for #{group.name}"
        )

    node =
      case opts[:node] do
        nil ->
          Map.get(group, :node) ||
            Mix.raise(
              "no --node given and no node configured in priv/groups.exs for #{group.name}"
            )

        node_string ->
          String.to_atom(node_string)
      end

    %{host: host, node: node}
  end

  defp await_terminal(group_name, target, cookie) do
    receive do
      {:deploy_update, ^group_name, status, line} ->
        if line, do: Mix.shell().info(line)
        handle_status(group_name, target, cookie, status)
    after
      180_000 -> Mix.raise("timed out waiting for #{group_name} to deploy")
    end
  end

  defp handle_status(group_name, target, cookie, :stopped) do
    CliState.put(group_name, target, cookie)

    Mix.shell().info(
      "#{group_name}: deployed. Run `mix wiki_race.start #{inspect(group_name)}` next."
    )
  end

  defp handle_status(group_name, _target, _cookie, {:error, reason}) do
    Mix.raise("#{group_name}: deploy failed: #{inspect(reason)}")
  end

  defp handle_status(group_name, target, cookie, _in_progress_status) do
    await_terminal(group_name, target, cookie)
  end
end
