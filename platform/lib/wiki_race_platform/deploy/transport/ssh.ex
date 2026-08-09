defmodule WikiRacePlatform.Deploy.Transport.SSH do
  @moduledoc """
  The real deploy transport: Erlang's own `:ssh`/`:ssh_sftp`/`:ssh_connection`
  modules, never a shelled-out `ssh` binary.

  Authenticates with a key pair under `opts[:user_dir]` (see
  `Deploy.Transport.connect/2`). This is the dev keypair `make deploy-keys`
  generates for the docker-simulated player VMs, or a real deployment key
  for a real player VM.
  """

  @behaviour WikiRacePlatform.Deploy.Transport

  @exec_timeout 30_000

  @impl WikiRacePlatform.Deploy.Transport
  def connect(host, opts) do
    ssh_opts =
      [
        user: to_charlist(Keyword.fetch!(opts, :user)),
        user_dir: to_charlist(Keyword.fetch!(opts, :user_dir)),
        silently_accept_hosts: true,
        save_accepted_host: false
      ]

    case :ssh.connect(
           to_charlist(host),
           Keyword.get(opts, :port, 22),
           ssh_opts,
           @exec_timeout
         ) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl WikiRacePlatform.Deploy.Transport
  def upload(conn, local_path, remote_path) do
    with {:ok, sftp} <- :ssh_sftp.start_channel(conn, []),
         {:ok, contents} <- File.read(local_path),
         :ok <- :ssh_sftp.write_file(sftp, to_charlist(remote_path), contents) do
      :ssh_sftp.stop_channel(sftp)
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl WikiRacePlatform.Deploy.Transport
  def exec(conn, command) do
    with {:ok, channel} <- :ssh_connection.session_channel(conn, @exec_timeout),
         :success <-
           :ssh_connection.exec(conn, channel, to_charlist(command), @exec_timeout) do
      collect(conn, channel, "", nil)
    else
      :failure -> {:error, :exec_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl WikiRacePlatform.Deploy.Transport
  def close(conn), do: :ssh.close(conn)

  defp collect(conn, channel, output, exit_status) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        collect(conn, channel, output <> data, exit_status)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        collect(conn, channel, output, exit_status)

      {:ssh_cm, ^conn, {:exit_status, ^channel, status}} ->
        collect(conn, channel, output, status)

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        {:ok, output, exit_status || 0}
    after
      @exec_timeout -> {:error, :timeout}
    end
  end
end
