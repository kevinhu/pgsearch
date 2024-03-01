ARG PG_VERSION_MAJOR=16

###############################################
# First Stage: Builder
###############################################

# We build the extensions on the official PostgreSQL image, since the Bitnami
# image does not have root access and necessary build tools
FROM postgres:${PG_VERSION_MAJOR}-bullseye as builder

ARG PG_VERSION_MAJOR=16

ARG RUST_VERSION=1.76.0
ARG PGRX_VERSION=0.11.2
ARG PGVECTO_RS_VERSION=0.2.0
ARG PARADEDB_VERSION=0.5.7

# Declare buildtime environment variables
ENV PG_VERSION_MAJOR=${PG_VERSION_MAJOR} \
    RUST_VERSION=${RUST_VERSION} \
    PGVECTO_RS_VERSION=${PGVECTO_RS_VERSION} \
    PGRX_VERSION=${PGRX_VERSION} \
    PARADEDB_VERSION=${PARADEDB_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    ca-certificates \
    build-essential \
    gnupg \
    curl \
    git \
    make \
    gcc \
    clang-16 \
    pkg-config \
    postgresql-server-dev-all \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && /root/.cargo/bin/rustup default "${RUST_VERSION}"

ENV PATH="/root/.cargo/bin:$PATH" \
    PGX_HOME=/usr/lib/postgresql/${PG_VERSION_MAJOR} \
    PG_VERSION_MAJOR=${PG_VERSION_MAJOR}

RUN cargo install --locked cargo-pgrx --version "${PGRX_VERSION}"
RUN cargo pgrx init --pg${PG_VERSION_MAJOR}=/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config

######################
# pg_bm25
######################
FROM builder as builder-pg_bm25

RUN git clone --branch v${PARADEDB_VERSION} https://github.com/paradedb/paradedb
RUN cd paradedb/pg_bm25 && cargo pgrx package --features icu --pg-config "/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config"

######################
# pgvecto.rs
######################
FROM builder as builder-pgvecto_rs

RUN git clone --branch v${PGVECTO_RS_VERSION} https://github.com/tensorchord/pgvecto.rs
RUN cd pgvecto.rs && cargo pgrx package --pg-config "/usr/lib/postgresql/${PG_VERSION_MAJOR}/bin/pg_config"

###############################################
# Second Stage: PostgreSQL
###############################################

FROM bitnami/postgresql:${PG_VERSION_MAJOR}-debian-11 as pgsearch

ARG PG_VERSION_MAJOR=16

ENV PG_VERSION_MAJOR=${PG_VERSION_MAJOR} \
    POSTHOG_API_KEY='' \
    POSTHOG_HOST='' \
    PARADEDB_TELEMETRY=false

COPY --from=builder-pgvecto_rs /pgvecto.rs/target/release/vectors-pg${PG_VERSION_MAJOR}/usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/* /opt/bitnami/postgresql/lib/
COPY --from=builder-pgvecto_rs /pgvecto.rs/target/release/vectors-pg${PG_VERSION_MAJOR}/usr/share/postgresql/${PG_VERSION_MAJOR}/extension/* /opt/bitnami/postgresql/share/extension/

COPY --from=builder-pg_bm25 /paradedb/pg_bm25/target/release/pg_bm25-pg${PG_VERSION_MAJOR}/usr/lib/postgresql/${PG_VERSION_MAJOR}/lib/* /opt/bitnami/postgresql/lib/
COPY --from=builder-pg_bm25 /paradedb/pg_bm25/target/release/pg_bm25-pg${PG_VERSION_MAJOR}/usr/share/postgresql/${PG_VERSION_MAJOR}/extension/* /opt/bitnami/postgresql/share/extension/

# Install runtime dependencies (requires switching to root temporarily)
USER root
RUN install_packages curl uuid-runtime libpq5
USER 1001

# Copy ParadeDB bootstrap script to install extensions, configure postgresql.conf, etc.
# COPY ./docker/01_bootstrap.sh /docker-entrypoint-initdb.d/
COPY ./01_bootstrap.sh /docker-entrypoint-initdb.d/

# Configure shared_preload_libraries
# Note: pgaudit is needed here as it comes pre-packaged in the Bitnami image
ENV POSTGRESQL_SHARED_PRELOAD_LIBRARIES="pgaudit,pg_bm25,vectors"