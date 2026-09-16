'use strict';
const express = require('express');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const { logStaffWrite } = require('../middleware/staff');
const { requireAuth, resolveBook, requirePerm } = require('./_auth');
const { encryptCell, decryptCell, encField } = require('../utils/cipher');

/** PII boundary: customer name/phone/address are AES-256-GCM encrypted at
 * rest (CIPHER_KEY). Numeric balances/dates stay plaintext so aggregation
 * keeps working. decryptCell passes legacy plaintext rows through, so
 * pre-encryption data keeps reading fine. */
function encCustomerBody(body) {
  const out = { ...body };
  for (const f of ['name', 'phone', 'address']) encField(out, f);
  return out;
}

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook);

/** Decrypt confidential customer fields on an already-fetched row (in place). */
function decCustomer(row) {
  if (!row) return row;
  for (const f of ['name', 'phone', 'address']) {
    try { row[f] = decryptCell(row[f]); } catch (_) { row[f] = '🔒'; }
  }
  return row;
}

/** Decrypts every row in a result array of customers (in place). */
function decCustomers(rows) {
  (rows || []).forEach(decCustomer);
  return rows;
}

router.get('/', requirePerm('view'), (req, res) => {
  const q = (req.query.q || '').toString().trim().toLowerCase();
  // NOTE: names/phones are ciphertext at rest, so LIKE can't match them.
  // Result sets are capped (200) — decrypt then filter in JS instead.
  const rows = decCustomers(
    db
      .prepare(
        `SELECT c.*, COALESCE(SUM(CASE WHEN t.kind='CREDIT' THEN t.amount ELSE -t.amount END),0) + c.opening_balance AS balance,
         COUNT(t.id) AS txn_count FROM customers c LEFT JOIN transactions t ON t.customer_id=c.id AND t.deleted_at IS NULL
         WHERE c.user_id=? AND c.deleted_at IS NULL GROUP BY c.id ORDER BY c.created_at DESC LIMIT 200`
      )
      .all(req.book.ownerId)
  );
  const out = q
    ? rows.filter(
        (c) =>
          String(c.name || '').toLowerCase().includes(q) ||
          String(c.phone || '').includes(q)
      )
    : rows;
  res.json({ customers: out });
});

router.post(
  '/',
  requirePerm('add'),
  validate(z.object({ name: z.string().min(1).max(80), phone: z.string().max(15).default(''), address: z.string().max(200).default(''), opening_balance: z.number().int().default(0) })),
  (req, res) => {
    const body = encCustomerBody(req.body);
    const r = db
      .prepare('INSERT INTO customers (user_id, name, phone, address, opening_balance) VALUES (?, ?, ?, ?, ?)')
      .run(req.book.ownerId, body.name, body.phone, body.address, body.opening_balance);
    logStaffWrite(req, 'customer_add', `id=${Number(r.lastInsertRowid)}`);
    res.status(201).json({ id: Number(r.lastInsertRowid) });
  }
);

router.get('/:id', requirePerm('view'), (req, res) => {
  const c = db.prepare('SELECT * FROM customers WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.params.id, req.book.ownerId);
  if (!c) return res.status(404).json({ error: 'not_found' });
  decCustomer(c);
  const txns = db
    .prepare(`SELECT t.*, EXISTS(SELECT 1 FROM ledger_attachments la WHERE la.transaction_id=t.id) AS has_attachment
              FROM transactions t WHERE t.customer_id=? AND t.user_id=? AND t.deleted_at IS NULL ORDER BY t.txn_date DESC, t.id DESC LIMIT 500`)
    .all(c.id, req.book.ownerId);
  const bal = db
    .prepare("SELECT COALESCE(SUM(CASE WHEN kind='CREDIT' THEN amount ELSE -amount END),0) AS b FROM transactions WHERE customer_id=? AND user_id=? AND deleted_at IS NULL")
    .get(c.id, req.book.ownerId);
  res.json({ customer: c, balance: (bal?.b || 0) + (c.opening_balance || 0), transactions: txns });
});

router.get('/:id/passbook', requirePerm('view'), (req, res) => {
  const c = db.prepare('SELECT * FROM customers WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.params.id, req.book.ownerId);
  if (!c) return res.status(404).json({ error: 'not_found' });
  decCustomer(c);
  const rows = db
    .prepare('SELECT * FROM transactions WHERE customer_id=? AND user_id=? AND deleted_at IS NULL ORDER BY txn_date ASC, id ASC')
    .all(c.id, req.book.ownerId);
  let running = c.opening_balance || 0;
  const entries = rows.map((t) => {
    running += t.kind === 'CREDIT' ? t.amount : -t.amount;
    return { ...t, running_balance: running };
  });
  const summary = {
    opening: c.opening_balance || 0,
    total_credit: rows.reduce((s, t) => s + (t.kind === 'CREDIT' ? t.amount : 0), 0),
    total_debit: rows.reduce((s, t) => s + (t.kind === 'DEBIT' ? t.amount : 0), 0),
    closing: running,
  };
  res.json({ customer: c, entries, summary });
});

// Printable bank-style passbook (standalone HTML, shareable/offline-printable).
router.get('/:id/passbook.html', requirePerm('view'), (req, res) => {
  const c = db.prepare('SELECT * FROM customers WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.params.id, req.book.ownerId);
  if (!c) return res.status(404).json({ error: 'not_found' });
  decCustomer(c);
  const owner = db.prepare('SELECT name, business_name, phone FROM users WHERE id=?').get(req.book.ownerId) || {};
  const rows = db
    .prepare('SELECT * FROM transactions WHERE customer_id=? AND user_id=? AND deleted_at IS NULL ORDER BY txn_date ASC, id ASC')
    .all(c.id, req.book.ownerId);
  let running = c.opening_balance || 0;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const money = (n) => '₹' + Number(n).toLocaleString('en-IN');
  const lines = rows
    .map((t) => {
      running += t.kind === 'CREDIT' ? t.amount : -t.amount;
      return `<tr><td>${esc(t.txn_date)}</td><td>${t.kind === 'CREDIT' ? esc(t.note || 'Udhaar') : esc(t.note || 'Payment')}</td><td>${t.kind === 'CREDIT' ? money(t.amount) : ''}</td><td>${t.kind === 'DEBIT' ? money(t.amount) : ''}</td><td>${money(running)}</td></tr>`;
    })
    .join('');
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>Passbook — ${esc(c.name)}</title>
<style>body{font-family:Arial,Helvetica,sans-serif;max-width:760px;margin:24px auto;color:#111}
h1{font-size:20px;margin:0 0 2px}h2{font-size:14px;font-weight:400;color:#555;margin:0 0 16px}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{border-bottom:1px solid #ddd;padding:8px 6px;text-align:left}
th{background:#f6f6f6;text-transform:uppercase;font-size:11px;color:#555}
.summary{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:10px 14px;margin-bottom:14px;font-size:13px}
.summary b{color:#15803d}.right{text-align:right}</style></head><body>
<h1>${esc(owner.business_name || owner.name || 'My Shop')} — Passbook</h1>
<h2>${esc(c.name)}${c.phone ? ' · ' + esc(c.phone) : ''}</h2>
<div class="summary">Opening <b>${money(c.opening_balance || 0)}</b> &nbsp;·&nbsp; Udhaar given
<b>${money(rows.filter((t) => t.kind === 'CREDIT').reduce((s, t) => s + t.amount, 0))}</b>
&nbsp;·&nbsp; Paid <b>${money(rows.filter((t) => t.kind === 'DEBIT').reduce((s, t) => s + t.amount, 0))}</b>
&nbsp;·&nbsp; Balance <b>${money(running)}</b></div>
<table><tr><th>Date</th><th>Particulars</th><th class="right">Udhaar (Cr)</th><th class="right">Paid (Dr)</th><th class="right">Balance</th></tr>${lines}</table>
<p style="font-size:11px;color:#888;margin-top:18px">Generated ${new Date().toISOString().slice(0, 10)} · Khata Clone demo</p>
</body></html>`;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
});

router.delete('/:id', requirePerm('edit'), (req, res) => {
  const r = db.prepare('UPDATE customers SET deleted_at=? WHERE id=? AND user_id=? AND deleted_at IS NULL').run(Date.now(), req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'customer_delete', `id=${req.params.id}`);
  res.json({ ok: true });
});

module.exports = router;
