FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    lib32gcc-s1 \
    libcurl4-gnutls-dev \
    logrotate \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root/steam/steamcmd

RUN wget -qO- "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar -xz

COPY Cluster_1 /root/steam/defaults/Cluster_1
COPY mods /root/steam/defaults/mods
COPY run_dedicated_servers.sh /root/steam/run_dedicated_servers.sh

RUN chmod +x /root/steam/run_dedicated_servers.sh

VOLUME ["/root/.klei/DoNotStarveTogether", "/root/steam/dst"]

CMD ["/root/steam/run_dedicated_servers.sh"]
