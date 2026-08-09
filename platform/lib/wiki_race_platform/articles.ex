defmodule WikiRacePlatform.Articles do
  @moduledoc """
  The curated start/target article pool, and how titles become URLs.

  `priv/article_pairs.exs` is the only source of article pairs. Every real
  race uses one fixed, professor-chosen pair from this pool for the whole
  tournament, so wait times stay predictable instead of risking a
  randomly-drawn pair that is many hops apart.
  """

  @pool_file "article_pairs.exs"
  @request_timeout 5_000

  @type pair :: %{start: String.t(), target: String.t(), note: String.t()}

  @doc "Every pair in the curated pool, in file order."
  @spec pairs() :: [pair()]
  def pairs do
    {pairs, _bindings} = Code.eval_file(pool_path())
    Enum.map(pairs, fn pair -> Map.put_new(pair, :note, "") end)
  end

  @doc """
  The Kiwix URL for an article title.

  This is the exact string handed to `c:WikiRace.Crawler.start/2`, so it must
  be fetchable as-is. Kiwix uses underscores for spaces, so titles are
  written here the readable way and converted.
  """
  @spec url(String.t()) :: String.t()
  def url(title) do
    slug = title |> String.replace(" ", "_") |> URI.encode()
    "#{base_url()}/content/#{book()}/#{slug}"
  end

  @doc "The start and target URLs for a pair."
  @spec urls(pair()) :: {String.t(), String.t()}
  def urls(%{start: start_title, target: target_title}) do
    {url(start_title), url(target_title)}
  end

  @doc """
  Fetches every article in the pool and reports the ones Kiwix does not have.

  Run this after editing the pool. A pair with a wrong title will fail a race
  in a way that looks like a crawler bug, which is a bad way to find out.
  """
  @spec check_pairs() :: :ok | {:missing, [String.t()]}
  def check_pairs do
    missing =
      pairs()
      |> Enum.flat_map(fn pair -> [pair.start, pair.target] end)
      |> Enum.uniq()
      |> Task.async_stream(fn title -> {title, reachable?(url(title))} end,
        max_concurrency: 8,
        timeout: @request_timeout + 2_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {_title, true}} -> []
        {:ok, {title, false}} -> [title]
        {:exit, _reason} -> ["(timed out)"]
      end)

    if missing == [], do: :ok, else: {:missing, missing}
  end

  @doc "Where the offline snapshot is served from."
  @spec base_url() :: String.t()
  def base_url, do: Keyword.fetch!(kiwix(), :base_url)

  @doc "The name of the ZIM book Kiwix is serving."
  @spec book() :: String.t()
  def book, do: Keyword.fetch!(kiwix(), :book)

  defp kiwix, do: Application.fetch_env!(:wiki_race_platform, :kiwix)

  defp pool_path do
    Application.app_dir(:wiki_race_platform, ["priv", @pool_file])
  end

  defp reachable?(url) do
    case Req.get(url, receive_timeout: @request_timeout, retry: false) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end
end
