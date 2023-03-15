# syntax=docker/dockerfile:1
FROM phusion/baseimage:jammy-1.0.1
# https://github.com/phusion/baseimage-docker

LABEL org.opencontainers.image.authors="Richard Kuhnt <r15ch13+git@gmail.com>" \
      org.opencontainers.image.title="ARK Cluster Image" \
      org.opencontainers.image.description="ARK Cluster Image" \
      org.opencontainers.image.url="https://github.com/r15ch13/arkcluster" \
      org.opencontainers.image.source="https://github.com/r15ch13/arkcluster"

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

RUN <<EOT bash
# Install dependencies and clean up
    apt-get update
    apt-get upgrade -y -o Dpkg::Options::="--force-confold"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bzip2 curl lib32gcc-s1 libc6-i386 lsof perl-modules tzdata
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create required directories
    mkdir -p /ark/{log,backup,staging,steam,default}
    mkdir -p /cluster
EOT

ARG ARKMANAGER_VERSION=1.6.62

# Expose environment variables
ENV CRON_AUTO_UPDATE="0 */3 * * *" \
    CRON_AUTO_BACKUP="0 */1 * * *" \
    UPDATEONSTART=1 \
    BACKUPONSTART=1 \
    BACKUPONSTOP=1 \
    WARNONSTOP=1 \
    USER_ID=1000 \
    GROUP_ID=1000 \
    TZ=UTC \
    MAX_BACKUP_SIZE=500 \
    SERVERMAP="TheIsland" \
    SESSION_NAME="ARK Docker" \
    MAX_PLAYERS=15 \
    RCON_ENABLE="True" \
    RCON_PORT=32330 \
    GAME_PORT=7778 \
    QUERY_PORT=27015 \
    SERVER_PVE="False" \
    SERVER_PASSWORD="" \
    ADMIN_PASSWORD="" \
    SPECTATOR_PASSWORD="" \
    MODS="" \
    CLUSTER_ID="keepmesecret" \
    GAME_USERSETTINGS_INI_PATH="" \
    GAME_INI_PATH="" \
    KILL_PROCESS_TIMEOUT=300 \
    KILL_ALL_PROCESSES_TIMEOUT=300

RUN <<EOT bash
# Add steam user
    addgroup --gid "$GROUP_ID" steam
    adduser --system --uid "$USER_ID" --gid "$GROUP_ID" --shell /bin/bash steam
    usermod -a -G docker_env steam

# Install ark-server-tools
    curl -sqL "https://github.com/arkmanager/ark-server-tools/archive/refs/tags/v${ARKMANAGER_VERSION}.tar.gz" | tar zxvf -
    mv "./ark-server-tools-${ARKMANAGER_VERSION}" /home/steam/ark-server-tools
    cd /home/steam/ark-server-tools/tools/
    ./install.sh steam --bindir=/usr/bin

# Install steamcmd
    mkdir -p /home/steam/steamcmd
    cd /home/steam/steamcmd
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -
EOT

# Setup arkcluster
RUN mkdir -p /etc/service/arkcluster
COPY run.sh /etc/service/arkcluster/run
RUN chmod +x /etc/service/arkcluster/run

COPY crontab /home/steam/crontab

COPY arkmanager.cfg /etc/arkmanager/arkmanager.cfg
COPY arkmanager-user.cfg /home/steam/arkmanager-user.cfg

HEALTHCHECK --interval=1m --timeout=10s --start-period=5m --retries=10 CMD [ "cat /proc/net/udp | grep `printf '%X' $GAME_PORT` || exit 1" ]

VOLUME /ark /cluster
WORKDIR /ark
