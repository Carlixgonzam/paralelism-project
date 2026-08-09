defmodule WikiRacePlatform.Race.Verifier do
  @moduledoc """
  Checks that a reported path is a real chain of links in the offline snapshot.

  Nothing is scored on trust. A report is only accepted once every hop has been
  fetched from Kiwix and the next article was found among that page's links.
  Structural checks run first so an obviously wrong path costs no requests.
  """

  alias WikiRace.Status

  @receive_timeout 10_000
  @max_concurrency 8

  @doc """
  Verifies `path` runs from `start_url` to `target_url` one link at a time.

  Returns `:ok`, or `{:error, reason}` with a reason short enough to show on
  the dashboard.
  """
  @spec verify(Status.path(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def verify(path, start_url, target_url) do
    with :ok <- check_shape(path, start_url, target_url) do
      check_links(path)
    end
  end

  @doc """
  Runs only the structural checks, with no network access.

  Useful to reject junk before spending requests, and to keep tests offline.
  """
  @spec check_shape(Status.path(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def check_shape(path, start_url, target_url) do
    cond do
      not is_list(path) or Enum.any?(path, &(not is_binary(&1))) ->
        {:error, "path must be a list of URLs"}

      path == [] ->
        {:error, "path is empty"}

      canonical(List.first(path)) != canonical(start_url) ->
        {:error, "path does not start at the start article"}

      canonical(List.last(path)) != canonical(target_url) ->
        {:error, "path does not end at the target article"}

      length(path) < 2 ->
        {:error, "path is too short to be a walk"}

      duplicates?(path) ->
        {:error, "path visits the same article twice"}

      true ->
        :ok
    end
  end

  @doc """
  Turns a URL into the form used for comparisons.

  Kiwix links come back relative, percent-encoded and sometimes with a
  fragment, so raw string equality is not good enough.
  """
  @spec canonical(String.t()) :: String.t()
  def canonical(url) do
    uri = URI.parse(url)
    path = uri.path |> to_string() |> URI.decode() |> String.trim_trailing("/")
    "#{uri.scheme}://#{uri.host}#{port(uri)}#{path}"
  end

  defp port(%URI{scheme: "http", port: 80}), do: ""
  defp port(%URI{scheme: "https", port: 443}), do: ""
  defp port(%URI{port: nil}), do: ""
  defp port(%URI{port: port}), do: ":#{port}"

  defp duplicates?(path) do
    canonical = Enum.map(path, &canonical/1)
    length(Enum.uniq(canonical)) != length(canonical)
  end

  defp check_links(path) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Task.async_stream(&check_hop/1,
      max_concurrency: @max_concurrency,
      timeout: @receive_timeout + 5_000,
      on_timeout: :kill_task
    )
    |> Enum.find_value(:ok, fn
      {:ok, :ok} -> nil
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, _reason} -> {:error, "timed out checking a link"}
    end)
  end

  defp check_hop([from, to]) do
    with {:ok, body} <- fetch(from) do
      if MapSet.member?(links(body, from), canonical(to)) do
        :ok
      else
        {:error, "#{short(from)} does not link to #{short(to)}"}
      end
    end
  end

  # `:req_options` is the seam tests use to serve pages from a plug instead of
  # a real Kiwix instance.
  defp req_options do
    Application.get_env(:wiki_race_platform, :req_options, [])
  end

  defp fetch(url) do
    options = [receive_timeout: @receive_timeout, retry: false] ++ req_options()

    case Req.get(url, options) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "#{short(url)} returned HTTP #{status}"}

      {:error, reason} ->
        {:error, "could not fetch #{short(url)}: #{Exception.message(reason)}"}
    end
  end

  defp links(body, base) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        document
        |> Floki.attribute("a", "href")
        |> Enum.map(&resolve(&1, base))
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      _ ->
        MapSet.new()
    end
  end

  defp resolve("#" <> _rest, _base), do: nil
  defp resolve("javascript:" <> _rest, _base), do: nil
  defp resolve("mailto:" <> _rest, _base), do: nil

  defp resolve(href, base) do
    base |> URI.merge(href) |> URI.to_string() |> canonical()
  rescue
    _ -> nil
  end

  defp short(url) do
    url |> URI.parse() |> Map.get(:path) |> to_string() |> Path.basename() |> URI.decode()
  end
end
