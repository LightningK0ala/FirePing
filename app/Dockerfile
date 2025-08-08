# Build stage
FROM elixir:1.15.7-otp-26-alpine as build

# Install build dependencies
RUN apk add --no-cache build-base git python3 cmake

# Create app directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only=prod
RUN mix deps.compile

# Copy source code
COPY . .

# Build assets using Mix (esbuild/tailwind)
RUN mix assets.deploy

# Compile and build release
RUN mix compile
RUN mix release

# Runtime stage
FROM alpine:3.18 as runtime

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

# Create app user
RUN addgroup -g 1001 -S app && \
    adduser -S -D -H -u 1001 -h /app -s /bin/sh -G app app

# Set the locale
ENV LANG en_US.UTF-8

# Set environment
ENV MIX_ENV=prod
ENV PHX_SERVER=true

WORKDIR /app

# Copy the release from build stage
COPY --from=build --chown=app:app /app/_build/prod/rel/app ./

USER app

EXPOSE 4000

CMD ["./bin/app", "start"]

# Development stage
FROM elixir:1.15.7-otp-26-alpine as dev

# Install development dependencies
RUN apk add --no-cache build-base git python3 cmake inotify-tools bash

# Create app directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set dev environment
ENV MIX_ENV=dev

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get
RUN mix deps.compile

# Copy source code
COPY . .

# Update deps after copying source (heroicons git dependency needs this)
RUN mix deps.get

# Compile in dev mode
RUN mix compile

EXPOSE 4000

CMD ["mix", "phx.server"]