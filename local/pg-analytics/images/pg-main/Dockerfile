# pg-main: PostgreSQL 18 + pg_lake (+ pgduck_server) + pg_clickhouse, one image.
#
# Upstream's docker/Dockerfile builds four PostgreSQL majors with
# --enable-cassert, which is right for pg_lake's own CI and wrong for a
# benchmark: assertion builds are several times slower. This image builds
# one release-mode PostgreSQL 18 and only the pieces the lab uses.
ARG ALMA_TAG=9

############################ build ############################
FROM almalinux:${ALMA_TAG} AS build

RUN dnf -y install epel-release && dnf config-manager --enable crb && \
    dnf -y install --allowerasing \
      ca-certificates cmake ninja-build wget git bzip2 tar gzip xz \
      readline-devel zlib-devel flex bison libxml2-devel libxslt-devel \
      libicu-devel openssl-devel uuid-devel libuuid-devel lz4-devel xz-devel \
      snappy-devel jansson-devel libcurl-devel libzstd-devel pam-devel \
      perl perl-IPC-Run perl-IPC-Cmd perl-FindBin perl-File-Compare perl-Time-Piece \
      libtool patch which diffutils gcc gcc-c++ make unzip zip pkgconf-pkg-config \
    && dnf clean all

ARG PG_VERSION=18.6
ENV PGHOME=/usr/local/pgsql
ENV PATH=${PGHOME}/bin:${PATH}
RUN wget -q https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.gz && \
    tar xzf postgresql-${PG_VERSION}.tar.gz && cd postgresql-${PG_VERSION} && \
    ./configure --prefix=${PGHOME} --with-openssl --with-libxml --with-libxslt \
                --with-icu --with-uuid=ossp --with-lz4 && \
    make -j"$(nproc)" world-bin && make install-world-bin && \
    cd / && rm -rf postgresql-${PG_VERSION}*

# vcpkg supplies aws-sdk-cpp / azure SDKs for DuckDB's httpfs/aws/azure extensions
ARG VCPKG_VERSION=2025.10.17
RUN git clone -q https://github.com/Microsoft/vcpkg.git -b ${VCPKG_VERSION} /opt/vcpkg && \
    /opt/vcpkg/bootstrap-vcpkg.sh -disableMetrics
ENV VCPKG_TOOLCHAIN_PATH=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake \
    VCPKG_FORCE_SYSTEM_BINARIES=1

ARG PG_LAKE_REF=v3.5.3
RUN git clone -q --branch ${PG_LAKE_REF} https://github.com/snowflake-labs/pg_lake.git /src/pg_lake && \
    cd /src/pg_lake && \
    git rm -q --cached test_common/rest_catalog/polaris && \
    git config -f .gitmodules --remove-section submodule.test_common/rest_catalog/polaris && \
    git add .gitmodules && \
    git submodule update --init duckdb_pglake/duckdb duckdb_pglake/duckdb-postgres avro && \
    git -C duckdb_pglake/duckdb-postgres submodule update --init database-connector

# DuckDB is the long pole. NCORES bounds parallel C++ jobs so the compile
# fits in a default 8 GB Docker Desktop VM.
ARG NCORES=6
RUN cd /src/pg_lake && make install-pg_lake
RUN cd /src/pg_lake && \
    make install-pgduck_server PGCOMPAT_BUILD_CONFIG=Release NCORES=${NCORES} && \
    rm -rf duckdb_pglake/build /opt/vcpkg/buildtrees /opt/vcpkg/downloads /opt/vcpkg/packages

# Local fixes to pg_lake, applied after pgduck_server so the DuckDB layer
# stays cached. 0001 writes the manifest key-value metadata the Iceberg spec
# requires (schema, partition-spec, content, ...), without which ClickHouse
# rejects the tables pg_lake writes. Removing avro/lang/c/build makes
# pg_lake's Makefile re-patch and rebuild libavro, since the fix extends
# avro.patch too.
COPY patches /src/patches
RUN cd /src/pg_lake && \
    for p in /src/patches/*.patch; do git apply "$p"; done && \
    rm -rf avro/lang/c/build && \
    make install-pg_lake

ARG PG_CLICKHOUSE_REF=v0.10.0
RUN git clone -q --branch ${PG_CLICKHOUSE_REF} --recurse-submodules \
      https://github.com/ClickHouse/pg_clickhouse.git /src/pg_clickhouse && \
    cd /src/pg_clickhouse && make -j"$(nproc)" && make install

############################ runtime ############################
FROM almalinux:${ALMA_TAG}
RUN dnf -y install epel-release && dnf config-manager --enable crb && \
    dnf -y install --allowerasing \
      ca-certificates readline zlib libxml2 libxslt libicu openssl uuid libuuid \
      lz4 xz snappy jansson libcurl libzstd pam perl procps-ng sudo \
    && dnf clean all && \
    useradd -u 1001 -m -s /bin/bash postgres
ENV PGHOME=/usr/local/pgsql PGDATA=/var/lib/pgsql/data
ENV PATH=${PGHOME}/bin:${PATH}
COPY --from=build ${PGHOME} ${PGHOME}
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    mkdir -p /var/lib/pgsql /var/lib/pgduck && chown -R postgres:postgres /var/lib/pgsql /var/lib/pgduck
USER postgres
EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
