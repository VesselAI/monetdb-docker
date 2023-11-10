# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not
# distributed with this file, You can obtain one at
# https://mozilla.org/MPL/2.0/.
#
# Copyright 1997 - July 2008 CWI, August 2008 - 2023 MonetDB B.V.
# Extensive modifications copyright 2023 by VTT.

# Build arg base is the base image, which must be Debianish.
# rev is the Git branch or tag to build.

ARG base=debian
FROM $base as build
RUN apt-get update; apt-get -y install git build-essential perl

WORKDIR /src
ARG rev=master
# Kluge around https://github.com/MonetDB/MonetDB/issues/7411.
RUN git clone --depth 1 -b "$rev" https://github.com/MonetDB/MonetDB.git \
    && cd MonetDB \
    && perl -p -i -e 's/openssl-dev/libssl-dev/g' debian/control \
    && apt-get -y build-dep . \
    && dpkg-buildpackage -b -jauto 

FROM $base

# Create users and groups
RUN groupadd -g 5000 monetdb && \
    useradd -u 5000 -g 5000 monetdb

# Update & upgrade
RUN apt-get update; apt-get -y upgrade && apt-get -y install tini

COPY --from=build /src/libmonetdb-client??_*.deb /src/libmonetdb??_*.deb \
    /src/libmonetdb-stream??_*.deb /src/monetdb-client_*.deb \
    /src/monetdb5-server_*.deb /src/monetdb5-sql_*.deb /deb/
RUN dpkg -i /deb/*.deb || apt-get -y install -f

#######################################################
# Setup MonetDB
#######################################################
COPY --chmod=755 scripts/entrypoint.sh /usr/local/bin/

# Group writability is required on OpenShift, which runs the container
# as a random user but group 0.  Elsewhere we can choose: let's run
# as monetdb:0.  The Debian packages would use monetdb:monetdb, but that
# does not work for us.
ENV MDB_FARM_DIR=/var/monetdb5/dbfarm
WORKDIR /work
RUN mkdir -p "$MDB_FARM_DIR" \
    && chmod ug+rwx . "$MDB_FARM_DIR" \
    && chown 5000:0 . "$MDB_FARM_DIR"
USER 5000:0

EXPOSE 50000

ENTRYPOINT ["tini", "--"]
CMD [ "entrypoint.sh" ]

STOPSIGNAL SIGINT
