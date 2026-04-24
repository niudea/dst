FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    lib32gcc-s1 \
    libcurl4-gnutls-dev \
    logrotate \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root/steam/steamcmd

RUN wget -qO- "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar -xz

COPY defaults /opt/dst/defaults
COPY scripts/run_dedicated_servers.sh /usr/local/bin/dst-entrypoint

RUN chmod +x /usr/local/bin/dst-entrypoint

VOLUME ["/root/.klei/DoNotStarveTogether", "/root/steam/dst"]

CMD ["dst-entrypoint"]
