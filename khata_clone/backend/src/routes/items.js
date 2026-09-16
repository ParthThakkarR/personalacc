'use strict';
/**
 * Inventory item master (cf. APK inventory module, 142 classes). Items power
 * fast bill creation: name/unit/rate/stock + GST slab. Soft-delete → recycle.
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
  const q = (req.query.q || '').toString().trim();
  let rows;
  if (q) {
    rows = db
      .prepare('SELECT * FROM items WHERE user_id=? AND deleted_at IS NULL AND name LIKE ? ORDER BY name LIMIT 500')
      .all(req.book.ownerId, `%${q}%`);
  } else {
    rows = db
      .prepare('SELECT * FROM items WHERE user_id=? AND deleted_at IS NULL ORDER BY name LIMIT 500')
      .all(req.book.ownerId);
  }
  const totalStock = rows.reduce((s, r) => s + r.stock * r.rate, 0);
  res.json({ items: rows, total_stock_value: totalStock });
});

router.post(
  '/',
  requirePerm('add'),
  validate(
    z.object({
      name: z.string().min(1).max(80),
      unit: z.string().max(10).default('PCS'),
      rate: z.number().int().min(0).max(100000000),
      stock: z.number().min(0).max(100000000).default(0),
      gst_slab_index: z.number().int().min(0).max(20).default(1),
    })
  ),
  (req, res) => {
    const r = db
      .prepare('INSERT INTO items (user_id, name, unit, rate, stock, gst_slab_index) VALUES (?, ?, ?, ?, ?, ?)')
      .run(req.book.ownerId, req.body.name, req.body.unit, req.body.rate, req.body.stock, req.body.gst_slab_index);
    logStaffWrite(req, 'item_add', req.body.name);
    res.status(201).json({ id: Number(r.lastInsertRowid) });
  }
);

router.patch(
  '/:id',
  requirePerm('edit'),
  validate(
    z.object({
      name: z.string().min(1).max(80).optional(),
      unit: z.string().max(10).optional(),
      rate: z.number().int().min(0).max(100000000).optional(),
      stock: z.number().min(0).max(100000000).optional(),
      gst_slab_index: z.number().int().min(0).max(20).optional(),
    })
  ),
  (req, res) => {
    const item = db.prepare('SELECT * FROM items WHERE id=? AND user_id=? AND deleted_at IS NULL').get(req.params.id, req.book.ownerId);
    if (!item) return res.status(404).json({ error: 'not_found' });
    const next = { ...item, ...req.body };
    db.prepare('UPDATE items SET name=?, unit=?, rate=?, stock=?, gst_slab_index=? WHERE id=?')
      .run(next.name, next.unit, next.rate, next.stock, next.gst_slab_index, item.id);
    logStaffWrite(req, 'item_edit', `id=${item.id}`);
    res.json({ ok: true });
  }
);

router.delete('/:id', requirePerm('edit'), (req, res) => {
  const r = db.prepare('UPDATE items SET deleted_at=? WHERE id=? AND user_id=? AND deleted_at IS NULL').run(Date.now(), req.params.id, req.book.ownerId);
  if (r.changes === 0) return res.status(404).json({ error: 'not_found' });
  logStaffWrite(req, 'item_delete', `id=${req.params.id}`);
  res.json({ ok: true });
});

module.exports = router;