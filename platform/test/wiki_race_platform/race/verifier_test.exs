defmodule WikiRacePlatform.Race.VerifierTest do
  use ExUnit.Case, async: true

  alias WikiRacePlatform.Race.Verifier

  @base "http://kiwix.test/content/wiki"
  @start "#{@base}/Elixir"
  @target "#{@base}/Erlang"

  describe "check_shape/3" do
    test "accepts a walk from start to target" do
      path = [@start, "#{@base}/BEAM", @target]
      assert :ok = Verifier.check_shape(path, @start, @target)
    end

    test "rejects an empty path" do
      assert {:error, "path is empty"} = Verifier.check_shape([], @start, @target)
    end

    test "rejects a path that starts somewhere else" do
      path = ["#{@base}/Ruby", @target]
      assert {:error, reason} = Verifier.check_shape(path, @start, @target)
      assert reason =~ "does not start"
    end

    test "rejects a path that never reaches the target" do
      path = [@start, "#{@base}/BEAM"]
      assert {:error, reason} = Verifier.check_shape(path, @start, @target)
      assert reason =~ "does not end"
    end

    test "rejects a single article, since a walk needs at least one hop" do
      assert {:error, reason} = Verifier.check_shape([@start], @start, @start)
      assert reason =~ "too short"
    end

    test "rejects a path that revisits an article" do
      path = [@start, "#{@base}/BEAM", @start, @target]
      assert {:error, reason} = Verifier.check_shape(path, @start, @target)
      assert reason =~ "twice"
    end

    test "rejects anything that is not a list of URLs" do
      assert {:error, reason} = Verifier.check_shape([@start, :atom], @start, @target)
      assert reason =~ "list of URLs"
    end

    test "ignores fragments, trailing slashes and percent encoding" do
      path = ["#{@base}/Elixir#top", "#{@base}/BEAM", "#{@target}/"]
      assert :ok = Verifier.check_shape(path, @start, @target)
    end
  end

  describe "canonical/1" do
    test "decodes the path and drops the fragment" do
      assert Verifier.canonical("#{@base}/Ada%20Lovelace#life") ==
               "#{@base}/Ada Lovelace"
    end
  end

  describe "verify/3 against a stubbed Kiwix" do
    setup do
      pages = %{
        "/content/wiki/Elixir" =>
          ~s(<a href="BEAM">beam</a><a href="Ruby">ruby</a><a href="Ghost">ghost</a>),
        "/content/wiki/BEAM" => ~s(<a href="Erlang">erlang</a>),
        "/content/wiki/Ruby" => ~s(<a href="Elixir">back</a>),
        "/content/wiki/Erlang" => ~s(<a href="BEAM">beam</a>)
      }

      Application.put_env(:wiki_race_platform, :req_options,
        plug: fn conn ->
          case Map.fetch(pages, conn.request_path) do
            {:ok, body} -> Req.Test.html(conn, body)
            :error -> Plug.Conn.send_resp(conn, 404, "not found")
          end
        end
      )

      on_exit(fn -> Application.delete_env(:wiki_race_platform, :req_options) end)
    end

    test "accepts a path where every hop is really linked" do
      path = [@start, "#{@base}/BEAM", @target]
      assert :ok = Verifier.verify(path, @start, @target)
    end

    test "rejects a hop that does not exist on the page" do
      path = [@start, "#{@base}/Ruby", @target]
      assert {:error, reason} = Verifier.verify(path, @start, @target)
      assert reason =~ "Ruby does not link to Erlang"
    end

    test "rejects a path through an article that is not in the snapshot" do
      path = [@start, "#{@base}/Ghost", @target]
      assert {:error, reason} = Verifier.verify(path, @start, @target)
      assert reason =~ "HTTP 404"
    end

    test "structural problems are caught before any request" do
      path = ["#{@base}/Ruby", @target]
      assert {:error, reason} = Verifier.verify(path, @start, @target)
      assert reason =~ "does not start"
    end
  end
end
