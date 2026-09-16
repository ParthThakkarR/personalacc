'use strict';
const express = require('express');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const { logStaffWrite } = require('../middleware/staff');
const { requireAuth, resolveBook, requirePerm } = require('./_auth');

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook);

router.post(
  '/',
  requirePerm('add'),
  validate(
    z.object({
      customer_id: z.number().int().positive(),
      kind: z.enum(['CREDIT', 'DEBIT']),
      amount: z.number().int().positive().max(100000000),
      note: z.string().max(300).default(''),
      txn_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    })
  ),
  (req, res) => {
    const c = db.prepare('SELECT id FROM customers WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.body.customer_id, req.book.ownerId);
    if (!c) return res.status(404).json({ error: 'customer_not_found' });
    const r = db
      .prepare('INSERT INTO transactions (user_id, customer_id, kind, amount, note, txn_date) VALUES (?, ?, ?, ?, ?, COALESCE(?, date(\'now\')))')
      .run(req.book.ownerId, req.body.customer_id, req.body.kind, req.body.amount, req.body.note, req.body.txn_date || null);
    logStaffWrite(req, 'txn_add', `${req.body.kind} ${req.body.amount} (customer ${req.body.customer_id})`);
    res.status(201).json({ id: Number(r.lastInsertRowid) });
  }
);

router.get('/', requirePerm('view'), (req, res) => {
  const rows = db
    .prepare('SELECT * FROM transactions WHERE user_id=? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 200')
    .all(req.book.ownerId);
  res.json({ transactions: rows });
});

router.delete('/:id', requirePerm('edit'), (req, res) => {
  const r = db.prepare('UPDATE transactions SET deleted_at=? WHERE id=? AND user_id=? AND deleted_at IS NULL').run(Date.now(), req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'txn_delete', `id=${req.params.id}`);
  res.json({ ok: true });
});

// Cashbook summary: total CREDIT (to-receive), DEBIT (received), net
router.get('/summary/cashbook', requirePerm('totals'), (req, res) => {
  const s = db
    .prepare(
      `SELECT COALESCE(SUM(CASE WHEN kind='CREDIT' THEN amount ELSE 0 END),0) AS credit,
              COALESCE(SUM(CASE WHEN kind='DEBIT' THEN amount ELSE 0 END),0) AS debit FROM transactions WHERE user_id=? AND deleted_at IS NULL`
    )
    .get(req.book.ownerId);
  res.json({ credit: s.credit, debit: s.debit, net_receivable: s.credit - s.debit });
});

router.get(
  '/:id/attachments',
  requirePerm('view'),
  (req, res) => {
    const t = db.prepare('SELECT id FROM transactions WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.params.id, req.book.ownerId);
    if (!t) return res.status(404).json({ error: 'not_found' });
    const rows = db.prepare('SELECT id, mime, caption, length(data) AS size_bytes, created_at FROM ledger_attachments WHERE transaction_id=? ORDER BY id').all(t.id);
    res.json({ attachments: rows });
  }
);

router.post(
  '/:id/attachments',
  requirePerm('edit'),
  validate(
    z.object({
      mime: z.string().max(40).default('image/jpeg'),
      caption: z.string().max(200).default(''),
      data: z.string().min(10).max(400000),
    })
  ),
  (req, res) => {
    const t = db.prepare('SELECT id FROM transactions WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.params.id, req.book.ownerId);
    if (!t) return res.status(404).json({ error: 'not_found' });
    const r = db
      .prepare('INSERT INTO ledger_attachments (user_id, transaction_id, mime, data, caption) VALUES (?, ?, ?, ?, ?)')
      .run(req.book.ownerId, t.id, req.body.mime, req.body.data, req.body.caption);
    logStaffWrite(req, 'attachment_add', `txn=${t.id}`);
    res.status(201).json({ id: Number(r.lastInsertRowid) });
  }
);

// Full attachment payload (image data) for the app to display.
router.get(
  '/attachments/:attId/data',
  requirePerm('view'),
  (req, res) => {
    const a = db.prepare('SELECT * FROM ledger_attachments WHERE id=? AND user_id=?').get(req.params.attId, req.book.ownerId);
    if (!a) return res.status(404).json({ error: 'not_found' });
    res.json({ mime: a.mime, caption: a.caption, data: a.data });
  }
);

router.delete('/attachments/:attId', requirePerm('edit'), (req, res) => {
  const r = db.prepare('DELETE FROM ledger_attachments WHERE id=? AND user_id=?').run(req.params.attId, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'attachment_delete', `att=${req.params.attId}`);
  res.json({ ok: true });
});

module.exports = router;
