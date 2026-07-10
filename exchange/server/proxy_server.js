const http = require('http');
const https = require('https');
const fs = require('fs');

// ============================================================
// MathMate API 代理服务
// 用途：接收 Flutter Web 前端的 API 请求，转发到 DeepSeek/Vivo/Volc
// 好处：API Key 只存在服务器，前端 JS 中不会泄露
//
// 启动: node proxy_server.js
// 端口: 3001（Nginx 反向代理 /api/* → localhost:3001）
// ============================================================

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

const ROUTES = {
  '/api/deepseek': {
    apiKeyEnv: 'DEEPSEEK_API_KEY',
    modelEnv:   'DEEPSEEK_MODEL_ID',
    baseUrlEnv: 'DEEPSEEK_BASE_URL',
    defaultUrl: 'https://api.deepseek.com/chat/completions',
  },
  '/api/vivo': {
    apiKeyEnv: 'VIVO_API_KEY',
    modelEnv:   'VIVO_MODEL_ID',
    baseUrlEnv: 'VIVO_BASE_URL',
    defaultUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
  },
  '/api/volc': {
    apiKeyEnv: 'VOLC_API_KEY',
    modelEnv:   'VOLC_MODEL_ID',
    baseUrlEnv: 'VOLC_BASE_URL',
    defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
  },
};

const env = loadEnv();

// ---------- 代理转发 ----------
function proxyRequest(clientReq, clientRes, bodyBuffer) {
  const route = ROUTES[clientReq.url];
  if (!route) {
    clientRes.writeHead(404, { 'Content-Type': 'application/json' });
    clientRes.end(JSON.stringify({ error: 'not found' }));
    return;
  }

  const apiKey  = env[route.apiKeyEnv]  || '';
  const modelId = env[route.modelEnv]   || '';
  const baseUrl = env[route.baseUrlEnv] || route.defaultUrl;

  if (!apiKey || !modelId) {
    clientRes.writeHead(500, { 'Content-Type': 'application/json' });
    clientRes.end(JSON.stringify({ error: `Server config missing: ${route.apiKeyEnv} or ${route.modelEnv}` }));
    return;
  }

  const upstream = new URL(baseUrl);
  const isHttps = upstream.protocol === 'https:';
  const transport = isHttps ? https : http;

  const options = {
    hostname: upstream.hostname,
    port:     upstream.port || (isHttps ? 443 : 80),
    path:     upstream.pathname + upstream.search,
    method:   'POST',
    headers:  {
      'Content-Type':  'application/json',
      'Authorization': 'Bearer ' + apiKey,
      'Content-Length': Buffer.byteLength(bodyBuffer),
    },
  };

  console.log(`[proxy] → ${baseUrl}`);

  const upstreamReq = transport.request(options, (upstreamRes) => {
    const chunks = [];
    upstreamRes.on('data',  c => chunks.push(c));
    upstreamRes.on('end', () => {
      const body = Buffer.concat(chunks);
      clientRes.writeHead(upstreamRes.statusCode, {
        'Content-Type':   'application/json',
        'Access-Control-Allow-Origin': '*',
      });
      clientRes.end(body);
      console.log(`[proxy] ← ${upstreamRes.statusCode} (${body.length} bytes)`);
    });
  });

  upstreamReq.on('error', (err) => {
    console.error('[proxy] error:', err.message);
    clientRes.writeHead(502, { 'Content-Type': 'application/json' });
    clientRes.end(JSON.stringify({ error: 'upstream error: ' + err.message }));
  });

  upstreamReq.write(bodyBuffer);
  upstreamReq.end();
}

// ---------- HTTP Server ----------
const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data',  c => chunks.push(c));
  req.on('end',  () => {
    const body = Buffer.concat(chunks);
    console.log(`[proxy] ${req.method} ${req.url} (${body.length} bytes)`);

    if (req.method === 'OPTIONS') {
      res.writeHead(200, {
        'Access-Control-Allow-Origin':  '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      });
      res.end();
      return;
    }

    if (req.method === 'POST' && ROUTES[req.url]) {
      proxyRequest(req, res, body);
    } else {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('MathMate Proxy OK');
    }
  });
});

server.listen(3001, '127.0.0.1', () => {
  console.log('MathMate API Proxy running on http://127.0.0.1:3001');
  console.log('Routes:');
  for (const path of Object.keys(ROUTES)) {
    console.log(`  POST ${path}`);
  }
});
