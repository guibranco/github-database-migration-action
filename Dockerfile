FROM alpine:3

# Labels for http://label-schema.org/rc1/#build-time-labels
# And for https://github.com/opencontainers/image-spec/blob/master/annotations.md
# And for https://help.github.com/en/actions/building-actions/metadata-syntax-for-github-actions
ARG NAME="GitHub action to manage SQL databases versioned migrations"
ARG DESCRIPTION=" A GitHub action to manage SQL databases versioned migrations"
ARG REPO_URL="https://github.com/guibranco/github-database-migration-action"
ARG AUTHOR="Guilherme Branco Stracini / GuiBranco / guilherme@guilhermebranco.com.br"
ARG HOMEPAGE="https://guibranco.github.io/"
ARG BUILD_DATE=2025-05-09T18:26:00Z
ARG VCS_REF=abcdef2
ARG VERSION=v2.0
LABEL \
  com.github.actions.name="${NAME}" \
  com.github.actions.author="${AUTHOR}" \
  com.github.actions.description="${DESCRIPTION}" \
  com.github.actions.color="purple" \
  com.github.actions.icon="upload-cloud" \
  org.label-schema.build-date="${BUILD_DATE}" \
  org.label-schema.name="${NAME}" \
  org.label-schema.description="${DESCRIPTION}" \
  org.label-schema.usage="README.md" \
  org.label-schema.url="${HOMEPAGE}" \
  org.label-schema.vcs-url="${REPO_URL}" \
  org.label-schema.vcs-ref="${VCS_REF}" \
  org.label-schema.vendor="${AUTHOR}" \
  org.label-schema.version="${VERSION}" \
  org.label-schema.schema-version="1.0"	\
  org.opencontainers.image.created="${BUILD_DATE}" \
  org.opencontainers.image.authors="${AUTHOR}" \
  org.opencontainers.image.url="${HOMEPAGE}" \
  org.opencontainers.image.documentation="${REPO_URL}/blob/main/README.md" \
  org.opencontainers.image.source="${REPO_URL}" \
  org.opencontainers.image.version="${VERSION}" \
  org.opencontainers.image.revision="${VCS_REF}" \
  org.opencontainers.image.vendor="${AUTHOR}" \
  org.opencontainers.image.licenses="MIT" \
  org.opencontainers.image.title="${NAME}" \
  org.opencontainers.image.description="${DESCRIPTION}" \
  maintainer="${AUTHOR}" \
  repository="${REPO_URL}"

RUN apk add --no-cache \
    mysql-client \
    postgresql-client \
    freetds

COPY entrypoint.sh /entrypoint.sh
COPY schema-version/ /schema-version/

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
