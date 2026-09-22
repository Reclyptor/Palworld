# syntax=docker/dockerfile:1
#
# ghcr.io/reclyptor/palworld — Palworld dedicated server on the GameOps toolkit.
# Adapter contract: https://github.com/Reclyptor/GameOps/blob/master/docs/CONTRACT.md

ARG GAMEOPS_VERSION=1.1.1
FROM ghcr.io/reclyptor/gameops:${GAMEOPS_VERSION} AS gameops

FROM debian:trixie-slim

ARG PUID=1000
ARG PGID=1000
ARG STEAMCMD_URL=https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# SteamCMD is a 32-bit binary (lib32gcc-s1, lib32stdc++6). curl stays at
# runtime: the adapter drives the server's REST API with it (authenticated
# POSTs). gettext-base provides envsubst for the ini templates; the remaining
# libraries are what the dedicated server links against.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl gettext-base xdg-user-dirs \
        lib32gcc-s1 lib32stdc++6 libicu76 libsdl3-0 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid "${PGID}" steam \
 && useradd --uid "${PUID}" --gid "${PGID}" --create-home --home-dir /home/steam --shell /bin/bash steam \
 && install -d -o "${PUID}" -g "${PGID}" /data /backups /home/steam/steamcmd /home/steam/Steam /home/steam/Steam/package

COPY --from=gameops /opt/gameops /opt/gameops
COPY adapter/ /opt/game/

RUN chmod 0644 /opt/game/adapter.sh /opt/game/lib/*.sh /opt/game/templates/* \
 && bash -n /opt/game/adapter.sh /opt/game/lib/*.sh \
 && /opt/gameops/bin/gameops version

ENV PATH="/opt/gameops/bin:${PATH}" \
    HOME=/home/steam \
    STEAMCMD_DIR=/home/steam/steamcmd \
    DATA_DIR=/data \
    BACKUP_DIR=/backups \
    SERVER_NAME=Palworld \
    PORT=8211 \
    QUERY_PORT=27015 \
    REST_API_ENABLED=true \
    REST_API_PORT=8212 \
    RCON_ENABLED=false \
    RCON_PORT=25575 \
    PUBLIC=false \
    MULTITHREADING=false \
    READY_TIMEOUT=1800

USER ${PUID}:${PGID}

# Install SteamCMD as the steam user and let it self-update once now, so the
# first container start goes straight to downloading the game.
RUN curl -fsSL --retry 5 "${STEAMCMD_URL}" | tar -xz -C /home/steam/steamcmd \
 && /home/steam/steamcmd/steamcmd.sh +quit \
 && test -x /home/steam/steamcmd/linux32/steamcmd

WORKDIR /data
VOLUME ["/data", "/backups"]
EXPOSE 8211/udp 27015/udp 9110/tcp
# First start downloads the dedicated server (several GB) before the world can load.
HEALTHCHECK --interval=60s --timeout=10s --start-period=45m --retries=3 CMD ["gameops", "health"]
ENTRYPOINT ["gameops", "run"]

LABEL org.opencontainers.image.title="palworld" \
      org.opencontainers.image.description="Palworld dedicated server with backups, in-place auto-updates, Discord notifications and player events, on the GameOps toolkit" \
      org.opencontainers.image.source="https://github.com/Reclyptor/Palworld" \
      org.opencontainers.image.licenses="MIT"
