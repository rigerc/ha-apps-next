ARG BUILD_VERSION="2.3.1-1"
ARG BUILD_ARCH
FROM rommapp/romm:v2.3.1

ARG BUILD_VERSION
ARG BUILD_ARCH

RUN apk add --no-cache \
    bash \
    curl \
    jq \
    mariadb-client

COPY run.sh /run.sh
RUN chmod 0755 /run.sh

LABEL \
  io.hass.type="app" \
  io.hass.arch="aarch64|amd64" \
  io.hass.name="RomM" \
  io.hass.description="Self-hosted ROM manager and player for Home Assistant" \
  io.hass.url="https://github.com/rigerc/ha-apps-next" \
  io.hass.version="${BUILD_VERSION}" \
  org.opencontainers.image.title="Home Assistant RomM" \
  org.opencontainers.image.description="Home Assistant-packaged RomM wrapper" \
  org.opencontainers.image.source="https://github.com/rigerc/ha-apps-next" \
  org.opencontainers.image.version="${BUILD_VERSION}" \
  org.opencontainers.image.licenses="AGPL-3.0-only"

ENTRYPOINT ["/run.sh"]
