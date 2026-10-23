defmodule WikiRace.SkeletonTest do
  @moduledoc """
  The contract files under `lib/wiki_race/` are also vendored, byte for byte,
  into `player/lib/wiki_race/`. The skeleton every group starts from can't
  depend on this app (it can't pull in Phoenix and still be a Req/Floki-only
  release), so it needs its own copies.

  This test catches the two copies going out of sync, so a fix here can't
  be forgotten in `player/`'s copy until a group hits it on race day.
  """
  use ExUnit.Case, async: true

  @contract_files ~w(crawler.ex status.ex harness.ex)

  @player_dir Path.expand("../../../player/lib/wiki_race", __DIR__)
  @platform_dir Path.expand("../../lib/wiki_race", __DIR__)

  for file <- @contract_files do
    test "player/lib/wiki_race/#{file} matches the canonical copy" do
      file = unquote(file)
      canonical = File.read!(Path.join(@platform_dir, file))
      shipped = File.read!(Path.join(@player_dir, file))

      assert canonical == shipped, """
      platform/lib/wiki_race/#{file} and player/lib/wiki_race/#{file} \
      have drifted apart. Copy the canonical file over the shipped one:

          cp platform/lib/wiki_race/#{file} player/lib/wiki_race/#{file}
      """
    end
  end
end
