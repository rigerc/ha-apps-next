# syntax=docker/dockerfile:1

FROM ghcr.io/jessielw/reclaimerr:0.3.5@sha256:f86767e0e580f08b93f811e966a6daf9e8442913d93df8036de0921627bcc013

ARG BUILD_ARCH
ARG BUILD_VERSION="0.3.5-1"
ARG BUILD_COMMIT="unknown"

USER root

COPY patches /usr/share/reclaimerr-ha/patches
COPY run.sh /run.sh

RUN \
  patch --directory=/app --strip=1 \
    < /usr/share/reclaimerr-ha/patches/0001-fix-version-endpoint.patch \
  && chmod 0755 /run.sh

LABEL \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}" \
  io.hass.name="Reclaimerr" \
  io.hass.description="Self-hosted media cleanup and deletion management for Home Assistant" \
  io.hass.url="https://github.com/rigerc/ha-apps-next" \
  io.hass.version="${BUILD_VERSION}" \
  org.opencontainers.image.title="Home Assistant App: Reclaimerr" \
  org.opencontainers.image.description="Home Assistant packaging for Reclaimerr" \
  org.opencontainers.image.source="https://github.com/rigerc/ha-apps-next" \
  org.opencontainers.image.revision="${BUILD_COMMIT}" \
  org.opencontainers.image.version="${BUILD_VERSION}" \
  org.opencontainers.image.licenses="GPL-3.0-only" \
  org.opencontainers.image.base.name="ghcr.io/jessielw/reclaimerr:0.3.5" \
  org.opencontainers.image.base.digest="sha256:f86767e0e580f08b93f811e966a6daf9e8442913d93df8036de0921627bcc013"

ENTRYPOINT ["/run.sh"]
