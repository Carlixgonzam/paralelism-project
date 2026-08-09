defmodule WikiRacePlatform.Race.Discovery do
  @moduledoc """
  Finds the module on a player node that implements `WikiRace.Crawler`.

  The contract deliberately says nothing about registration: a group only has
  to implement `start/2` and `status/1`. So the harness goes looking instead,
  asking the player node which of its loaded modules declares the behaviour.

  The scan is sent as source text and evaluated on the player node, which keeps
  it to one round trip and needs no platform code to be present over there. If
  a group's crawler module has not been loaded yet, or two modules declare the
  behaviour, the admin interface lets the professor name the module by hand.
  """

  require Logger

  @rpc_timeout 5_000

  # Everything a crawler node runs that did not come from the group. Skipping
  # these keeps the scan to the handful of modules that could plausibly be a
  # crawler, and it has to be a denylist because there is nothing in the
  # contract that says what a group calls its application.
  @infrastructure ~w(
    asn1 bandit castore compiler crypto db_connection decimal dns_cluster
    earmark_parser ecto ecto_sql eex elixir esbuild expo file_system finch
    floki gettext hex hpax inets iex jason kernel lazy_html logger makeup
    makeup_elixir makeup_erlang mime mint mix nimble_options nimble_ownership
    nimble_pool nimble_parsec os_mon phoenix phoenix_ecto phoenix_html
    phoenix_live_dashboard phoenix_live_reload phoenix_live_view
    phoenix_pubsub phoenix_template plug plug_crypto postgrex public_key
    req runtime_tools sasl ssl ssl_verify_fun stdlib swoosh syntax_tools
    tailwind telemetry telemetry_metrics telemetry_poller thousand_island
    tls_certificate_check websock websock_adapter xmerl
  )

  # Sent as source and evaluated on the player node, so the scan needs nothing
  # from the platform to be present over there.
  @scan_source """
  infrastructure = #{inspect(Enum.map(@infrastructure, &String.to_atom/1))}

  from_apps =
    Application.loaded_applications()
    |> Enum.map(fn {app, _description, _vsn} -> app end)
    |> Enum.reject(fn app -> app in infrastructure end)
    |> Enum.flat_map(fn app ->
      case :application.get_key(app, :modules) do
        {:ok, modules} -> modules
        _ -> []
      end
    end)

  from_code = Enum.map(:code.all_loaded(), fn {mod, _path} -> mod end)

  (from_apps ++ from_code)
  |> Enum.uniq()
  |> Enum.filter(fn mod ->
    try do
      Code.ensure_loaded?(mod) and
        mod.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()
        |> Enum.member?(WikiRace.Crawler)
    rescue
      _ -> false
    end
  end)
  """

  @doc """
  Returns the crawler module loaded on `node`.

  Fails with `:not_found` when nothing on the node declares the behaviour, and
  with `{:ambiguous, modules}` when more than one does.
  """
  @spec crawler_module(node()) ::
          {:ok, module()} | {:error, :not_found | {:ambiguous, [module()]} | term()}
  def crawler_module(node) do
    case :rpc.call(node, Code, :eval_string, [@scan_source], @rpc_timeout) do
      {[module], _bindings} ->
        {:ok, module}

      {[], _bindings} ->
        {:error, :not_found}

      {modules, _bindings} when is_list(modules) ->
        {:error, {:ambiguous, modules}}

      {:badrpc, reason} ->
        Logger.warning("crawler scan failed on #{inspect(node)}: #{inspect(reason)}")
        {:error, {:badrpc, reason}}

      other ->
        {:error, {:unexpected, other}}
    end
  end

  @doc """
  Resolves the module for a player spec, honouring a manual override.

  Returns the spec with `:module` filled in, or an error string ready to show
  on the dashboard.
  """
  @spec resolve(map()) :: {:ok, module()} | {:error, String.t()}
  def resolve(%{module: module}) when is_atom(module) and not is_nil(module) do
    {:ok, module}
  end

  def resolve(%{node: node}) do
    case crawler_module(node) do
      {:ok, module} -> {:ok, module}
      {:error, reason} -> {:error, describe(node, reason)}
    end
  end

  defp describe(node, :not_found),
    do: "no module on #{node} implements WikiRace.Crawler"

  defp describe(node, {:ambiguous, modules}),
    do: "#{node} has several crawler modules (#{Enum.join(modules, ", ")}), pick one"

  defp describe(node, {:badrpc, :nodedown}), do: "#{node} is not reachable"

  defp describe(node, reason), do: "could not inspect #{node}: #{inspect(reason)}"
end
