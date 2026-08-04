const os = require('os');
const express = require('express');

const app = express();

const COMMIT_SHA = process.env.COMMIT_SHA || 'local-dev';
const ENVIRONMENT = process.env.ENVIRONMENT || 'local';
const STARTED_AT = Date.now();

// Surface the running build on every response so a rolling update can be
// observed from the client side, not just from `kubectl`.
app.use((req, res, next) => {
  res.set('X-App-Version', COMMIT_SHA);
  res.set('X-App-Environment', ENVIRONMENT);
  next();
});

app.get('/', (req, res) => {
  res.json({ message: 'Hello World', service: 'harness-demo-app' });
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    version: COMMIT_SHA,
    environment: ENVIRONMENT,
    hostname: os.hostname(),
    uptimeSeconds: Math.floor((Date.now() - STARTED_AT) / 1000),
  });
});

app.use((req, res) => res.status(404).json({ error: 'not found' }));

module.exports = app;
