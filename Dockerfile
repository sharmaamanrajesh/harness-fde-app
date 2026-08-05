# syntax=docker/dockerfile:1.7

# Pinned to the *build* platform so `npm ci` runs natively even when building
# for another architecture. Safe here because every dependency is pure
# JavaScript; a native/compiled module would require a per-target-arch build.
FROM --platform=$BUILDPLATFORM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# Runtime is plain Alpine with only the Node binary copied in — npm, yarn and
# corepack are never present. That is a deliberate security decision, not an
# optimisation: `node:22-alpine` bundles npm, whose vendored `tar` carried
# CVE-2026-59873 (CRITICAL) and failed the pipeline's security gate, despite npm
# never being executed at runtime. Removing the package manager removes the
# entire class of finding rather than suppressing it.
#
# Alpine over distroless on purpose: distroless has no shell or coreutils, which
# would silently break the Deployment's `preStop` sleep hook, and its Debian
# base currently carries CVE-2026-31789 (CRITICAL) in libssl3.
#
# This stage contains no RUN, so cross-building needs no QEMU emulation at all.
# !! DEMO BRANCH ONLY - DO NOT MERGE !!
# Deliberately downgraded from alpine:3.24 to a base carrying
# CVE-2022-37434 (CRITICAL, zlib) to prove the pipeline's security
# gate blocks a pull request before it can be merged.
FROM alpine:3.12 AS runtime
ARG COMMIT_SHA=local-dev
ENV NODE_ENV=production \
    PORT=8080 \
    COMMIT_SHA=$COMMIT_SHA

LABEL org.opencontainers.image.title="harness-demo-app" \
      org.opencontainers.image.revision="$COMMIT_SHA" \
      org.opencontainers.image.source="https://github.com/sharmaamanrajesh/harness-fde-app"

# Node runtime plus the two shared libraries it links against on musl.
COPY --from=node:22-alpine /usr/local/bin/node /usr/local/bin/node
COPY --from=node:22-alpine /usr/lib/libstdc++.so.6 /usr/lib/libgcc_s.so.1 /usr/lib/

WORKDIR /app
COPY --from=deps --chown=1001:1001 /app/node_modules ./node_modules
COPY --chown=1001:1001 src ./src
COPY --chown=1001:1001 package.json ./

# UID:GID both pinned — specifying only a UID leaves the primary group as 0,
# and Kubernetes `runAsNonRoot` can only verify a numeric user.
USER 1001:1001
EXPOSE 8080
CMD ["node", "src/server.js"]
