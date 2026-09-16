'use strict';
/**
 * Staff management (owner-only): invite by phone → staff claims via normal
 * password register/login → role-gated book access. Owner sees an audit
 * feed of staff writes. (OTP-claim seam parked; see routes/auth.js.)
 */
const express = require('express');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const { ROLES } = require('../middleware/staff');
const { requireAuth, resolveBook, requireOwner } = require('./_auth');

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook, requireOwner);

const phoneSchema = z.object({
  phone: z.string().regex(/^[0-9]{10}$/),
  role: z.enum(ROLES),
});

router.get('/', (req, res) => {
  const rows = db
    .prepare('SELECT id, phone, role, status, member_user_id, created_at FROM staff_members WHERE owner_id=? ORDER BY created_at DESC')
    .all(req.book.ownerId);
  res.json({ staff: rows, roles: ROLES });
});

router.post('/invite', validate(phoneSchema), (req, res) => {
  const { phone, role } = req.body;
  const owner = db.prepare('SELECT phone FROM users WHERE id=?').get(req.book.ownerId);
  if (owner && owner.phone === phone) {
    return res.status(400).json({ error: 'cannot_invite_self' });
  }
  try {
    // Auto-activate if this phone already has an account (still OTP-claimed on next login).
    const existing = db.prepare('SELECT id FROM users WHERE phone=?').get(phone);
    db.prepare(
      `INSERT INTO staff_members (owner_id, member_user_id, phone, role, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).run(req.book.ownerId, existing ? existing.id : null, phone, role, existing ? 'active' : 'invited', Date.now());
    res.status(201).json({ ok: true, status: existing ? 'active' : 'invited' });
  } catch (e) {
    if (String(e.message).includes('UNIQUE')) return res.status(409).json({ error: 'already_invited' });
    throw e;
  }
});

router.post(
  '/role',
  validate(z.object({ phone: z.string().regex(/^[0-9]{10}$/), role: z.enum(ROLES) })),
  (req, res) => {
    const r = db
      .prepare("UPDATE staff_members SET role=? WHERE owner_id=? AND phone=? AND status!='revoked'")
      .run(req.body.role, req.book.ownerId, req.body.phone);
    if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
    res.json({ ok: true });
  }
);

router.post('/revoke', validate(z.object({ phone: z.string().regex(/^[0-9]{10}$/) })), (req, res) => {
  const r = db
    .prepare("UPDATE staff_members SET status='revoked', member_user_id=NULL WHERE owner_id=? AND phone=?")
    .run(req.book.ownerId, req.body.phone);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  res.json({ ok: true });
});

router.get('/activity', (req, res) => {
  const rows = db
    .prepare(
      `SELECT a.*, u.phone AS actor_phone, u.name AS actor_name FROM staff_audit a
       JOIN users u ON u.id=a.actor_user_id WHERE a.owner_id=? ORDER BY a.id DESC LIMIT 200`
    )
    .all(req.book.ownerId);
  res.json({ activity: rows });
});

module.exports = router;
