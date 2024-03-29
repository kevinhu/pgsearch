ARG PG_VERSION_MAJOR=16

# FROM bitnami/postgresql:${PG_VERSION_MAJOR}-debian-12 as pgsearch
FROM postgres:${PG_VERSION_MAJOR}-bookworm as pgsearch

ARG PG_VERSION_MAJOR=16
ARG TARGETARCH
ARG PG_BM25_VERSION=0.5.7
ARG VECTORS_VERSION=0.2.1

ENV PG_VERSION_MAJOR=${PG_VERSION_MAJOR} \
    POSTHOG_API_KEY='' \
    POSTHOG_HOST='' \
    PARADEDB_TELEMETRY=false \
    TARGETARCH=${TARGETARCH}

# Install runtime dependencies (requires switching to root temporarily)
USER root
RUN apt-get update
RUN apt-get remove libicu-dev -y
RUN apt-get install curl uuid-runtime libpq5 -y
RUN apt-get install postgresql-server-dev-all postgresql-16-cron -y

ENV PG_BM25_VERSION=${PG_BM25_VERSION}
RUN curl -fsSL https://github.com/paradedb/paradedb/releases/download/v${PG_BM25_VERSION}/pg_bm25-v${PG_BM25_VERSION}-pg${PG_VERSION_MAJOR}-${TARGETARCH}-ubuntu2204.deb -o /tmp/pg_bm25.deb
RUN dpkg -i /tmp/pg_bm25.deb
RUN rm /tmp/pg_bm25.deb

ENV VECTORS_VERSION=${VECTORS_VERSION}
RUN curl -fsSL https://github.com/tensorchord/pgvecto.rs/releases/download/v${VECTORS_VERSION}/vectors-pg${PG_VERSION_MAJOR}_${VECTORS_VERSION}_${TARGETARCH}.deb -o /tmp/vectors.deb
RUN dpkg -i /tmp/vectors.deb
RUN rm /tmp/vectors.deb

RUN if [ "$TARGETARCH" = "arm64" ]; then curl -fsSL http://ports.ubuntu.com/pool/main/i/icu/libicu70_70.1-2_arm64.deb -o /tmp/libicu70.deb; else curl -fsSL http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2_amd64.deb -o /tmp/libicu70.deb; fi
RUN dpkg -i /tmp/libicu70.deb
RUN rm /tmp/libicu70.deb

# clean up
RUN apt-get clean autoclean
RUN apt-get autoremove --yes
RUN rm -rf /var/lib/{apt,dpkg,cache,log}/

# Copy ParadeDB bootstrap script to install extensions, configure postgresql.conf, etc.
# COPY ./docker/01_bootstrap.sh /docker-entrypoint-initdb.d/
COPY ./01_bootstrap.sh /docker-entrypoint-initdb.d/

# Configure shared_preload_libraries
# Note: pgaudit is needed here as it comes pre-packaged in the Bitnami image
ENV POSTGRESQL_SHARED_PRELOAD_LIBRARIES="pgaudit,pg_cron,pg_bm25,vectors"

# Change the uid of postgres to 26
RUN usermod -u 26 postgres \
    && chown -R 26:999 /var/lib/postgresql \
    && chown -R 26:999 /var/run/postgresql \
    && chmod -R 700 /var/lib/postgresql

USER 26