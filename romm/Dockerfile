ARG ROMM_VERSION="5.0.0"
FROM ghcr.io/rommapp/romm:${ROMM_VERSION}

ARG BUILD_ARCH
ARG BUILD_VERSION="5.0.0-4"

RUN \
  apk add --no-cache \
    curl \
    jq \
    mariadb-client

COPY run.sh /run.sh
COPY valkey.conf /usr/local/etc/valkey/valkey.conf

RUN \
  chmod 0755 /run.sh \
  && chmod 0644 /usr/local/etc/valkey/valkey.conf

LABEL \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}" \
  io.hass.name="RomM" \
  io.hass.description="Self-hosted ROM manager and player for Home Assistant" \
  io.hass.url="https://github.com/rigerc/ha-apps-next" \
  io.hass.version="${BUILD_VERSION}" \
  org.opencontainers.image.title="Home Assistant App: RomM" \
  org.opencontainers.image.description="Home Assistant packaging for RomM" \
  org.opencontainers.image.source="https://github.com/rigerc/ha-apps-next" \
  org.opencontainers.image.version="${BUILD_VERSION}" \
  org.opencontainers.image.licenses="AGPL-3.0-only"

ENTRYPOINT ["/run.sh"]
