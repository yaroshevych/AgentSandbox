# Container for claude / rust

FROM node:22-bookworm-slim

# All tool caches land in /cache — mount one named volume to persist across runs
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_TARGET_DIR=/cache/cargo-target \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go/build \
    npm_config_cache=/cache/npm \
    PNPM_HOME=/cache/pnpm/home \
    XDG_CACHE_HOME=/cache/xdg \
    UV_CACHE_DIR=/cache/uv

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates jq less unzip \
        ripgrep fd-find gh procps tmux \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable \
    && chmod -R a+w "${CARGO_HOME}" "${RUSTUP_HOME}"
ENV PATH="${CARGO_HOME}/bin:${PATH}"

RUN mkdir -p /cache /usr/local/share/npm-global \
    && chown node:node /cache /usr/local/share/npm-global

USER node

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH="/usr/local/share/npm-global/bin:/home/node/.claude/local:${PATH}"

RUN curl -fsSL https://claude.ai/install.sh | bash
