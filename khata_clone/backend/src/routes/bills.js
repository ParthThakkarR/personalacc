'use strict';
/**
 * Bills with GST slab math. Slab table mirrors assets/gst_slabs.json observed in APK.
 * total = sum(items) + GST% - discount. GST% derived from slab index's igst.
 */
const express = require('express');
const { z } = require('zod');
const fs = require('node:fs');
const path = require('node:path');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const { logStaffWrite } = require('../middleware/staff');
const { render } = require('../utils/invoice');
const { decryptCell } = require('../utils/cipher');
const { requireAuth, resolveBook, requirePerm } = require('./_auth');

const router = express.Router();
const db = migrate(openDb());
router.use(requireAuth, resolveBook);

function loadSlabs() {
  try {
    const p = path.join(__dirname, '..', '..', 'data', 'seed', 'gst_slabs.json');
    const j = JSON.parse(fs.readFileSync(p, 'utf8'));
    return j.gstSlabs;
  } catch {
    return [{ igst: 0 }, { igst: 0 }, { igst: 5 }, { igst: 12 }, { igst: 18 }, { igst: 28 }];
  }
}

router.get('/meta', requirePerm('view'), (req, res) => {
  res.json({ slabs: loadSlabs() });
});

router.post(
  '/',
  requirePerm('add'),
  validate(
    z.object({
      customer_id: z.number().int().positive().nullable().optional(),
      invoice_no: z.string().min(1).max(40),
      invoice_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      gst_slab_index: z.number().int().min(0).max(20).default(1),
      discount: z.number().int().min(0).default(0),
      items: z.array(z.object({ name: z.string().min(1).max(100), qty: z.number().positive().max(100000), unit: z.string().max(10).default('PCS'), rate: z.number().int().min(0), item_id: z.number().int().positive().nullable().optional() })).min(1).max(100),
    })
  ),
  (req, res) => {
    const slabs = loadSlabs();
    const slab = slabs[req.body.gst_slab_index] || { igst: 0 };
    const igst = Number(slab.igst || 0);
    const subtotal = req.body.items.reduce((s, it) => s + Math.round(it.qty * it.rate), 0);
    const gstAmt = Math.round((subtotal * igst) / 100);
    const total = Math.max(0, subtotal + gstAmt - req.body.discount);
    // Validate referenced inventory BEFORE writing anything: previously an
    // unknown item_id returned 400 after the bill row was already inserted,
    // leaving an orphan bill (+ partial stock deductions). Fail closed first.
    for (const it of req.body.items) {
      if (it.item_id != null) {
        const item = db.prepare('SELECT id FROM items WHERE id=? AND user_id=? AND deleted_at IS NULL').get(it.item_id, req.book.ownerId);
        if (!item) return res.status(400).json({ error: 'unknown_item' });
      }
    }
    db.exec('BEGIN');
    try {
      const r = db
        .prepare('INSERT INTO bills (user_id, customer_id, invoice_no, invoice_date, gst_slab_index, discount, total) VALUES (?, ?, ?, COALESCE(?, date(\'now\')), ?, ?, ?)')
        .run(req.book.ownerId, req.body.customer_id || null, req.body.invoice_no, req.body.invoice_date || null, req.body.gst_slab_index, req.body.discount, total);
      const billId = Number(r.lastInsertRowid);
      const ins = db.prepare('INSERT INTO bill_items (bill_id, item_id, name, qty, unit, rate, amount) VALUES (?, ?, ?, ?, ?, ?, ?)');
      for (const it of req.body.items) {
        ins.run(billId, it.item_id || null, it.name, it.qty, it.unit, it.rate, Math.round(it.qty * it.rate));
        if (it.item_id != null) {
          db.prepare('UPDATE items SET stock = MAX(0, stock - ?) WHERE id=?').run(it.qty, it.item_id);
        }
      }
      db.exec('COMMIT');
      logStaffWrite(req, 'bill_add', `${req.body.invoice_no} total=${total}`);
      res.status(201).json({ id: billId, subtotal, gstAmt, total });
    } catch (e) {
      try { db.exec('ROLLBACK'); } catch (_) {}
      if (String(e.message).includes('UNIQUE')) return res.status(409).json({ error: 'duplicate_invoice_no' });
      throw e;
    }
  }
);

router.get('/', requirePerm('view'), (req, res) => {
  const rows = db.prepare('SELECT * FROM bills WHERE user_id=? ORDER BY id DESC LIMIT 200').all(req.book.ownerId);
  res.json({ bills: rows });
});

router.get('/:id', requirePerm('view'), (req, res) => {
  const b = db.prepare('SELECT * FROM bills WHERE id=? AND user_id=?').get(req.params.id, req.book.ownerId);
  if (!b) return res.status(404).json({ error: 'not_found' });
  const items = db.prepare('SELECT * FROM bill_items WHERE bill_id=?').all(b.id);
  res.json({ bill: b, items });
});

// Standalone invoice HTML (offline-capable). ?template=standard|thermal
router.get('/:id/html', requirePerm('view'), (req, res) => {
  const b = db.prepare('SELECT * FROM bills WHERE id=? AND user_id=?').get(req.params.id, req.book.ownerId);
  if (!b) return res.status(404).json({ error: 'not_found' });
  const items = db.prepare('SELECT * FROM bill_items WHERE bill_id=?').all(b.id);
  const owner = db.prepare('SELECT business_name, business_category FROM users WHERE id=?').get(req.book.ownerId) || {};
  const customer = b.customer_id ? db.prepare('SELECT name, phone FROM customers WHERE id=?').get(b.customer_id) : null;
  if (customer) {
    // Customer PII is ciphertext at rest — decrypt for the printed invoice.
    for (const f of ['name', 'phone']) {
      try { customer[f] = decryptCell(customer[f]); } catch (_) { customer[f] = '🔒'; }
    }
  }
  const template = req.query.template === 'thermal' ? 'thermal' : 'standard';
  const opts = req.query.seal === '1' ? { seal: true } : {};
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(
    render(
      template,
      b,
      items,
      { name: owner.business_name || 'My Shop', category: owner.business_category || '' },
      customer,
      opts
    )
  );
});

module.exports = router;
