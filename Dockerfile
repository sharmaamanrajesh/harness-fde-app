# syntax=docker/dockerfile:1.7

# Pinned to the *build* platform so `npm ci` runs natively even when building
# for another architecture. Safe here because every dependency is pure
# JavaScript; a native/compiled module would require a per-target-arch build.
FROM --platform=$BUILDPLATFORM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:22-alpine AS runtime
ARG COMMIT_SHA=local-dev
ENV NODE_ENV=production \
    PORT=8080 \
    COMMIT_SHA=$COMMIT_SHA

LABEL org.opencontainers.image.title="harness-demo-app" \
      org.opencontainers.image.revision="$COMMIT_SHA" \
      org.opencontainers.image.source="https://github.com/sharmaamanrajesh/harness-fde-app"

# No RUN in this stage: it is the only per-target-architecture stage, so keeping
# it to COPY/metadata means cross-building needs no QEMU emulation at all.
# A numeric UID needs no /etc/passwd entry, and Kubernetes `runAsNonRoot` can
# only verify a numeric user anyway.
WORKDIR /app
COPY --from=deps --chown=1001:1001 /app/node_modules ./node_modules
COPY --chown=1001:1001 src ./src
COPY --chown=1001:1001 package.json ./

# UID:GID both pinned — specifying only a UID leaves the primary group as 0.
USER 1001:1001
EXPOSE 8080
CMD ["node", "src/server.js"]
