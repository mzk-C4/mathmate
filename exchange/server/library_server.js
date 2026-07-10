const http = require('http');
const fs = require('fs');

// ============================================================
// MathMate 题库 API 服务（独立微服务）
// 用途：题库 CRUD + 批量导入 + 板块/统计，供 App 多端 + 多人协作
// 启动: node library_server.js
// 端口: 3004（Nginx 反反代 /api/library/* → localhost:3004）
// 存储: JSON 文件（零依赖，初期千级题量够用；后期可迁 SQLite/MySQL）
// ============================================================

const DATA_FILE = __dirname + '/library_questions.json';
const PORT = process.env.LIBRARY_PORT || 3004;
const BASE = '/api/library';

// ---------- JSON 文件存储 ----------
function loadQuestions() {
  try {
    return JSON.parse(fs.readFileSync(DATA_FILE, 'utf-8'));
  } catch (_) {
    return [];
  }
}
function saveQuestions(qs) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(qs, null, 2));
}

// ---------- 工具 ----------
function sendJson(res, status, data) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  });
  res.end(JSON.stringify(data));
}
function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf-8')));
      } catch (_) {
        resolve(null);
      }
    });
  });
}
function newId() {
  return 'q_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
}

// ---------- HTTP Server ----------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const pathname = url.pathname;
  const method = req.method;

  if (method === 'OPTIONS') return sendJson(res, 200, {});

  // GET /api/library/health
  if (method === 'GET' && pathname === BASE + '/health') {
    return sendJson(res, 200, { ok: true, total: loadQuestions().length });
  }

  // GET /api/library/questions?section=&type=&dmin=&dmax=&q=&page=&limit=
  if (method === 'GET' && pathname === BASE + '/questions') {
    const sp = Object.fromEntries(url.searchParams);
    const { section, type, dmin, dmax, q, page = '1', limit = '50' } = sp;
    let filtered = loadQuestions();
    if (section) filtered = filtered.filter((x) => x.section === section);
    if (type) filtered = filtered.filter((x) => x.type === type);
    if (dmin) filtered = filtered.filter((x) => (x.difficulty || 0) >= +dmin);
    if (dmax) filtered = filtered.filter((x) => (x.difficulty || 0) <= +dmax);
    if (q) {
      const kw = q.toLowerCase();
      filtered = filtered.filter(
        (x) =>
          (x.content || '').toLowerCase().includes(kw) ||
          (x.knowledgePoints || []).some((k) => k.toLowerCase().includes(kw))
      );
    }
    const p = Math.max(1, +page || 1);
    const n = Math.max(1, +limit || 50);
    return sendJson(res, 200, {
      total: filtered.length,
      page: p,
      limit: n,
      items: filtered.slice((p - 1) * n, p * n),
    });
  }

  // POST /api/library/questions/batch  (批量导入，灌 questions_*.json)
  if (method === 'POST' && pathname === BASE + '/questions/batch') {
    const body = await readBody(req);
    if (!Array.isArray(body)) {
      return sendJson(res, 400, { error: 'expect a JSON array' });
    }
    const qs = loadQuestions();
    const byId = new Map(qs.map((x) => [x.id, x]));
    let added = 0, updated = 0;
    for (const item of body) {
      if (!item.id) item.id = newId();
      if (byId.has(item.id)) {
        updated++;
        byId.set(item.id, { ...byId.get(item.id), ...item });
      } else {
        added++;
        byId.set(item.id, item);
      }
    }
    saveQuestions([...byId.values()]);
    console.log(`[library] batch: +${added} ~${updated} total=${byId.size}`);
    return sendJson(res, 200, { added, updated, total: byId.size });
  }

  // /api/library/questions/:id  (GET / PUT / DELETE)
  const idMatch = pathname.match(new RegExp('^' + BASE + '/questions/([^/]+)$'));
  if (idMatch) {
    const id = decodeURIComponent(idMatch[1]);
    const qs = loadQuestions();
    if (method === 'GET') {
      const item = qs.find((x) => x.id === id);
      return item ? sendJson(res, 200, item) : sendJson(res, 404, { error: 'not found' });
    }
    if (method === 'PUT') {
      const body = await readBody(req);
      const idx = qs.findIndex((x) => x.id === id);
      if (idx < 0) return sendJson(res, 404, { error: 'not found' });
      qs[idx] = { ...qs[idx], ...body, id };
      saveQuestions(qs);
      return sendJson(res, 200, qs[idx]);
    }
    if (method === 'DELETE') {
      const before = qs.length;
      const filtered = qs.filter((x) => x.id !== id);
      saveQuestions(filtered);
      return sendJson(res, 200, { deleted: before - filtered.length });
    }
  }

  // POST /api/library/questions  (新增单题)
  if (method === 'POST' && pathname === BASE + '/questions') {
    const body = await readBody(req);
    if (!body) return sendJson(res, 400, { error: 'invalid body' });
    if (!body.id) body.id = newId();
    const qs = loadQuestions();
    qs.push(body);
    saveQuestions(qs);
    console.log(`[library] +1 ${body.id}`);
    return sendJson(res, 201, body);
  }

  // GET /api/library/sections  (板块树 + 题量)
  if (method === 'GET' && pathname === BASE + '/sections') {
    const qs = loadQuestions();
    const map = {};
    for (const x of qs) map[x.section || '其他'] = (map[x.section || '其他'] || 0) + 1;
    return sendJson(
      res,
      200,
      Object.entries(map)
        .map(([section, count]) => ({ section, count }))
        .sort((a, b) => b.count - a.count)
    );
  }

  // GET /api/library/stats  (统计)
  if (method === 'GET' && pathname === BASE + '/stats') {
    const qs = loadQuestions();
    const bySection = {}, byType = {};
    const byDiff = { '基础(<0.4)': 0, '中等(0.4-0.6)': 0, '较难(0.6-0.8)': 0, '挑战(>=0.8)': 0 };
    for (const x of qs) {
      bySection[x.section || '其他'] = (bySection[x.section || '其他'] || 0) + 1;
      byType[x.type || '其他'] = (byType[x.type || '其他'] || 0) + 1;
      const d = x.difficulty == null ? 0.5 : x.difficulty;
      if (d < 0.4) byDiff['基础(<0.4)']++;
      else if (d < 0.6) byDiff['中等(0.4-0.6)']++;
      else if (d < 0.8) byDiff['较难(0.6-0.8)']++;
      else byDiff['挑战(>=0.8)']++;
    }
    return sendJson(res, 200, { total: qs.length, bySection, byType, byDiff });
  }

  sendJson(res, 404, { error: 'not found', path: pathname });
});

server.listen(PORT, () => {
  console.log(`[library] 题库 API 服务启动 :${PORT}  (数据: ${DATA_FILE})`);
});
