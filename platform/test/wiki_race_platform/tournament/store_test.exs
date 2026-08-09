defmodule WikiRacePlatform.Tournament.StoreTest do
  use ExUnit.Case, async: true

  alias WikiRacePlatform.Race.Result
  alias WikiRacePlatform.Tournament.Store

  @result Result.build([], :all_settled, 123)

  defp tmp_path do
    Path.join(
      System.tmp_dir!(),
      "tournament_store_test_#{System.unique_integer([:positive])}.terms"
    )
  end

  defp start_store(id, path, name) do
    spec = %{id: id, start: {Store, :start_link, [[path: path, name: name]]}}
    start_supervised!(spec)
  end

  test "a fresh store with no file on disk starts out empty" do
    path = tmp_path()
    name = :"store_#{System.unique_integer([:positive])}"
    start_store(:empty_store, path, name)

    assert Store.list(name) == []
  end

  test "append/2 is visible from list/1 right away" do
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)
    name = :"store_#{System.unique_integer([:positive])}"
    start_store(:append_store, path, name)

    assert :ok = Store.append(@result, name)

    assert [entry] = Store.list(name)
    assert entry.result == @result
    assert %DateTime{} = entry.ended_at_utc
  end

  test "multiple appends round-trip in order" do
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)
    name = :"store_#{System.unique_integer([:positive])}"
    start_store(:multi_store, path, name)

    other_result = Result.build([], :time_limit, 456)
    :ok = Store.append(@result, name)
    :ok = Store.append(other_result, name)

    assert [first, second] = Store.list(name)
    assert first.result == @result
    assert second.result == other_result
  end

  test "a new instance reads back entries a previous one wrote, simulating a restart" do
    path = tmp_path()
    on_exit(fn -> File.rm(path) end)
    name1 = :"store_#{System.unique_integer([:positive])}"
    name2 = :"store_#{System.unique_integer([:positive])}"

    start_store(:restart_before, path, name1)
    :ok = Store.append(@result, name1)
    stop_supervised!(:restart_before)

    start_store(:restart_after, path, name2)

    assert [entry] = Store.list(name2)
    assert entry.result == @result
  end
end
