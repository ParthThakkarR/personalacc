'use strict';
/**
 * Recycle bin (mirrors recyclebin/deletekhata): soft-deleted customers and
 * transactions can be restored or purged forever. Restore/ purge need 'edit'.
 */
const express = require('express');
const { openDb, migrate } = require('../db');
const { logStaffWrite } = require('../middleware/staff');
const { decryptCell } = require('../utils/cipher');
const { requireAuth, resolveBook, requirePerm } = require('./_auth');

/** Recycle bin shows customer names — decrypt (ciphertext at rest). */
function decRow(row) {
  for (const f of ['name', 'phone', 'customer_name']) {
    if (row && typeof row[f] === 'string') {
      try { row[f] = decryptCell(row[f]); } catch (_) { row[f] = '🔒'; }
    }
  }
  return row;
}

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook);

router.get('/', requirePerm('view'), (req, res) => {
  const customers = db
    .prepare('SELECT id, name, phone, deleted_at FROM customers WHERE user_id=? AND deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT 200')
    .all(req.book.ownerId)
    .map(decRow);
  const transactions = db
    .prepare(
      `SELECT t.id, t.kind, t.amount, t.note, t.txn_date, t.deleted_at, c.name AS customer_name
       FROM transactions t JOIN customers c ON c.id=t.customer_id
       WHERE t.user_id=? AND t.deleted_at IS NOT NULL ORDER BY t.deleted_at DESC LIMIT 200`
    )
    .all(req.book.ownerId)
    .map(decRow);
  const expenses = db
    .prepare('SELECT id, amount, note, category, expense_date, deleted_at FROM expenses WHERE user_id=? AND deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT 200')
    .all(req.book.ownerId);
  const items = db
    .prepare('SELECT id, name, unit, rate, stock, deleted_at FROM items WHERE user_id=? AND deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT 200')
    .all(req.book.ownerId);
  res.json({ customers, transactions, expenses, items });
});

router.post('/customers/:id/restore', requirePerm('edit'), (req, res) => {
  const r = db
    .prepare('UPDATE customers SET deleted_at=NULL WHERE id=? AND user_id=? AND deleted_at IS NOT NULL')
    .run(req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'customer_restore', `id=${req.params.id}`);
  res.json({ ok: true });
});

router.post('/transactions/:id/restore', requirePerm('edit'), (req, res) => {
  const t = db.prepare('SELECT * FROM transactions WHERE id=? AND user_id=?').get(req.params.id, req.book.ownerId);
  if (!t || !t.deleted_at) return res.status(404).json({ error: 'not_found' });
  const c = db.prepare('SELECT id FROM customers WHERE id=? AND deleted_at IS NULL').get(t.customer_id);
  if (!c) return res.status(410).json({ error: 'customer_deleted' });
  db.prepare('UPDATE transactions SET deleted_at=NULL WHERE id=?').run(t.id);
  logStaffWrite(req, 'txn_restore', `id=${t.id}`);
  res.json({ ok: true });
});

router.delete('/customers/:id/permanent', requirePerm('edit'), (req, res) => {
  const c = db.prepare('SELECT id FROM customers WHERE id=? AND user_id=? AND deleted_at IS NOT NULL').get(req.params.id, req.book.ownerId);
  if (!c) return res.status(404).json({ error: 'not_found' });
  db.prepare('DELETE FROM transactions WHERE customer_id=? AND user_id=?').run(c.id, req.book.ownerId);
  db.prepare('DELETE FROM customers WHERE id=?').run(c.id);
  logStaffWrite(req, 'customer_purge', `id=${c.id}`);
  res.json({ ok: true });
});

router.delete('/transactions/:id/permanent', requirePerm('edit'), (req, res) => {
  const r = db.prepare('DELETE FROM transactions WHERE id=? AND user_id=? AND deleted_at IS NOT NULL').run(req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'txn_purge', `id=${req.params.id}`);
  res.json({ ok: true });
});

router.post('/expenses/:id/restore', requirePerm('edit'), (req, res) => {
  const r = db.prepare('UPDATE expenses SET deleted_at=NULL WHERE id=? AND user_id=? AND deleted_at IS NOT NULL').run(req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'expense_restore', `id=${req.params.id}`);
  res.json({ ok: true });
});

router.delete('/expenses/:id/permanent', requirePerm('edit'), (req, res) => {
  const r = db.prepare('DELETE FROM expenses WHERE id=? AND user_id=? AND deleted_at IS NOT NULL').run(req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'expense_purge', `id=${req.params.id}`);
  res.json({ ok: true });
});

router.post('/items/:id/restore', requirePerm('edit'), (req, res) => {
  const r = db.prepare('UPDATE items SET deleted_at=NULL WHERE id=? AND user_id=? AND deleted_at IS NOT NULL').run(req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'item_restore', `id=${req.params.id}`);
  res.json({ ok: true });
});

router.delete('/items/:id/permanent', requirePerm('edit'), (req, res) => {
  const r = db.prepare('DELETE FROM items WHERE id=? AND user_id=? AND deleted_at IS NOT NULL').run(req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'item_purge', `id=${req.params.id}`);
  res.json({ ok: true });
});

module.exports = router;
