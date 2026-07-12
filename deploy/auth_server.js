// ============================================================
// MathMate 认证服务 v3
// 功能: 注册(邮箱/手机验证码) | 登录 | 用户管理
// 端口: 3002
// 说明: 已移除邀请码体系（inviteCode / 邀请码直登 / invites 管理）
// ============================================================

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// 读取 .env.server(本地脚本旁 / 生产 /opt/mathmate)
try {
  require('dotenv').config({
    path: process.env.MATHMATE_ENV ||
      (process.platform === 'win32' ? path.join(__dirname, '.env.server') : '/opt/mathmate/.env.server'),
  });
} catch (_) { /* dotenv 未安装时忽略 */ }

const IS_PRODUCTION = process.env.NODE_ENV === 'production';

// 阿里云短信 SDK(可选;未安装或未配置时验证码回退到 console 打印)
// 个人用 PNVS 号码认证服务(@alicloud/dypnsapi20170525,免资质);企业可用普通短信(@alicloud/dysmsapi20170525)
let Dysmsapi = null, Dypnsapi = null, OpenApi = null;
try {
  Dysmsapi = require('@alicloud/dysmsapi20170525');
  Dypnsapi = require('@alicloud/dypnsapi20170525');
  OpenApi = require('@alicloud/openapi-client');
} catch (_) { /* SDK 未安装,短信功能禁用 */ }

// 数据目录:优先环境变量；Windows 本地用脚本旁的 data/，生产 Linux 用 /opt/mathmate
const DATA_DIR = process.env.MATHMATE_DATA_DIR ||
  (process.platform === 'win32' ? path.join(__dirname, 'data') : '/opt/mathmate');

// ==================== 阿里云短信发送 ====================
let _smsClient = null;
function getSmsClient() {
  if (_smsClient) return _smsClient;
  if (!Dypnsapi || !OpenApi) return null;
  const ak = process.env.SMS_ACCESS_KEY;
  const sk = process.env.SMS_ACCESS_SECRET;
  if (!ak || !sk) return null;
  const config = new OpenApi.Config({
    accessKeyId: ak,
    accessKeySecret: sk,
    endpoint: 'dypnsapi.aliyuncs.com',
  });
  _smsClient = new Dypnsapi.default(config);
  return _smsClient;
}

// 发送短信验证码(PNVS 号码认证服务,个人免资质)。返回 { ok: true } | { fallback: true } | { ok: false, error }
async function sendSmsCode(phone, code) {
  const client = getSmsClient();
  if (!client) return { fallback: true };
  const sign = process.env.SMS_SIGN_NAME;
  const tmpl = process.env.SMS_TEMPLATE_CODE;
  if (!sign || !tmpl) return { fallback: true };
  // PNVS 手机号:纯数字,去掉前缀 86
  const phoneNum = phone.replace(/[^\d]/g, '').replace(/^86/, '');
  try {
    const resp = await client.sendSmsVerifyCode(new Dypnsapi.SendSmsVerifyCodeRequest({
      phoneNumber: phoneNum,
      signName: sign,
      templateCode: tmpl,
      code: code,
      // 预置模板变量:${Code} 验证码、${min} 有效期分钟数(PNVS key 用小写)
      templateParam: JSON.stringify({ code: code, min: '5' }),
    }));
    const b = resp && resp.body;
    if (b && b.code === 'OK') return { ok: true };
    return { ok: false, error: (b && b.message) || '短信发送失败' };
  } catch (e) {
    // 捕获 API 异常,防止崩进程;返回错误给前端
    return { ok: false, error: (e && (e.code || e.message)) || '短信发送失败' };
  }
}
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
const USERS_FILE = path.join(DATA_DIR, 'users.json');
const SECRET_FILE = path.join(DATA_DIR, 'auth_secret.txt');
const TOKEN_TTL_SECONDS = Math.max(300, parseInt(process.env.AUTH_TOKEN_TTL_SECONDS || '604800', 10) || 604800);
const MAX_BODY_BYTES = Math.max(1024, parseInt(process.env.AUTH_MAX_BODY_BYTES || '1048576', 10) || 1048576);

// ==================== 邮件发送(nodemailer) ====================
let nodemailer = null;
try { nodemailer = require('nodemailer'); } catch (_) { /* 未安装时回退 console */ }

let _mailTransporter = null;
function getMailTransporter() {
  if (_mailTransporter) return _mailTransporter;
  if (!nodemailer) return null;
  const host = process.env.SMTP_HOST;
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  if (!host || !user || !pass) return null;
  const port = parseInt(process.env.SMTP_PORT || '465', 10);
  _mailTransporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
    disableFileAccess: true,
    disableUrlAccess: true,
  });
  return _mailTransporter;
}

// 发送邮件验证码。返回 { ok: true } | { fallback: true } | { ok: false, error }
async function sendMailCode(email, code) {
  const transporter = getMailTransporter();
  if (!transporter) return { fallback: true };
  try {
    const from = process.env.SMTP_FROM || process.env.SMTP_USER;
    await transporter.sendMail({
      from,
      to: email,
      subject: 'MathMate 注册验证码',
      text: `您的验证码为 ${code},5 分钟内有效,请勿泄露。`,
      html: `<p>您的 MathMate 注册验证码为 <b style="font-size:22px;letter-spacing:2px">${code}</b>,5 分钟内有效,请勿向他人泄露。</p>`,
    });
    return { ok: true };
  } catch (e) {
    return { ok: false, error: (e && e.message) || '邮件发送失败' };
  }
}

// ==================== 工具函数 ====================

function getSecret() {
  if (fs.existsSync(SECRET_FILE)) return fs.readFileSync(SECRET_FILE, 'utf-8').trim();
  const s = crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(SECRET_FILE, s);
  return s;
}

function loadUsers() {
  try { if (fs.existsSync(USERS_FILE)) return JSON.parse(fs.readFileSync(USERS_FILE, 'utf-8')); }
  catch (e) { console.error(e.message); }
  return [];
}
function saveUsers(u) { fs.writeFileSync(USERS_FILE, JSON.stringify(u, null, 2)); }

function hashPassword(pw, salt) {
  salt = salt || crypto.randomBytes(16).toString('hex');
  return { hash: crypto.scryptSync(pw, salt, 64).toString('hex'), salt };
}
function verifyPassword(pw, salt, hash) {
  return crypto.timingSafeEqual(
    Buffer.from(hashPassword(pw, salt).hash),
    Buffer.from(hash)
  );
}

function createToken(payload) {
  const now = Math.floor(Date.now() / 1000);
  const h = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const b = Buffer.from(JSON.stringify({ ...payload, iat: now, exp: now + TOKEN_TTL_SECONDS })).toString('base64url');
  const s = crypto.createHmac('sha256', getSecret()).update(h + '.' + b).digest('base64url');
  return h + '.' + b + '.' + s;
}
function verifyToken(token) {
  try {
    const p = token.split('.');
    if (p.length !== 3) return null;
    const s = crypto.createHmac('sha256', getSecret()).update(p[0] + '.' + p[1]).digest('base64url');
    const expected = Buffer.from(s);
    const actual = Buffer.from(p[2]);
    if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) return null;
    const payload = JSON.parse(Buffer.from(p[1], 'base64url').toString());
    if (!Number.isInteger(payload.exp) || payload.exp <= Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch (e) { return null; }
}
function getUserId(req) {
  const t = (req.headers['authorization'] || '').replace(/^Bearer\s+/i, '');
  const p = verifyToken(t);
  return p ? p.uid : null;
}
function getUserRole(req) {
  const t = (req.headers['authorization'] || '').replace(/^Bearer\s+/i, '');
  const p = verifyToken(t);
  return p ? p.role : null;
}

function parseBody(req, res, cb) {
  const c = [];
  let size = 0;
  let rejected = false;
  req.on('data', d => {
    if (rejected) return;
    size += d.length;
    if (size > MAX_BODY_BYTES) {
      rejected = true;
      send(res, 413, { error: '请求内容过大' });
      return;
    }
    c.push(d);
  });
  req.on('end', () => {
    if (rejected) return;
    try { cb(JSON.parse(Buffer.concat(c).toString())); }
    catch (e) { res.writeHead(400, cors()); res.end(JSON.stringify({ error: 'Invalid JSON' })); }
  });
}

function cors() {
  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };
}
function send(res, code, data) {
  res.writeHead(code, cors());
  res.end(JSON.stringify(data));
}

// ==================== 验证码 ====================

const VERIFY_CODES = {};

function genCode() { return String(Math.floor(100000 + Math.random() * 900000)); }

function consumeVerificationAttempt(target, code) {
  const vc = VERIFY_CODES[target];
  if (!vc) return { ok: false, status: 400, error: '请先获取验证码' };
  if (vc.expires < Date.now()) {
    delete VERIFY_CODES[target];
    return { ok: false, status: 400, error: '验证码已过期，请重新获取' };
  }
  vc.attempts = (vc.attempts || 0) + 1;
  if (vc.attempts > 5) {
    delete VERIFY_CODES[target];
    return { ok: false, status: 429, error: '尝试次数过多，请重新获取' };
  }
  if (vc.code !== String(code || '').trim()) {
    return { ok: false, status: 400, error: `验证码错误，还剩 ${5 - vc.attempts} 次机会` };
  }
  return { ok: true };
}

async function handleSendCode(req, res, body) {
  const { email, phone } = body;
  const target = (email || phone || '').trim();
  if (!target) return send(res, 400, { error: '请输入邮箱或手机号' });

  const users = loadUsers();
  if (users.find(u => u.email === target || u.phone === target)) {
    return send(res, 409, { error: '该邮箱/手机号已注册' });
  }

  const exist = VERIFY_CODES[target];
  if (exist && (Date.now() - exist.sentAt) < 60000) {
    return send(res, 429, { error: '发送过于频繁，请 60 秒后再试' });
  }

  const code = genCode();
  VERIFY_CODES[target] = { code, expires: Date.now() + 300000, attempts: 0, sentAt: Date.now() };

  const isEmail = target.includes('@');

  // 邮箱:走 SMTP(nodemailer);未配置则回退 console(开发)
  if (isEmail) {
    const result = await sendMailCode(target, code);
    if (result.fallback) {
      if (IS_PRODUCTION) {
        delete VERIFY_CODES[target];
        return send(res, 503, { error: '邮件服务暂未配置，请联系管理员' });
      }
      console.log(`========== 验证码(dev) ==========`);
      console.log(`目标: ${target}`);
      console.log(`验证码: ${code}`);
      console.log(`============================`);
      return send(res, 200, { ok: true, message: '验证码已发送，有效期 5 分钟' });
    }
    if (result.ok) return send(res, 200, { ok: true, message: '验证码已发送至邮箱，有效期 5 分钟' });
    delete VERIFY_CODES[target];
    return send(res, 500, { error: result.error || '邮件发送失败，请稍后重试' });
  }

  // 手机:走阿里云短信;未配置 SDK/密钥时回退 console(开发模式)
  const result = await sendSmsCode(target, code);
  if (result.fallback) {
    if (IS_PRODUCTION) {
      delete VERIFY_CODES[target];
      return send(res, 503, { error: '短信服务暂未配置，请联系管理员' });
    }
    console.log(`========== 验证码(dev) ==========`);
    console.log(`目标: ${target}`);
    console.log(`验证码: ${code}`);
    console.log(`============================`);
    return send(res, 200, { ok: true, message: '验证码已发送，有效期 5 分钟' });
  }
  if (result.ok) {
    return send(res, 200, { ok: true, message: '验证码已发送至手机，有效期 5 分钟' });
  }
  // 发送失败:清除本次验证码,避免占用
  delete VERIFY_CODES[target];
  return send(res, 500, { error: result.error || '短信发送失败，请稍后重试' });
}

function handleVerifyCode(req, res, body) {
  const { email, phone, code } = body;
  const target = (email || phone || '').trim();
  if (!target || !code) return send(res, 400, { error: '参数不完整' });

  const result = consumeVerificationAttempt(target, code);
  if (!result.ok) return send(res, result.status, { error: result.error });

  return send(res, 200, { ok: true, message: '验证成功' });
}

// ==================== 注册/登录 ====================

function handleRegister(req, res, body) {
  const { username, password, email, phone, code } = body;
  const target = (email || phone || '').trim();

  if (!username || username.length < 2) return send(res, 400, { error: '用户名至少 2 个字符' });
  if (!password || password.length < 6) return send(res, 400, { error: '密码至少 6 位' });
  if (!target) return send(res, 400, { error: '请输入邮箱或手机号' });

  // 直接校验验证码（前端 register 时携带 code）
  const verification = consumeVerificationAttempt(target, code);
  if (!verification.ok) return send(res, verification.status, { error: verification.error });

  const users = loadUsers();
  if (users.find(u => u.username === username)) return send(res, 409, { error: '用户名已存在' });

  const { hash, salt } = hashPassword(password);
  const user = {
    id: 'u' + Date.now().toString(36) + crypto.randomBytes(3).toString('hex'),
    username, passwordHash: hash, passwordSalt: salt,
    email: email || '', phone: phone || '',
    role: 'user',
    createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
  };
  users.push(user);
  saveUsers(users);
  delete VERIFY_CODES[target];

  const token = createToken({ uid: user.id, role: user.role });
  console.log(`[auth] 注册成功: ${username}`);
  return send(res, 201, { token, user: { id: user.id, username, email: user.email, role: user.role } });
}

function handleLogin(req, res, body) {
  const { username, password } = body;
  if (!username || !password) return send(res, 400, { error: '请输入用户名和密码' });

  const users = loadUsers();
  const user = users.find(u => u.username === username);
  if (!user || !verifyPassword(password, user.passwordSalt, user.passwordHash)) {
    return send(res, 401, { error: '用户名或密码错误' });
  }
  const token = createToken({ uid: user.id, role: user.role });
  return send(res, 200, { token, user: { id: user.id, username, email: user.email || '', role: user.role } });
}

function handleProfile(req, res) {
  const uid = getUserId(req);
  if (!uid) return send(res, 401, { error: '未登录' });
  const users = loadUsers();
  const user = users.find(u => u.id === uid);
  if (!user) return send(res, 404, { error: '用户不存在' });

  if (req.method === 'GET') {
    return send(res, 200, { id: user.id, username: user.username, email: user.email || '', role: user.role, createdAt: user.createdAt });
  }
  if (req.method === 'PUT') {
    parseBody(req, res, (b) => {
      if (b.email !== undefined) user.email = b.email;
      if (b.password) { const r = hashPassword(b.password); user.passwordHash = r.hash; user.passwordSalt = r.salt; }
      user.updatedAt = new Date().toISOString();
      saveUsers(users);
      return send(res, 200, { ok: true });
    });
    return;
  }
}

function handleUsers(req, res) {
  const role = getUserRole(req);
  if (!role || (role !== 'admin' && role !== 'dev')) return send(res, 403, { error: '无权限' });
  const users = loadUsers();
  if (req.method === 'GET') return send(res, 200, users.map(u => ({ id: u.id, username: u.username, email: u.email || '', role: u.role, createdAt: u.createdAt })));
  if (req.method === 'PUT') {
    parseBody(req, res, (b) => {
      const t = users.find(u => u.id === b.id);
      if (!t) return send(res, 404, { error: '用户不存在' });
      if (b.role) t.role = b.role;
      t.updatedAt = new Date().toISOString();
      saveUsers(users);
      return send(res, 200, { ok: true });
    });
    return;
  }
}

// ==================== Server ====================

const server = http.createServer((req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(200, cors()); res.end(); return; }
  console.log(`[auth] ${req.method} ${req.url}`);

  if (req.url === '/api/auth/register' && req.method === 'POST')
    return parseBody(req, res, b => handleRegister(req, res, b));

  if (req.url === '/api/auth/login' && req.method === 'POST')
    return parseBody(req, res, b => handleLogin(req, res, b));

  if (req.url === '/api/auth/send-code' && req.method === 'POST')
    return parseBody(req, res, b => handleSendCode(req, res, b));

  if (req.url === '/api/auth/verify-code' && req.method === 'POST')
    return parseBody(req, res, b => handleVerifyCode(req, res, b));

  if (req.url === '/api/auth/profile' && (req.method === 'GET' || req.method === 'PUT'))
    return handleProfile(req, res);

  if (req.url === '/api/auth/users') return handleUsers(req, res);

  if (req.url === '/api/auth/health') {
    return send(res, 200, {
      ok: true,
      version: 'v3',
      smsConfigured: Boolean(
        getSmsClient() && process.env.SMS_SIGN_NAME && process.env.SMS_TEMPLATE_CODE,
      ),
      smtpConfigured: Boolean(getMailTransporter()),
    });
  }

  send(res, 404, { error: 'Not found' });
});

const AUTH_HOST = process.env.AUTH_HOST ||
  (process.platform === 'win32' ? '0.0.0.0' : '127.0.0.1');
if (require.main === module) {
  server.listen(3002, AUTH_HOST, () =>
    console.log(`MathMate Auth v3 running on ${AUTH_HOST}:3002`));
}

module.exports = { server, createToken, verifyToken, consumeVerificationAttempt, VERIFY_CODES };
