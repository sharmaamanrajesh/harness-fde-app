# harness-demo-app

Demo service for the Harness CI/CD + security gating assignment.

Exposes:

| Endpoint  | Response |
|-----------|----------|
| `GET /`       | `{"message":"Hello World","service":"harness-demo-app"}` |
| `GET /health` | `{"status":"ok","version":"<commit sha>","environment":"<env>","hostname":"<pod>","uptimeSeconds":n}` |

`version` and `environment` are injected at runtime, so `/health` reports which
build is live and which environment it is running in.

## Local development

```bash
npm install
npm test
npm start        # http://localhost:8080
```

## Container

```bash
docker buildx build --load --platform linux/arm64 \
  --build-arg COMMIT_SHA=$(git rev-parse --short HEAD) \
  -t harness-demo-app:local .

docker run --rm -p 8080:8080 -e ENVIRONMENT=local harness-demo-app:local
```

> Full architecture, pipeline explanation, and security-gating documentation
> live in the top-level assignment README (added in a later phase).
