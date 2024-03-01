FROM paradedb/paradedb:0.5.7

ARG PG_VERSION_MAJOR=16
ARG RUST_VERSION=1.76.0
ARG PGRX_VERSION=0.11.2
ARG PGVECTO_RS_VERSION=0.2.0

# Declare buildtime environment variables
ENV PG_VERSION_MAJOR=${PG_VERSION_MAJOR} \
    RUST_VERSION=${RUST_VERSION} \
    PGRX_VERSION=${PGRX_VERSION} \
    PGVECTO_RS_VERSION=${PGVECTO_RS_VERSION}

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    ca-certificates \
    build-essential \
    gnupg \
    curl \
    git \
    make \
    gcc \
    clang \
    pkg-config \
    postgresql-server-dev-all \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && /root/.cargo/bin/rustup default "${RUST_VERSION}"

ENV PATH="/root/.cargo/bin:$PATH" \
    PGX_HOME=/usr/lib/postgresql/${PG_VERSION_MAJOR}

RUN git clone --branch v${PGVECTO_RS_VERSION} https://github.com/tensorchord/pgvecto.rs

WORKDIR /pgvecto.rs

RUN cargo install cargo-pgrx@$(grep 'pgrx = { version' Cargo.toml | cut -d '"' -f 2)
RUN cargo pgrx init "--pg${PG_VERSION_MAJOR}=/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config"
RUN cargo pgrx install --release