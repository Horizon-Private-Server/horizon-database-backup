FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Base deps
RUN apt-get update && apt-get install -y \
    curl ca-certificates gnupg \
    python3 python3-pip \
    unixodbc-dev \
  && rm -rf /var/lib/apt/lists/*

# Microsoft repo + mssql-tools18 (sqlcmd/bcp)
RUN curl https://packages.microsoft.com/keys/microsoft.asc \
      | tee /etc/apt/trusted.gpg.d/microsoft.asc >/dev/null \
 && curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list \
      | tee /etc/apt/sources.list.d/mssql-release.list >/dev/null \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y mssql-tools18 \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="$PATH:/opt/mssql-tools18/bin"

# Script
RUN mkdir -p /backup
COPY backup.sh /backup/backup_script.sh
RUN chmod +x /backup/backup_script.sh

ENTRYPOINT ["/backup/backup_script.sh"]

