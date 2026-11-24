# ==========================================
# STAGE 1: Base Elixir + ImageMagick (Shared)
# ==========================================
FROM elixir:1.19-slim AS base

ENV LANG=C.UTF-8

# Install build tools + ImageMagick with WebP delegates for thumbnail generation
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libzstd-dev \
    imagemagick \
    libwebp-dev \
    webp \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && \
    mix local.rebar --force

WORKDIR /app

# ==========================================
# STAGE 2: Test Stage (For Local & CircleCI)
# ==========================================
FROM base AS test

ENV MIX_ENV=test

COPY mix.exs mix.lock ./
COPY config ./config

RUN mix deps.get
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
COPY test test

RUN mix compile --warnings-as-errors

CMD ["mix", "test"]

# ==========================================
# STAGE 3: Build the Production Release
# ==========================================
FROM base AS builder

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs ./config/

RUN mix deps.get --only prod
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.setup
RUN mix assets.deploy
RUN mix compile

COPY config/runtime.exs ./config/

# Note: Make sure release name matches your mix.exs (ash_phoenix_starter vs AshPhoenixStarter)
RUN mix release --overwrite

# ==========================================
# STAGE 4: Lightweight Runtime Environment
# ==========================================
FROM debian:bookworm-slim AS runner

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true

# Install runtime OS libraries + ImageMagick & WebP for thumbnail processing
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libzstd1 \
    imagemagick \
    webp \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/AshPhoenixStarter ./
COPY --chown=nobody:root start.sh ./start.sh

USER nobody
EXPOSE 10000

CMD ["/app/start.sh"]
