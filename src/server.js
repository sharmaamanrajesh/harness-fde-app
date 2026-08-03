const app = require('./app');

const PORT = process.env.PORT || 8080;

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(JSON.stringify({
    level: 'info',
    msg: 'server started',
    port: PORT,
    version: process.env.COMMIT_SHA || 'local-dev',
    environment: process.env.ENVIRONMENT || 'local',
  }));
});

// Graceful shutdown. Kubernetes sends SIGTERM before removing a pod; without
// draining, in-flight requests are dropped and the maxUnavailable: 0 rolling
// strategy would not actually be zero-downtime.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(JSON.stringify({ level: 'info', msg: `${signal} received, draining` }));
    server.close(() => process.exit(0));
  });
}
