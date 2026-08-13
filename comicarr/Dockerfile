# syntax=docker/dockerfile:1

FROM ghcr.io/frankieramirez/comicarr:0.31.0@sha256:5c4c55373c1d8032b9168c6fd31d7e601f0a6fa3930adc53e08e194c7e33077b

ARG BUILD_ARCH
ARG BUILD_VERSION="0.31.0-2"
ARG BUILD_COMMIT="unknown"

USER root

ENV PYTHONDONTWRITEBYTECODE=1

COPY run.sh /run.sh

RUN chmod 0755 /run.sh

LABEL \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}" \
  io.hass.name="Comicarr" \
  io.hass.description="Automated comic book and manga management for Home Assistant" \
  io.hass.url="https://github.com/rigerc/ha-apps-next" \
  io.hass.version="${BUILD_VERSION}" \
  org.opencontainers.image.title="Home Assistant App: Comicarr" \
  org.opencontainers.image.description="Unofficial Home Assistant packaging for Comicarr" \
  org.opencontainers.image.source="https://github.com/rigerc/ha-apps-next" \
  org.opencontainers.image.revision="${BUILD_COMMIT}" \
  org.opencontainers.image.version="${BUILD_VERSION}" \
  org.opencontainers.image.licenses="GPL-3.0-or-later" \
  org.opencontainers.image.base.name="ghcr.io/frankieramirez/comicarr:0.31.0" \
  org.opencontainers.image.base.digest="sha256:5c4c55373c1d8032b9168c6fd31d7e601f0a6fa3930adc53e08e194c7e33077b"

ENTRYPOINT ["/run.sh"]
