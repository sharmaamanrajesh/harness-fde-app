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

RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=deps --chown=app:app /app/node_modules ./node_modules
COPY --chown=app:app src ./src
COPY --chown=app:app package.json ./

USER app
EXPOSE 8080
CMD ["node", "src/server.js"]
