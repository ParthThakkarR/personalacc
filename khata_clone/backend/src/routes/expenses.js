'use strict';
/**
 * Expenses (cf. finance/expenses surface in APK). Soft-delete → recycle bin.
 * Permissions mirror transactions: add/edit for writes, totals for summary.
 */
const express = require('express');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const { logStaffWrite } = require('../middleware/staff');
const { requireAuth, resolveBook, requirePerm } = require('./_auth');

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook);

router.get('/', requirePerm('view'), (req, res) => {
  const month = (req.query.month || '').toString();
  let rows;
  if (/^\d{4}-\d{2}$/.test(month)) {
    rows = db
      .prepare("SELECT * FROM expenses WHERE user_id=? AND deleted_at IS NULL AND substr(expense_date,1,7)=? ORDER BY expense_date DESC, id DESC LIMIT 500")
      .all(req.book.ownerId, month);
  } else {
    rows = db
      .prepare('SELECT * FROM expenses WHERE user_id=? AND deleted_at IS NULL ORDER BY expense_date DESC, id DESC LIMIT 500')
      .all(req.book.ownerId);
  }
  const total = rows.reduce((s, r) => s + r.amount, 0);
  res.json({ expenses: rows, total });
});

router.post(
  '/',
  requirePerm('add'),
  validate(
    z.object({
      amount: z.number().int().positive().max(100000000),
      note: z.string().max(300).default(''),
      category: z.string().max(40).default('General'),
      expense_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    })
  ),
  (req, res) => {
    const r = db
      .prepare('INSERT INTO expenses (user_id, amount, note, category, expense_date) VALUES (?, ?, ?, ?, COALESCE(?, date(\'now\')))')
      .run(req.book.ownerId, req.body.amount, req.body.note, req.body.category, req.body.expense_date || null);
    logStaffWrite(req, 'expense_add', `${req.body.category} ${req.body.amount}`);
    res.status(201).json({ id: Number(r.lastInsertRowid) });
  }
);

router.delete('/:id', requirePerm('edit'), (req, res) => {
  const r = db.prepare('UPDATE expenses SET deleted_at=? WHERE id=? AND user_id=? AND deleted_at IS NULL').run(Date.now(), req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'expense_delete', `id=${req.params.id}`);
  res.json({ ok: true });
});

module.exports = router;