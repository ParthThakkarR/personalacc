'use strict';
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'college-demo-secret-change-me';
const ACCESS_EXPIRES = process.env.ACCESS_EXPIRES || '15m';
const REFRESH_DAYS = Number(process.env.REFRESH_DAYS || 30);

function signAccess(user) {
  return jwt.sign({ sub: user.id, phone: user.phone, typ: 'access' }, JWT_SECRET, {
    expiresIn: ACCESS_EXPIRES,
  });
}

/** Opaque refresh token (cf. KbAuthenticationSession): returned once, stored hashed. */
function newRefreshToken() {
  const raw = crypto.randomBytes(32).toString('base64url');
  const hash = crypto.createHash('sha256').update(raw).digest('hex');
  return { raw, hash };
}

function refreshExpiry() {
  return Date.now() + REFRESH_DAYS * 24 * 60 * 60 * 1000;
}

function authRequired(req, res, next) {
  const h = req.headers.authorization || '';
  const m = h.match(/^Bearer (.+)$/);
  if (!m) return res.status(401).json({ error: 'missing_bearer_token' });
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    if (payload.typ !== 'access') return res.status(401).json({ error: 'invalid_token' });
    req.user = { id: Number(payload.sub), phone: payload.phone };
    return next();
  } catch (e) {
    const code = e && e.name === 'TokenExpiredError' ? 'token_expired' : 'invalid_token';
    return res.status(401).json({ error: code });
  }
}

module.exports = { signAccess, newRefreshToken, refreshExpiry, authRequired, JWT_SECRET };
