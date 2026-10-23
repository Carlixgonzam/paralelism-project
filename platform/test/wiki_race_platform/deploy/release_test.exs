defmodule WikiRacePlatform.Deploy.ReleaseTest do
  # Real `docker compose run` against `release_builder`. See `make
  # test-deploy` / `mix test --only integration`. Not part of the
  # Docker-free default `mix test` run.
  use ExUnit.Case, async: false

  @moduletag :integration

  alias WikiRacePlatform.Deploy.Manifest
  alias WikiRacePlatform.Deploy.Release

  test "builds a real release from the player/ skeleton and packages it into a tarball" do
    group = Manifest.group!("Local fixture")
    on_exit(fn -> cleanup(group) end)

    {:ok, agent} = Agent.start_link(fn -> [] end)
    on_output = fn line -> Agent.update(agent, fn lines -> [line | lines] end) end

    assert {:ok, tarball} = Release.build(group, on_output)
    assert File.exists?(tarball)
    assert Agent.get(agent, & &1) != []

    {output, 0} = System.cmd("tar", ["-tzf", tarball])
    assert output =~ "player/bin/player"

    File.rm(tarball)
  end

  defp cleanup(group) do
    System.cmd("docker", [
      "compose",
      "run",
      "--rm",
      "-v",
      "#{group.path}:/src",
      "release_builder",
      "sh",
      "-c",
      "rm -rf /src/_build /src/deps"
    ])
  end
end
