'use strict';
/**
 * Proper login system (clean-room, mirrors researched flow W2/W3):
 * PASSWORD MODE (active, AUTH_MODE=password, zero SMS cost):
 *  register (phone+password, first device) → login (phone+password, any
 *  device; same number sees same books = account-based sync) →
 *  {access, refresh, user, is_new} → profile onboarding → PIN/AppLock.
 * CLOSED VAULT: when ALLOWED_PHONES is set, register/login accept ONLY
 *  listed phones (admin-added users). Production refuses to start without it.
 *  OTP MODE (parked, see seam below): re-enable when an SMS provider is
 *  funded; utils/otp.js is untouched and tests keep a parked OTP block.
 * Refresh rotation with reuse detection; PIN with fail-counter + lockout.
 */
const express = require('express');
const bcrypt = require('bcryptjs');
const crypto = require('node:crypto');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { signAccess, newRefreshToken, refreshExpiry } = require('../utils/jwt');
const { isPhoneAllowed } = require('../utils/allowlist');
// OTP/SMS seam (PARKED — preserved intact for later, do not delete):
// re-enable by uncommenting the import + route block below when an SMS
// provider (Firebase Phone Auth / MSG91 / Truecaller) is funded.
// const { requestOtp, verifyOtp } = require('../utils/otp');
const { validate } = require('../middleware/common');

const router = express.Router();
const db = migrate(openDb());

const phoneSchema = z.object({ phone: z.string().regex(/^[0-9]{10}$/, '10-digit phone required') });
const passwordSchema = z.object({
  phone: z.string().regex(/^[0-9]{10}$/, '10-digit phone required'),
  password: z.string().min(8, 'password must be at least 8 characters').max(72, 'password too long'),
});
const PIN_RE = /^[0-9]{4,8}$/;
const MAX_PIN_FAILS = 5;
const PIN_LOCK_MS = 5 * 60 * 1000;

function publicUser(u) {
  return {
    id: u.id,
    phone: u.phone,
    name: u.name,
    business_name: u.business_name,
    business_category: u.business_category,
    has_pin: !!u.pin_hash,
    has_password: !!u.password_hash,
    profile_complete: !!(u.name && u.name !== 'Shop Owner' && u.business_name),
  };
}

function storeRefresh(userId) {
  const { raw, hash } = newRefreshToken();
  const r = db
    .prepare('INSERT INTO refresh_tokens (user_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?)')
    .run(userId, hash, refreshExpiry(), Date.now());
  return { raw, id: Number(r.lastInsertRowid) };
}

function issueSession(user) {
  const { raw, id } = storeRefresh(user.id);
  return { access: signAccess(user), refresh: raw, refresh_id: id };
}

function staffBooks(userId) {
  return db
    .prepare(
      `SELECT s.owner_id, s.role, u.name AS owner_name, u.business_name AS owner_business
       FROM staff_members s JOIN users u ON u.id=s.owner_id
       WHERE s.member_user_id=? AND s.status='active'`
    )
    .all(userId);
}

  // --- Password auth (active) ------------------------------------------------
// Same session shape as OTP verify so clients treat both identically:
// {access, refresh, user, is_new, staff_books}.
function claimStaffInvites(userId, phone) {
  // Same OTP login doubles as staff claim; password register/login does too.
  db.prepare("UPDATE staff_members SET member_user_id=?, status='active' WHERE phone=? AND status='invited'")
    .run(userId, phone);
}

function newReferralCode() {
  return (
    'KB' +
    Array.from(crypto.randomBytes(4))
      .map((b) => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'[b % 31])
      .join('')
  );
}

// First device: create the account. Later devices: use /login with the
// same number + password to sync the same books (account-based sync).
router.post('/register', validate(passwordSchema), (req, res) => {
  const { phone, password } = req.body;
  // Closed vault: only admin-listed phones may create an account, ever.
  // Checked BEFORE the existing-user lookup so outsiders learn nothing.
  if (!isPhoneAllowed(phone)) {
    return res.status(403).json({ error: 'not_invited' });
  }
  const existing = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone);
  if (existing) {
    return res.status(409).json({ error: 'user_exists' });
  }
  const r = db
    .prepare('INSERT INTO users (phone, name, referral_code, password_hash) VALUES (?, ?, ?, ?)')
    .run(phone, 'Shop Owner', newReferralCode(), bcrypt.hashSync(password, 10));
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(Number(r.lastInsertRowid));
  claimStaffInvites(user.id, phone);
  const sess = issueSession(user);
  res.status(201).json({ ...sess, user: publicUser(user), is_new: true, staff_books: staffBooks(user.id) });
});

// Any device: same number + password → same account, same books.
router.post('/login', validate(passwordSchema), (req, res) => {
  const { phone, password } = req.body;
  // Closed vault: unlisted phones get the GENERIC error on purpose — the
  // response must not reveal whether a number is allow-listed or registered.
  if (!isPhoneAllowed(phone)) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  const user = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone);
  // Generic error on purpose: do not reveal whether the number is registered.
  if (!user || !user.password_hash || !bcrypt.compareSync(password, user.password_hash)) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }
  claimStaffInvites(user.id, phone);
  const sess = issueSession(user);
  res.json({ ...sess, user: publicUser(user), is_new: false, staff_books: staffBooks(user.id) });
});

// --- OTP (PARKED — SMS seam, re-enable when a provider is funded) -----------
/*
router.post('/request-otp', validate(phoneSchema), (req, res) => {
  const out = requestOtp(db, req.body.phone);
  if (out.error === 'resend_cooldown') {
    return res.status(429).json({ error: 'resend_cooldown', resend_after_s: out.resend_after_s });
  }
  if (out.error === 'too_many_requests') {
    return res.status(429).json({ error: 'too_many_requests' });
  }
  res.json({ ok: true, resend_after_s: out.resend_after_s, ...(out.demo_code ? { demo_code: out.demo_code } : {}) });
});

router.post(
  '/verify-otp',
  validate(z.object({ phone: z.string().regex(/^[0-9]{10}$/), code: z.string().min(4).max(8) })),
  (req, res) => {
    const { phone, code } = req.body;
    const v = verifyOtp(db, phone, code);
    if (!v.ok) {
      const status = v.error === 'too_many_attempts' ? 429 : 401;
      return res.status(status).json({ error: v.error });
    }
    let user = db.prepare('SELECT * FROM users WHERE phone = ?').get(phone);
    let isNew = false;
    if (!user) {
      isNew = true;
      const ref =
        'KB' +
        Array.from(crypto.randomBytes(4))
          .map((b) => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'[b % 31])
          .join('');
      const r = db.prepare('INSERT INTO users (phone, name, referral_code) VALUES (?, ?, ?)').run(phone, 'Shop Owner', ref);
      user = db.prepare('SELECT * FROM users WHERE id = ?').get(Number(r.lastInsertRowid));
    }
    const sess = issueSession(user);
    // Claim staff invites for this phone (same OTP login doubles as staff claim).
    db.prepare("UPDATE staff_members SET member_user_id=?, status='active' WHERE phone=? AND status='invited'")
      .run(user.id, phone);
    res.json({ ...sess, user: publicUser(user), is_new: isNew, staff_books: staffBooks(user.id) });
  }
);
--- end OTP parked block ---
*/

// --- Refresh (rotation + reuse detection) ----------------------------------
router.post('/refresh', validate(z.object({ refresh: z.string().min(20) })), (req, res) => {
  const hash = crypto.createHash('sha256').update(req.body.refresh).digest('hex');
  const row = db.prepare('SELECT * FROM refresh_tokens WHERE token_hash = ?').get(hash);
  if (!row || row.expires_at < Date.now()) {
    return res.status(401).json({ error: 'invalid_refresh' });
  }
  // Reuse of a rotated token → possible theft: revoke whole family.
  if (row.replaced_by) {
    db.prepare('UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL').run(Date.now(), row.user_id);
    return res.status(401).json({ error: 'refresh_reused' });
  }
  if (row.revoked_at) {
    return res.status(401).json({ error: 'invalid_refresh' });
  }
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(row.user_id);
  if (!user) return res.status(401).json({ error: 'invalid_refresh' });
  const next = storeRefresh(user.id);
  db.prepare('UPDATE refresh_tokens SET revoked_at = ?, replaced_by = ? WHERE id = ?').run(Date.now(), next.id, row.id);
  res.json({ access: signAccess(user), refresh: next.raw });
});

// --- Session / profile ------------------------------------------------------
const auth = require('./_auth').requireAuth;

router.get('/me', auth, (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!user) return res.status(404).json({ error: 'not_found' });
  res.json({ user: publicUser(user), staff_books: staffBooks(user.id) });
});

router.patch(
  '/profile',
  auth,
  validate(
    z.object({
      name: z.string().min(1).max(80).optional(),
      business_name: z.string().max(120).optional(),
      business_category: z.string().max(120).optional(),
    })
  ),
  (req, res) => {
    const sets = [];
    const vals = [];
    for (const k of ['name', 'business_name', 'business_category']) {
      if (req.body[k] !== undefined) {
        sets.push(`${k} = ?`);
        vals.push(req.body[k]);
      }
    }
    if (sets.length === 0) return res.status(400).json({ error: 'nothing_to_update' });
    vals.push(req.user.id);
    db.prepare(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`).run(...vals);
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
    res.json({ user: publicUser(user) });
  }
);

// --- PIN / AppLock ------------------------------------------------------------
router.post(
  '/pin-set',
  auth,
  validate(z.object({ pin: z.string().regex(PIN_RE, '4-8 digit PIN'), current_pin: z.string().optional() })),
  (req, res) => {
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
    if (user.pin_hash) {
      if (!req.body.current_pin || !bcrypt.compareSync(req.body.current_pin, user.pin_hash)) {
        return res.status(401).json({ error: 'invalid_current_pin' });
      }
    }
    db.prepare('UPDATE users SET pin_hash = ?, pin_fail_count = 0, pin_locked_until = 0 WHERE id = ?').run(
      bcrypt.hashSync(req.body.pin, 10),
      req.user.id
    );
    res.json({ ok: true });
  }
);

router.post('/pin-verify', auth, validate(z.object({ pin: z.string().min(4).max(8) })), (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!user.pin_hash) return res.status(400).json({ error: 'pin_not_set' });
  if (Date.now() < Number(user.pin_locked_until)) {
    return res.status(423).json({ error: 'pin_locked', retry_after_s: Math.ceil((Number(user.pin_locked_until) - Date.now()) / 1000) });
  }
  if (!bcrypt.compareSync(req.body.pin, user.pin_hash)) {
    const fails = Number(user.pin_fail_count) + 1;
    if (fails >= MAX_PIN_FAILS) {
      db.prepare('UPDATE users SET pin_fail_count = 0, pin_locked_until = ? WHERE id = ?').run(Date.now() + PIN_LOCK_MS, req.user.id);
      return res.status(423).json({ error: 'pin_locked', retry_after_s: PIN_LOCK_MS / 1000 });
    }
    db.prepare('UPDATE users SET pin_fail_count = ? WHERE id = ?').run(fails, req.user.id);
    return res.status(401).json({ error: 'invalid_pin', attempts_left: MAX_PIN_FAILS - fails });
  }
  db.prepare('UPDATE users SET pin_fail_count = 0, pin_locked_until = 0 WHERE id = ?').run(req.user.id);
  res.json({ ok: true });
});

router.post('/pin-remove', auth, validate(z.object({ current_pin: z.string().min(4).max(8) })), (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!user.pin_hash || !bcrypt.compareSync(req.body.current_pin, user.pin_hash)) {
    return res.status(401).json({ error: 'invalid_current_pin' });
  }
  db.prepare('UPDATE users SET pin_hash = NULL, pin_fail_count = 0, pin_locked_until = 0 WHERE id = ?').run(req.user.id);
  res.json({ ok: true });
});

// --- Logout ---------------------------------------------------------------------
router.post('/logout', validate(z.object({ refresh: z.string().min(20).optional() })), (req, res) => {
  if (req.body.refresh) {
    const hash = crypto.createHash('sha256').update(req.body.refresh).digest('hex');
    db.prepare('UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ?').run(Date.now(), hash);
  }
  res.json({ ok: true });
});

module.exports = router;
