defmodule WikiRacePlatform.Tournament.Store do
  @moduledoc """
  Appends finished race results to a single file and reads them back on
  boot. This is the only piece of cross-race memory the platform has;
  everything else goes through this module, so swapping in a database later
  touches one place.

  Each entry is `%{result: Race.Result.t(), ended_at_utc: DateTime.t()}`,
  written with `:erlang.term_to_binary/1` and framed with a 4-byte length
  header, since concatenating raw term binaries in one file wouldn't
  otherwise say where one term ends and the next begins.
  """

  use GenServer

  alias WikiRacePlatform.Race.Result

  @type entry :: %{result: Result.t(), ended_at_utc: DateTime.t()}

  # Client

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    path = Keyword.get(opts, :path, default_path())
    GenServer.start_link(__MODULE__, path, name: name)
  end

  @doc "Appends a finished race's result, stamped with the current UTC time."
  @spec append(Result.t(), GenServer.server()) :: :ok
  def append(%Result{} = result, server \\ __MODULE__) do
    GenServer.call(server, {:append, result})
  end

  @doc "All stored entries, oldest first."
  @spec list(GenServer.server()) :: [entry()]
  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  @doc "Test-only: clears every entry and deletes the backing file."
  @spec clear(GenServer.server()) :: :ok
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  # Server

  @impl true
  def init(path) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, %{path: path, entries: read_all(path)}}
  end

  @impl true
  def handle_call({:append, result}, _from, state) do
    entry = %{result: result, ended_at_utc: DateTime.utc_now()}
    File.write!(state.path, frame(entry), [:append])
    {:reply, :ok, %{state | entries: state.entries ++ [entry]}}
  end

  def handle_call(:list, _from, state) do
    {:reply, state.entries, state}
  end

  def handle_call(:clear, _from, state) do
    File.rm(state.path)
    {:reply, :ok, %{state | entries: []}}
  end

  defp default_path do
    data_dir = Application.get_env(:wiki_race_platform, :tournament_store)[:data_dir]
    Path.join(data_dir, "results.terms")
  end

  defp frame(term) do
    binary = :erlang.term_to_binary(term)
    <<byte_size(binary)::32, binary::binary>>
  end

  defp read_all(path) do
    case File.read(path) do
      {:ok, binary} -> decode_all(binary, [])
      {:error, :enoent} -> []
    end
  end

  defp decode_all(<<>>, acc), do: Enum.reverse(acc)

  defp decode_all(<<size::32, term_binary::binary-size(size), rest::binary>>, acc) do
    decode_all(rest, [:erlang.binary_to_term(term_binary) | acc])
  end
end
