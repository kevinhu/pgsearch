ARG PG_VERSION_MAJOR=16

# FROM bitnami/postgresql:${PG_VERSION_MAJOR}-debian-12 as pgsearch
FROM postgres:${PG_VERSION_MAJOR}-bookworm as pgsearch

ARG PG_VERSION_MAJOR=16
ARG PLATFORM=amd64

ENV PG_VERSION_MAJOR=${PG_VERSION_MAJOR} \
    POSTHOG_API_KEY='' \
    POSTHOG_HOST='' \
    PARADEDB_TELEMETRY=false \
    PLATFORM=${PLATFORM}

# Install runtime dependencies (requires switching to root temporarily)
USER root
RUN apt-get update
RUN apt-get remove libicu-dev -y
RUN apt-get install curl uuid-runtime libpq5 -y
RUN apt-get install postgresql-server-dev-all postgresql-16-cron -y

RUN curl -fsSL https://github.com/paradedb/paradedb/releases/download/v0.5.7/pg_bm25-v0.5.7-pg16-${PLATFORM}-ubuntu2204.deb -o /tmp/pg_bm25.deb
RUN dpkg -i /tmp/pg_bm25.deb

RUN curl -fsSL https://github.com/tensorchord/pgvecto.rs/releases/download/v0.2.0/vectors-pg16_0.2.0_${PLATFORM}.deb -o /tmp/vectors.deb
RUN dpkg -i /tmp/vectors.deb

RUN if [ "$PLATFORM" = "arm64" ]; then curl -fsSL http://ports.ubuntu.com/pool/main/i/icu/libicu70_70.1-2_arm64.deb -o /tmp/libicu70.deb; else curl -fsSL http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2_amd64.deb -o /tmp/libicu70.deb; fi
RUN dpkg -i /tmp/libicu70.deb
USER 1001

# Copy ParadeDB bootstrap script to install extensions, configure postgresql.conf, etc.
# COPY ./docker/01_bootstrap.sh /docker-entrypoint-initdb.d/
COPY ./01_bootstrap.sh /docker-entrypoint-initdb.d/

# Configure shared_preload_libraries
# Note: pgaudit is needed here as it comes pre-packaged in the Bitnami image
ENV POSTGRESQL_SHARED_PRELOAD_LIBRARIES="pgaudit,pg_cron,pg_bm25,vectors"