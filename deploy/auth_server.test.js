const assert = require('node:assert/strict');
const test = require('node:test');

const {
  createToken,
  verifyToken,
  consumeVerificationAttempt,
  VERIFY_CODES,
} = require('./auth_server');

test('issued tokens include an expiry and verify successfully', () => {
  const payload = verifyToken(createToken({ uid: 'test-user', role: 'user' }));
  assert.equal(payload.uid, 'test-user');
  assert.ok(payload.exp > payload.iat);
});

test('tampered tokens are rejected', () => {
  const token = createToken({ uid: 'test-user', role: 'user' });
  assert.equal(verifyToken(`${token.slice(0, -1)}x`), null);
});

test('registration verification is locked after five wrong attempts', () => {
  const target = 'security-test@example.com';
  VERIFY_CODES[target] = {
    code: '123456',
    expires: Date.now() + 60000,
    attempts: 0,
    sentAt: Date.now(),
  };
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    const result = consumeVerificationAttempt(target, '000000');
    assert.equal(result.status, 400);
  }
  const blocked = consumeVerificationAttempt(target, '000000');
  assert.equal(blocked.status, 429);
  assert.equal(VERIFY_CODES[target], undefined);
});
