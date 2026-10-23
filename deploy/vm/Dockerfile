# Doubles as two things, both pinned to platform/player's exact base image
# so a release built here is binary-compatible with where it runs:
# - player_vm1/player_vm2: a local stand-in for a bare player VM. Just
#   sshd and an unprivileged user to unpack and run a release into. No
#   Elixir/mix needed at runtime, a `mix release` ships its own ERTS.
# - release_builder: the same image, invoked via `docker compose run` to
#   build a group's release (needs mix/hex, unused by the sshd role).
FROM hexpm/elixir:1.20.2-erlang-28.5.0.4-debian-bookworm-20260713-slim

RUN apt-get update -q && \
    apt-get install -y --no-install-recommends openssh-server && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd && \
    mix local.hex --force && mix local.rebar --force

# `-p '*'` avoids a locked (`!`) password field. OpenSSH refuses even
# pubkey auth for a locked account, and this user is never meant to log in
# with a password at all.
RUN useradd --create-home --shell /bin/bash -p '*' deploy && \
    mkdir -p /home/deploy/.ssh /home/deploy/releases && \
    chown -R deploy:deploy /home/deploy

COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22

# /run and /home/deploy/releases are tmpfs at container runtime (a
# read-only rootfs). Both always start empty, root-owned, on every boot,
# so sshd's privilege-separation directory and the deploy user's own
# scratch space are recreated (and re-chowned) here rather than relying on
# anything surviving from the image layer.
CMD ["sh", "-c", "mkdir -p /run/sshd && chown deploy:deploy /home/deploy/releases && exec /usr/sbin/sshd -D -e"]
