'use strict';
/**
 * Collections (mirrors researched W7: bulkreminder + payment links).
 * Payment links are MOCK (no Razorpay keys in a college project): creating a
 * link returns a khata-clone://pay/<ref> handle, and the demo "customer pays"
 * call settles it into the ledger automatically — the same auto-entry the
 * real app advertises ("entry in khata, automatically").
 */
const express = require('express');
const crypto = require('node:crypto');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const { logStaffWrite } = require('../middleware/staff');
const { decryptCell } = require('../utils/cipher');
const { requireAuth, resolveBook, requirePerm } = require('./_auth');

function decName(row, field = 'customer_name') {
  if (row && typeof row[field] === 'string') {
    try { row[field] = decryptCell(row[field]); } catch (_) { row[field] = '🔒'; }
  }
  return row;
}

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook);

router.post(
  '/links',
  requirePerm('add'),
  validate(z.object({ customer_id: z.number().int().positive(), amount: z.number().int().positive().max(100000000) })),
  (req, res) => {
    const c = db.prepare('SELECT id, name FROM customers WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.body.customer_id, req.book.ownerId);
    if (!c) return res.status(404).json({ error: 'customer_not_found' });
    const ref = 'KB' + crypto.randomBytes(6).toString('hex').toUpperCase();
    const r = db
      .prepare('INSERT INTO collection_links (owner_id, customer_id, amount, ref, created_at) VALUES (?, ?, ?, ?, ?)')
      .run(req.book.ownerId, c.id, req.body.amount, ref, Date.now());
    logStaffWrite(req, 'paylink_create', `${ref} ${req.body.amount} (customer ${c.id})`);
    res.status(201).json({ id: Number(r.lastInsertRowid), ref, link: `khata-clone://pay/${ref}`, amount: req.body.amount });
  }
);

router.get('/links', requirePerm('view'), (req, res) => {
  const rows = db
    .prepare(
      `SELECT l.*, c.name AS customer_name FROM collection_links l
       JOIN customers c ON c.id=l.customer_id WHERE l.owner_id=? ORDER BY l.id DESC LIMIT 200`
    )
    .all(req.book.ownerId)
    .map((r) => decName(r));
  res.json({ links: rows });
});

// Demo customer payment: settles an open link into the ledger (idempotent).
// Race-safe: the status flip is a single conditional UPDATE, so two
// concurrent pays can't both settle (loser gets already_paid).
router.post('/links/:ref/pay', requirePerm('add'), (req, res) => {
  const link = db.prepare('SELECT * FROM collection_links WHERE ref=? AND owner_id=?').get(req.params.ref, req.book.ownerId);
  if (!link) return res.status(404).json({ error: 'not_found' });
  if (link.status === 'paid') return res.status(409).json({ error: 'already_paid' });
  const c = db.prepare('SELECT id FROM customers WHERE id=? AND deleted_at IS NULL').get(link.customer_id);
  if (!c) return res.status(410).json({ error: 'customer_deleted' });
  const flip = db.prepare("UPDATE collection_links SET status='paid', paid_at=? WHERE id=? AND status='open'").run(Date.now(), link.id);
  if (flip.changes === 0) return res.status(409).json({ error: 'already_paid' });
  const t = db
    .prepare("INSERT INTO transactions (user_id, customer_id, kind, amount, note, txn_date) VALUES (?, ?, 'DEBIT', ?, ?, date('now'))")
    .run(req.book.ownerId, link.customer_id, link.amount, `Payment link ${link.ref}`);
  logStaffWrite(req, 'paylink_paid', `${link.ref} ${link.amount}`);
  res.json({ ok: true, txn_id: Number(t.lastInsertRowid) });
});

router.post(
  '/reminders',
  requirePerm('add'),
  validate(
    z.object({
      customer_ids: z.array(z.number().int().positive()).min(1).max(100),
      channel: z.enum(['sms', 'whatsapp', 'call']),
      message: z.string().max(300).default(''),
    })
  ),
  (req, res) => {
    const ins = db.prepare(
      "INSERT INTO reminders (owner_id, customer_id, channel, message, status, created_at) VALUES (?, ?, ?, ?, 'queued', ?)"
    );
    let queued = 0;
    for (const cid of new Set(req.body.customer_ids)) {
      const c = db.prepare('SELECT id FROM customers WHERE id=? AND user_id=? AND deleted_at IS NULL').get(cid, req.book.ownerId);
      if (c) {
        ins.run(req.book.ownerId, cid, req.body.channel, req.body.message, Date.now());
        queued++;
      }
    }
    logStaffWrite(req, 'reminder_queue', `${queued} via ${req.body.channel}`);
    res.status(201).json({ ok: true, queued });
  }
);

router.get('/reminders', requirePerm('view'), (req, res) => {
  const rows = db
    .prepare(
      `SELECT r.*, c.name AS customer_name FROM reminders r
       JOIN customers c ON c.id=r.customer_id WHERE r.owner_id=? ORDER BY r.id DESC LIMIT 200`
    )
    .all(req.book.ownerId)
    .map((r) => decName(r));
  res.json({ reminders: rows });
});

module.exports = router;
