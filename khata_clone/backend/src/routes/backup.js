'use strict';
/**
 * Backup/restore (mirrors backuprestore + khatabook.com/recover).
 * Owner-only. Export = full book JSON. Import = validated overwrite-restore
 * inside a transaction (documented behavior: restore replaces book content).
 */
const express = require('express');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const { encryptCell } = require('../utils/cipher');
const { requireAuth, resolveBook, requireOwner } = require('./_auth');

/** Import payloads may carry PLAINTEXT (hand-written) or CIPHERTEXT (our own
 * export dumps, `v2:`-prefixed). Seal plaintext, pass sealed values through
 * untouched — never double-encrypt, or restores would show ciphertext. */
function ensureEncrypted(v) {
  if (v === null || v === undefined || v === '') return v;
  if (String(v).startsWith('v2:')) return v;
  return encryptCell(String(v));
}

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook, requireOwner);

router.get('/export', (req, res) => {
  const oid = req.book.ownerId;
  res.json({
    version: 1,
    exported_at: new Date().toISOString(),
    customers: db.prepare('SELECT * FROM customers WHERE user_id=?').all(oid),
    transactions: db.prepare('SELECT * FROM transactions WHERE user_id=?').all(oid),
    bills: db.prepare('SELECT * FROM bills WHERE user_id=?').all(oid),
    bill_items: db
      .prepare('SELECT bi.* FROM bill_items bi JOIN bills b ON b.id=bi.bill_id WHERE b.user_id=?')
      .all(oid),
    collection_links: db.prepare('SELECT * FROM collection_links WHERE owner_id=?').all(oid),
    reminders: db.prepare('SELECT * FROM reminders WHERE owner_id=?').all(oid),
    expenses: db.prepare('SELECT * FROM expenses WHERE user_id=?').all(oid),
    items: db.prepare('SELECT * FROM items WHERE user_id=?').all(oid),
    attachments: db
      .prepare('SELECT la.* FROM ledger_attachments la JOIN transactions t ON t.id=la.transaction_id WHERE t.user_id=?')
      .all(oid),
  });
});

const itemSchema = z.object({
  name: z.string().min(1).max(100),
  qty: z.number().positive().max(100000),
  unit: z.string().max(10).default('PCS'),
  rate: z.number().int().min(0),
  amount: z.number().int().min(0),
});

router.post(
  '/import',
  validate(
    z.object({
      version: z.literal(1),
      customers: z.array(z.object({
        // `id` is present in our own export dumps: it lets transactions and
        // bills that reference `customer_id` (export shape) resolve to the
        // positional `customer_index` the restore uses internally.
        id: z.number().int().positive().nullable().optional(),
        // Lengths are ciphertext-aware: our own exports carry `v2:`-sealed
        // values (plaintext 80/15/200 chars + 28 B GCM overhead, base64).
        name: z.string().min(1).max(200),
        phone: z.string().max(80).default(''),
        address: z.string().max(400).default(''),
        opening_balance: z.number().int().default(0),
        deleted_at: z.number().nullable().optional(),
      })).max(5000),
      transactions: z.array(z.object({
        customer_index: z.number().int().min(0).nullable().optional(),
        // Export shape: our own GET /backup/export writes customer_id.
        customer_id: z.number().int().positive().nullable().optional(),
        kind: z.enum(['CREDIT', 'DEBIT']),
        amount: z.number().int().positive().max(100000000),
        note: z.string().max(300).default(''),
        txn_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        deleted_at: z.number().nullable().optional(),
      })).max(20000),
      bills: z.array(z.object({
        // `id` + top-level `bill_items` carry our own export shape through.
        id: z.number().int().positive().nullable().optional(),
        customer_index: z.number().int().min(0).nullable().optional(),
        customer_id: z.number().int().positive().nullable().optional(),
        invoice_no: z.string().min(1).max(40),
        invoice_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        gst_slab_index: z.number().int().min(0).max(20).default(1),
        discount: z.number().int().min(0).default(0),
        total: z.number().int().min(0).default(0),
        items: z.array(itemSchema).max(100).default([]),
      })).max(2000).default([]),
      // Our own export writes bill lines here, keyed by the OLD bill id.
      bill_items: z.array(z.object({
        bill_id: z.number().int().positive(),
        name: z.string().min(1).max(100),
        qty: z.number().positive().max(100000),
        unit: z.string().max(10).default('PCS'),
        rate: z.number().int().min(0),
        amount: z.number().int().min(0),
      })).max(20000).default([]),
      expenses: z.array(z.object({
        amount: z.number().int().positive().max(100000000),
        note: z.string().max(300).default(''),
        category: z.string().max(40).default('General'),
        expense_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        deleted_at: z.number().nullable().optional(),
      })).max(5000).default([]),
      items: z.array(z.object({
        name: z.string().min(1).max(80),
        unit: z.string().max(10).default('PCS'),
        rate: z.number().int().min(0).max(100000000),
        stock: z.number().min(0).max(100000000).default(0),
        gst_slab_index: z.number().int().min(0).max(20).default(1),
        deleted_at: z.number().nullable().optional(),
      })).max(5000).default([]),
    })
  ),
  (req, res) => {
    const oid = req.book.ownerId;
    const { customers, transactions, bills, expenses, items } = req.body;
    // Map OLD customer ids (export shape) → positional index in this payload.
    const custIdxById = new Map();
    customers.forEach((c, i) => {
      if (c.id != null) custIdxById.set(c.id, i);
    });
    const resolveCustomer = (e) => {
      if (e.customer_index != null) return e.customer_index;
      if (e.customer_id != null && custIdxById.has(e.customer_id)) {
        return custIdxById.get(e.customer_id);
      }
      return -1;
    };
    for (const t of transactions) {
      t.customer_index = resolveCustomer(t);
      if (t.customer_index < 0 || t.customer_index >= customers.length) {
        return res.status(400).json({ error: 'bad_customer_index' });
      }
    }
    for (const b of bills) {
      if (b.customer_index == null && b.customer_id != null) {
        b.customer_index = resolveCustomer(b);
      }
      // -1 = referenced customer not in this payload → walk-in bill.
      if (b.customer_index == null || b.customer_index < 0) b.customer_index = null;
      if (b.customer_index != null && b.customer_index >= customers.length) {
        return res.status(400).json({ error: 'bad_customer_index' });
      }
    }
    // Re-attach exported bill lines (keyed by OLD bill id) to their bills
    // when the payload carries no embedded items (i.e. it is our export).
    const linesByBill = new Map();
    for (const bi of req.body.bill_items || []) {
      if (!linesByBill.has(bi.bill_id)) linesByBill.set(bi.bill_id, []);
      linesByBill.get(bi.bill_id).push(bi);
    }
    for (const b of bills) {
      if ((!b.items || b.items.length === 0) && b.id != null && linesByBill.has(b.id)) {
        b.items = linesByBill.get(b.id);
      }
    }
    const ids = { customers: [], bills: [] };
    db.exec('BEGIN');
    try {
      db.prepare('DELETE FROM transactions WHERE user_id=?').run(oid);
      db.prepare('DELETE FROM bill_items WHERE bill_id IN (SELECT id FROM bills WHERE user_id=?)').run(oid);
      db.prepare('DELETE FROM bills WHERE user_id=?').run(oid);
      db.prepare('DELETE FROM collection_links WHERE owner_id=?').run(oid);
      db.prepare('DELETE FROM reminders WHERE owner_id=?').run(oid);
      db.prepare('DELETE FROM expenses WHERE user_id=?').run(oid);
      db.prepare('DELETE FROM items WHERE user_id=?').run(oid);
      db.prepare('DELETE FROM customers WHERE user_id=?').run(oid);
      const addC = db.prepare(
        'INSERT INTO customers (user_id, name, phone, address, opening_balance, deleted_at) VALUES (?, ?, ?, ?, ?, ?)'
      );
      customers.forEach((c) => {
        const r = addC.run(oid, ensureEncrypted(c.name), ensureEncrypted(c.phone), ensureEncrypted(c.address), c.opening_balance, c.deleted_at ?? null);
        ids.customers.push(Number(r.lastInsertRowid));
      });
      const addT = db.prepare(
        'INSERT INTO transactions (user_id, customer_id, kind, amount, note, txn_date, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
      );
      transactions.forEach((t) => {
        addT.run(oid, ids.customers[t.customer_index], t.kind, t.amount, t.note, t.txn_date, t.deleted_at ?? null);
      });
      const addB = db.prepare(
        'INSERT INTO bills (user_id, customer_id, invoice_no, invoice_date, gst_slab_index, discount, total) VALUES (?, ?, ?, ?, ?, ?, ?)'
      );
      const addI = db.prepare('INSERT INTO bill_items (bill_id, name, qty, unit, rate, amount) VALUES (?, ?, ?, ?, ?, ?)');
      bills.forEach((b) => {
        const r = addB.run(oid, b.customer_index != null ? ids.customers[b.customer_index] : null,
          b.invoice_no, b.invoice_date, b.gst_slab_index, b.discount, b.total);
        const bid = Number(r.lastInsertRowid);
        ids.bills.push(bid);
        b.items.forEach((it) => addI.run(bid, it.name, it.qty, it.unit, it.rate, it.amount));
      });
      const addE = db.prepare(
        'INSERT INTO expenses (user_id, amount, note, category, expense_date, deleted_at) VALUES (?, ?, ?, ?, ?, ?)'
      );
      expenses.forEach((e) => addE.run(oid, e.amount, e.note, e.category, e.expense_date, e.deleted_at ?? null));
      const addItem = db.prepare(
        'INSERT INTO items (user_id, name, unit, rate, stock, gst_slab_index, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
      );
      items.forEach((it) => addItem.run(oid, it.name, it.unit, it.rate, it.stock, it.gst_slab_index, it.deleted_at ?? null));
      db.exec('COMMIT');
    } catch (e) {
      try { db.exec('ROLLBACK'); } catch (_) {}
      throw e;
    }
    res.json({ ok: true, customers: ids.customers.length, bills: ids.bills.length });
  }
);

module.exports = router;
