# syntax=docker/dockerfile:1.7
FROM node:22-alpine AS deps
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

# Pinned numeric UID/GID: Kubernetes `runAsNonRoot` cannot verify a username,
# only a numeric user, and a pinned UID survives base-image changes.
RUN addgroup -S -g 1001 app && adduser -S -u 1001 -G app app
WORKDIR /app
COPY --from=deps --chown=1001:1001 /app/node_modules ./node_modules
COPY --chown=1001:1001 src ./src
COPY --chown=1001:1001 package.json ./

USER 1001
EXPOSE 8080
CMD ["node", "src/server.js"]
