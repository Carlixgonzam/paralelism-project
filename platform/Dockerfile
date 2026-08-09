# Pinned to match /.tool-versions (elixir 1.20.2-otp-28, erlang 28.5).
FROM hexpm/elixir:1.20.2-erlang-28.5.0.4-debian-bookworm-20260713-slim

RUN apt-get update -q && \
    apt-get install -y --no-install-recommends git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=dev

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . .
RUN mix assets.setup && mix assets.build

# Source is bind-mounted over this at runtime (see docker-compose.yml), so
# edits on the host take effect without rebuilding the image. Same
# live-edit behavior `mix phx.server` already gives outside a container.
CMD ["sh", "-c", "elixir --sname ${NODE_NAME:-platform@platform} --cookie ${ERL_COOKIE:?} -S mix phx.server"]
