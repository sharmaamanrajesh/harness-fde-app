const test = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../src/app');

test('GET / returns Hello World', async () => {
  const res = await request(app).get('/');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.message, 'Hello World');
});

test('GET /health returns ok with version and environment', async () => {
  const res = await request(app).get('/health');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.status, 'ok');
  assert.ok(res.body.version);
  assert.ok(res.body.environment);
});

test('GET /health reports when the process started', async () => {
  const res = await request(app).get('/health');
  assert.strictEqual(res.status, 200);
  assert.ok(!Number.isNaN(Date.parse(res.body.startedAt)));
});

test('responses carry version and environment headers', async () => {
  const res = await request(app).get('/health');
  assert.ok(res.headers['x-app-version']);
  assert.ok(res.headers['x-app-environment']);
});

test('unknown route returns 404 JSON', async () => {
  const res = await request(app).get('/nope');
  assert.strictEqual(res.status, 404);
  assert.strictEqual(res.body.error, 'not found');
});
