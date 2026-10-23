defmodule WikiRacePlatform.FakeWiki do
  @moduledoc """
  A configurable wiki served over real HTTP, for tests that need a specific
  link graph. `FakeKiwix` only serves a fixed graph, so tests of
  dual-frontier meeting behavior, fetch deduplication, and transient-failure
  retries use this module instead.

  Start fresh per test with `start_link/1`, passing `%{title => [links]}`.
  Tracks how many times each title was actually fetched (`hits/1`) and can
  be told to fail a title's first N requests before succeeding
  (`fail_first/2`), to test retry behavior against a real HTTP round trip.
  """

  @behaviour Plug

  @port 4591

  @doc "The base URL of the fake wiki."
  @spec base_url() :: String.t()
  def base_url, do: "http://127.0.0.1:#{@port}/content/wiki"

  @doc "The URL of one article."
  @spec article(String.t()) :: String.t()
  def article(title), do: "#{base_url()}/#{title}"

  @doc "A child spec starting the graph state and the HTTP server together, for `start_supervised!({FakeWiki, pages})`."
  @spec child_spec(%{String.t() => [String.t()]}) :: Supervisor.child_spec()
  def child_spec(pages) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [pages]}, type: :supervisor}
  end

  @doc false
  def start_link(pages) do
    children = [
      %{
        id: __MODULE__.State,
        start:
          {Agent, :start_link,
           [fn -> %{pages: pages, hits: %{}, fail_first: %{}} end, [name: __MODULE__]]}
      },
      Supervisor.child_spec({Bandit, plug: __MODULE__, port: @port, startup_log: false},
        id: __MODULE__.Endpoint
      )
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc "How many times `title` has actually been requested."
  @spec hits(String.t()) :: non_neg_integer()
  def hits(title), do: Agent.get(__MODULE__, fn s -> Map.get(s.hits, title, 0) end)

  @doc "Makes the first `count` requests for `title` return a 503, then succeed."
  @spec fail_first(String.t(), non_neg_integer()) :: :ok
  def fail_first(title, count) do
    Agent.update(__MODULE__, fn s -> put_in(s.fail_first[title], count) end)
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case conn.path_info do
      ["content", "wiki", title] -> serve(conn, title)
      _ -> Plug.Conn.send_resp(conn, 404, "not found")
    end
  end

  defp serve(conn, title) do
    if should_fail?(title) do
      Plug.Conn.send_resp(conn, 503, "temporarily unavailable")
    else
      respond(conn, title)
    end
  end

  defp should_fail?(title) do
    Agent.get_and_update(__MODULE__, fn s ->
      remaining = Map.get(s.fail_first, title, 0)
      hits = Map.update(s.hits, title, 1, &(&1 + 1))

      if remaining > 0 do
        {true, %{s | hits: hits, fail_first: Map.put(s.fail_first, title, remaining - 1)}}
      else
        {false, %{s | hits: hits}}
      end
    end)
  end

  defp respond(conn, title) do
    case Agent.get(__MODULE__, fn s -> Map.fetch(s.pages, title) end) do
      {:ok, links} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, page(title, links))

      :error ->
        Plug.Conn.send_resp(conn, 404, "no such article")
    end
  end

  defp page(title, links) do
    body = Enum.map_join(links, "", fn link -> ~s(<a href="#{link}">#{link}</a>) end)
    "<html><body><h1>#{title}</h1>#{body}</body></html>"
  end
end
