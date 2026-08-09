defmodule WikiRacePlatform.FakeKiwix do
  @moduledoc """
  A tiny wiki served over real HTTP, so the crawler under test does exactly
  what it would do against Kiwix.

  Pages live under `/content/wiki/`, links between them are relative, and there
  is some non-article noise mixed in for the link filter to throw away.
  """

  @behaviour Plug

  @pages %{
    "Elixir" => ~w(BEAM Ruby),
    "BEAM" => ~w(Erlang),
    "Ruby" => ~w(Elixir),
    "Erlang" => ~w(BEAM),
    "Island" => []
  }

  @port 4589

  @doc "The base URL of the fake wiki."
  @spec base_url() :: String.t()
  def base_url, do: "http://127.0.0.1:#{@port}/content/wiki"

  @doc "The URL of one article."
  @spec article(String.t()) :: String.t()
  def article(title), do: "#{base_url()}/#{title}"

  @doc "A child spec that serves the wiki on a fixed port."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Supervisor.child_spec({Bandit, plug: __MODULE__, port: @port, startup_log: false},
      id: __MODULE__
    )
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
    case Map.fetch(@pages, title) do
      {:ok, links} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, page(title, links))

      :error ->
        Plug.Conn.send_resp(conn, 404, "no such article")
    end
  end

  # The stylesheet, the Kiwix machinery link and the fragment are all things a
  # crawler must not follow.
  defp page(title, links) do
    body = Enum.map_join(links, "", fn link -> ~s(<a href="#{link}">#{link}</a>) end)

    """
    <html>
      <head><link rel="stylesheet" href="style.css"></head>
      <body>
        <h1>#{title}</h1>
        #{body}
        <a href="../-/search?q=#{title}">search</a>
        <a href="#top">top</a>
      </body>
    </html>
    """
  end
end
