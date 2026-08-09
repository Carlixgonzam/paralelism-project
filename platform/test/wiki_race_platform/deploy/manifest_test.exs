defmodule WikiRacePlatform.Deploy.ManifestTest do
  use ExUnit.Case, async: true

  alias WikiRacePlatform.Deploy.Manifest

  test "the local fixture group is in the manifest, pointing at the real player/ skeleton" do
    # The manifest may hold other groups too (real ones, or a local
    # multi-node test fixture). Find "Local fixture" rather than assuming
    # it's the only entry.
    assert %{name: "Local fixture", app: :player, path: path} =
             Enum.find(Manifest.groups(), &(&1.name == "Local fixture"))

    assert File.dir?(path)
    assert File.exists?(Path.join(path, "mix.exs"))
  end

  test "group! finds a group by name" do
    assert Manifest.group!("Local fixture").app == :player
  end

  test "group! raises for an unknown name instead of returning nil" do
    assert_raise RuntimeError, ~r/no group named/, fn ->
      Manifest.group!("Group Nonexistent")
    end
  end

  test "check_groups passes against the real manifest and checkout" do
    assert Manifest.check_groups() == :ok
  end
end
