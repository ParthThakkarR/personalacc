'use strict';
const express = require('express');
const { openDb, migrate } = require('../db');
const { decryptCell } = require('../utils/cipher');
const { requireAuth, resolveBook, requirePerm } = require('./_auth');

/** Customer names arrive as ciphertext (see customers.js PII boundary) —
 * decrypt before sending to the app. Fail closed per-row, never crash. */
function decName(row, field = 'name') {
  if (row && typeof row[field] === 'string') {
    try { row[field] = decryptCell(row[field]); } catch (_) { row[field] = '🔒'; }
  }
  return row;
}

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook);

// Day-wise + customer-wise report (mirrors fragment_day_wise_report / customer_report layouts seen in APK)
router.get('/summary', requirePerm('totals'), (req, res) => {
  const perDay = db
    .prepare(
      `SELECT txn_date AS date,
        SUM(CASE WHEN kind='CREDIT' THEN amount ELSE 0 END) AS given,
        SUM(CASE WHEN kind='DEBIT' THEN amount ELSE 0 END) AS received
       FROM transactions WHERE user_id=? AND deleted_at IS NULL GROUP BY txn_date ORDER BY txn_date DESC LIMIT 60`
    )
    .all(req.book.ownerId);
  const perCustomer = db
    .prepare(
      `SELECT c.id, c.name, COALESCE(SUM(CASE WHEN t.kind='CREDIT' THEN t.amount ELSE -t.amount END),0)+c.opening_balance AS balance
       FROM customers c LEFT JOIN transactions t ON t.customer_id=c.id AND t.deleted_at IS NULL
       WHERE c.user_id=? AND c.deleted_at IS NULL GROUP BY c.id ORDER BY balance DESC LIMIT 200`
    )
    .all(req.book.ownerId);
  const cash = db
    .prepare(`SELECT COALESCE(SUM(CASE WHEN kind='CREDIT' THEN amount ELSE 0 END),0) AS credit, COALESCE(SUM(CASE WHEN kind='DEBIT' THEN amount ELSE 0 END),0) AS debit FROM transactions WHERE user_id=? AND deleted_at IS NULL`)
    .get(req.book.ownerId);
  res.json({ perDay, perCustomer: perCustomer.map((r) => decName(r)), cashbook: cash });
});

// Owner dashboard (mirrors userdashboard module): headline balances,
// 6-month trend, top dues, month expense/cash summary.
router.get('/dashboard', requirePerm('totals'), (req, res) => {
  const oid = req.book.ownerId;
  const cash = db
    .prepare("SELECT COALESCE(SUM(CASE WHEN kind='CREDIT' THEN amount ELSE 0 END),0) AS credit, COALESCE(SUM(CASE WHEN kind='DEBIT' THEN amount ELSE 0 END),0) AS debit FROM transactions WHERE user_id=? AND deleted_at IS NULL")
    .get(oid);
  const receivable = Math.max(0, cash.credit - cash.debit);
  const payables = db
    .prepare(`SELECT COALESCE(SUM(o),0) AS payable FROM (SELECT c.opening_balance + COALESCE(SUM(CASE WHEN t.kind='CREDIT' THEN t.amount ELSE -t.amount END),0) AS o
       FROM customers c LEFT JOIN transactions t ON t.customer_id=c.id AND t.deleted_at IS NULL
       WHERE c.user_id=? AND c.deleted_at IS NULL GROUP BY c.id HAVING o < 0)`)
    .get(oid);
  const thisMonth = db
    .prepare("SELECT SUM(CASE WHEN kind='CREDIT' THEN amount ELSE -amount END) AS net FROM transactions WHERE user_id=? AND deleted_at IS NULL AND substr(txn_date,1,7)=substr(date('now'),1,7)")
    .get(oid);
  const expenseMonth = db
    .prepare("SELECT COALESCE(SUM(amount),0) AS spent FROM expenses WHERE user_id=? AND deleted_at IS NULL AND substr(expense_date,1,7)=substr(date('now'),1,7)")
    .get(oid);
  const trend = db
    .prepare(`WITH RECURSIVE m(i) AS (SELECT 5 UNION ALL SELECT i-1 FROM m WHERE i>0)
       SELECT substr(date('now','-'||i||' months'),1,7) AS month FROM m`)
    .all();
  const trendData = trend.map((m) => {
    const row = db
      .prepare("SELECT COALESCE(SUM(CASE WHEN kind='CREDIT' THEN amount ELSE 0 END),0) AS given, COALESCE(SUM(CASE WHEN kind='DEBIT' THEN amount ELSE 0 END),0) AS received FROM transactions WHERE user_id=? AND deleted_at IS NULL AND substr(txn_date,1,7)=?")
      .get(oid, m.month);
    return { month: m.month, given: row.given, received: row.received };
  });
  const topDues = db
    .prepare(`SELECT c.id, c.name, c.opening_balance + COALESCE(SUM(CASE WHEN t.kind='CREDIT' THEN t.amount ELSE -t.amount END),0) AS balance
       FROM customers c LEFT JOIN transactions t ON t.customer_id=c.id AND t.deleted_at IS NULL
       WHERE c.user_id=? AND c.deleted_at IS NULL GROUP BY c.id HAVING balance > 0 ORDER BY balance DESC LIMIT 5`)
    .all(oid)
    .map((r) => decName(r));
  res.json({
    receivable,
    payable: Math.abs(payables.payable),
    this_month_net: thisMonth.net || 0,
    this_month_expense: expenseMonth.spent,
    customer_count: db.prepare('SELECT COUNT(*) c FROM customers WHERE user_id=? AND deleted_at IS NULL').get(oid).c,
    trend: trendData,
    top_dues: topDues,
  });
});

// Cash register / day book (Phase 9): one day's ledger, kaccha to pakka.
// date=YYYY-MM-DD optional → today. Also returns recent dates for the pager.
router.get('/daybook', requirePerm('view'), (req, res) => {
  const date = /^\d{4}-\d{2}-\d{2}$/.test(req.query.date || '') ? req.query.date : db.prepare("SELECT date('now') d").get().d;
  const txns = db
    .prepare(
      `SELECT t.id, t.kind, t.amount, t.note, t.txn_date, t.created_at, c.id AS customer_id, c.name AS customer_name
       FROM transactions t JOIN customers c ON c.id=t.customer_id
       WHERE t.user_id=? AND t.deleted_at IS NULL AND t.txn_date=? ORDER BY t.id DESC`
    )
    .all(req.book.ownerId, date)
    .map((t) => decName(t, 'customer_name'));
  const totals = db
    .prepare(
      `SELECT COALESCE(SUM(CASE WHEN kind='CREDIT' THEN amount ELSE 0 END),0) AS given,
              COALESCE(SUM(CASE WHEN kind='DEBIT' THEN amount ELSE 0 END),0) AS received
       FROM transactions WHERE user_id=? AND deleted_at IS NULL AND txn_date=?`
    )
    .get(req.book.ownerId, date);
  const days = db
    .prepare('SELECT DISTINCT txn_date FROM transactions WHERE user_id=? AND deleted_at IS NULL ORDER BY txn_date DESC LIMIT 90')
    .all(req.book.ownerId)
    .map((r) => r.txn_date);
  res.json({
    date,
    transactions: txns,
    given: totals.given,
    received: totals.received,
    net: totals.given - totals.received,
    days,
  });
});

// CSV export for viva/demo (open in Excel) — party ledger
router.get('/ledger.csv', requirePerm('totals'), (req, res) => {
  const rows = db
    .prepare(
      `SELECT t.txn_date, c.name AS customer, t.kind, t.amount, t.note FROM transactions t JOIN customers c ON c.id=t.customer_id WHERE t.user_id=? AND t.deleted_at IS NULL AND c.deleted_at IS NULL ORDER BY t.txn_date, t.id`
    )
    .all(req.book.ownerId);
  rows.forEach((r) => decName(r, 'customer'));
  const esc = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = ['date,customer,kind,amount,note', ...rows.map((r) => [r.txn_date, esc(r.customer), r.kind, r.amount, esc(r.note)].join(','))].join('\n');
  res.setHeader('Content-Type', 'text/csv');
  res.send(csv);
});

module.exports = router;
