const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const https = require('https');

// Public clients use a rate-limited gateway token. Provider API keys remain
// exclusively in /opt/mathmate/.env.server.

function loadEnv() {
  const content = fs.readFileSync(__dirname + '/.env.server', 'utf-8');
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    env[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim();
  }
  return env;
}

const env = loadEnv();
const ROUTES = {
  '/api/deepseek': {
    apiKeyEnv: 'DEEPSEEK_API_KEY',
    modelEnv: 'DEEPSEEK_MODEL_ID',
    baseUrlEnv: 'DEEPSEEK_BASE_URL',
    defaultUrl: 'https://api.deepseek.com/chat/completions',
  },
  '/api/vivo': {
    apiKeyEnv: 'VIVO_API_KEY',
    modelEnv: 'VIVO_MODEL_ID',
    baseUrlEnv: 'VIVO_BASE_URL',
    defaultUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
  },
  '/api/qwen': {
    apiKeyEnv: 'VIVO_API_KEY',
    modelEnv: 'VIVO_MODEL_ID',
    baseUrlEnv: 'VIVO_BASE_URL',
    defaultUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
  },
  '/api/volc': {
    apiKeyEnv: 'VOLC_API_KEY',
    modelEnv: 'VOLC_MODEL_ID',
    baseUrlEnv: 'VOLC_BASE_URL',
    defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
  },
};

const MAX_BODY_BYTES = Number(env.DEMO_MAX_BODY_BYTES || 12 * 1024 * 1024);
const IP_REQUESTS_PER_MINUTE = Number(env.DEMO_IP_REQUESTS_PER_MINUTE || 30);
const GLOBAL_REQUESTS_PER_DAY = Number(env.DEMO_GLOBAL_REQUESTS_PER_DAY || 2000);
const ipWindows = new Map();
let globalWindow = { day: new Date().toISOString().slice(0, 10), count: 0 };

function json(res, status, payload) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(JSON.stringify(payload));
}

function tokenMatches(value) {
  const expected = env.DEMO_GATEWAY_TOKEN || '';
  if (!expected || !value) return false;
  const left = Buffer.from(value);
  const right = Buffer.from(expected);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function authorize(req, res) {
  const header = req.headers.authorization || '';
  const token = header.replace(/^Bearer\s+/i, '');
  if (!env.DEMO_GATEWAY_TOKEN) {
    json(res, 503, { error: 'AI gateway is not configured' });
    return false;
  }
  if (!tokenMatches(token)) {
    json(res, 401, { error: 'Invalid AI gateway token' });
    return false;
  }
  return true;
}

function withinRateLimit(req, res) {
  const now = Date.now();
  const day = new Date(now).toISOString().slice(0, 10);
  if (globalWindow.day !== day) globalWindow = { day, count: 0 };
  if (globalWindow.count >= GLOBAL_REQUESTS_PER_DAY) {
    json(res, 429, { error: 'Daily demo quota reached' });
    return false;
  }

  const ip = (req.headers['x-real-ip'] || req.socket.remoteAddress || 'unknown').toString();
  let window = ipWindows.get(ip);
  if (!window || now - window.startedAt >= 60_000) {
    window = { startedAt: now, count: 0 };
    ipWindows.set(ip, window);
  }
  if (window.count >= IP_REQUESTS_PER_MINUTE) {
    json(res, 429, { error: 'Too many demo requests' });
    return false;
  }

  window.count += 1;
  globalWindow.count += 1;
  return true;
}

function proxyRequest(clientReq, clientRes, bodyBuffer) {
  const route = ROUTES[clientReq.url];
  const apiKey = env[route.apiKeyEnv] || '';
  const modelId = env[route.modelEnv] || '';
  const baseUrl = env[route.baseUrlEnv] || route.defaultUrl;
  if (!apiKey || !modelId) {
    json(clientRes, 503, { error: `Server config missing: ${route.apiKeyEnv} or ${route.modelEnv}` });
    return;
  }

  const upstream = new URL(baseUrl);
  const transport = upstream.protocol === 'https:' ? https : http;
  const upstreamReq = transport.request({
    hostname: upstream.hostname,
    port: upstream.port || (upstream.protocol === 'https:' ? 443 : 80),
    path: upstream.pathname + upstream.search,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
      'Content-Length': Buffer.byteLength(bodyBuffer),
    },
  }, (upstreamRes) => {
    clientRes.writeHead(upstreamRes.statusCode || 502, {
      'Content-Type': upstreamRes.headers['content-type'] || 'application/json',
      'Cache-Control': 'no-cache',
      'X-Accel-Buffering': 'no',
      'Access-Control-Allow-Origin': '*',
    });
    upstreamRes.pipe(clientRes);
  });

  upstreamReq.on('error', (error) => {
    if (!clientRes.headersSent) json(clientRes, 502, { error: 'Upstream request failed' });
    else clientRes.end();
    console.error('[proxy] upstream error:', error.message);
  });
  upstreamReq.end(bodyBuffer);
}

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    });
    res.end();
    return;
  }

  if (req.method === 'GET' && req.url === '/health') {
    json(res, 200, { status: 'ok', gatewayAuth: Boolean(env.DEMO_GATEWAY_TOKEN) });
    return;
  }

  if (req.method !== 'POST' || !ROUTES[req.url]) {
    json(res, 404, { error: 'Not found' });
    return;
  }
  if (!authorize(req, res) || !withinRateLimit(req, res)) return;

  const chunks = [];
  let total = 0;
  let rejected = false;
  req.on('data', (chunk) => {
    if (rejected) return;
    total += chunk.length;
    if (total > MAX_BODY_BYTES) {
      rejected = true;
      json(res, 413, { error: 'Request body too large' });
      return;
    }
    chunks.push(chunk);
  });
  req.on('end', () => {
    if (!rejected) proxyRequest(req, res, Buffer.concat(chunks));
  });
});

server.listen(3001, '127.0.0.1', () => {
  console.log('MathMate authenticated AI proxy listening on 127.0.0.1:3001');
});
