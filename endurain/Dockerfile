ARG ENDURAIN_VERSION="v0.19.0"
FROM codeberg.org/endurain-project/endurain:${ENDURAIN_VERSION}@sha256:a43273a30588f344f103e978a2e17aae75de31ffdb21dddd8ac8e71d70a08f3c

ARG BUILD_ARCH
ARG BUILD_VERSION="0.19.0-1"

USER root

RUN \
  apk add --no-cache \
    bash \
    jq \
    openssl \
    postgresql18 \
    postgresql18-client \
    su-exec \
    valkey \
    valkey-cli \
  && chmod -R a-w /app/backend /app/frontend \
  && chmod 0664 /app/frontend/dist/env.js /app/frontend/dist/index.html

COPY run.sh /run.sh
COPY valkey.conf /usr/local/etc/valkey/valkey.conf

RUN \
  chmod 0755 /run.sh \
  && chmod 0644 /usr/local/etc/valkey/valkey.conf

LABEL \
  io.hass.type="app" \
  io.hass.arch="${BUILD_ARCH}" \
  io.hass.name="Endurain" \
  io.hass.description="Self-hosted fitness and activity tracking for Home Assistant" \
  io.hass.url="https://github.com/rigerc/ha-apps-next" \
  io.hass.version="${BUILD_VERSION}" \
  org.opencontainers.image.title="Home Assistant App: Endurain" \
  org.opencontainers.image.description="Unofficial Home Assistant packaging for Endurain" \
  org.opencontainers.image.source="https://github.com/rigerc/ha-apps-next" \
  org.opencontainers.image.version="${BUILD_VERSION}" \
  org.opencontainers.image.licenses="AGPL-3.0-or-later"

ENTRYPOINT ["/run.sh"]
