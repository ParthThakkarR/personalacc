'use strict';
/**
 * Phase 8-10 engagement + business identity (clean-room):
 *  - GET /referral          → my invite code + reward stats
 *  - POST /referral/claim   → apply a friend's code (one-time, double reward)
 *  - GET /card              → business card data + vCard QR payload
 *  - GET /preferences       → txn_sms toggle + other per-user prefs
 *  - POST /preferences      → save preferences
 * The routes are user-scoped (like "My business" in the real app) rather than
 * book-scoped: staff members switch khata books, but referral rewards and the
 * business card belong to the phone account that is logged in.
 */
const express = require('express');
const { z } = require('zod');
const { openDb, migrate } = require('../db');
const { validate } = require('../middleware/common');
const auth = require('./_auth').requireAuth;

const router = express.Router();
const db = migrate(openDb());

const REF_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const BONUS_PER_FRIEND = 100;

router.use(auth);

function myUser(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

router.get('/referral', (req, res) => {
  const user = myUser(req.user.id);
  const friends = db
    .prepare('SELECT COUNT(*) AS c, COALESCE(SUM(bonus), 0) AS b FROM referrals WHERE referrer_id = ?')
    .get(req.user.id);
  res.json({
    code: user.referral_code,
    bonus_per_friend: BONUS_PER_FRIEND,
    friends: Number(friends.c),
    earned: Number(friends.b),
  });
});

router.post(
  '/referral/claim',
  validate(z.object({ code: z.string().min(4).max(16).trim().toUpperCase() })),
  (req, res) => {
    const code = req.body.code.toUpperCase();
    const referrer = db.prepare('SELECT * FROM users WHERE referral_code = ?').get(code);
    if (!referrer) return res.status(404).json({ error: 'invalid_code' });
    if (referrer.id === req.user.id) return res.status(400).json({ error: 'own_code' });
    const existing = db.prepare('SELECT id FROM referrals WHERE referee_user_id = ?').get(req.user.id);
    if (existing) return res.status(409).json({ error: 'already_referred' });
    db.prepare('INSERT INTO referrals (referrer_id, referee_user_id, bonus, created_at) VALUES (?, ?, ?, ?)').run(
      referrer.id,
      req.user.id,
      BONUS_PER_FRIEND,
      Date.now()
    );
    res.json({ ok: true, bonus: BONUS_PER_FRIEND });
  }
);

router.get('/card', (req, res) => {
  const user = myUser(req.user.id);
  const name = user.name || 'Shop Owner';
  const business = user.business_name || user.name || 'My Store';
  const category = user.business_category || '';
  const qr_payload = [
    'BEGIN:VCARD',
    'VERSION:3.0',
    `FN:${name}`,
    `ORG:${business}`,
    ...(category ? [`TITLE:${category}`] : []),
    `TEL:${user.phone}`,
    'END:VCARD',
  ]
    .map((l) => l.replace(/\r?\n/g, ' '))
    .join('\n');
  res.json({
    name,
    business_name: business,
    business_category: category,
    phone: user.phone,
    qr_payload,
  });
});

router.get('/preferences', (req, res) => {
  const user = myUser(req.user.id);
  res.json({ txn_sms: Number(user.txn_sms_enabled) === 1, referral_code: user.referral_code });
});

router.post(
  '/preferences',
  validate(z.object({ txn_sms: z.boolean().optional() })),
  (req, res) => {
    db.prepare('UPDATE users SET txn_sms_enabled = ? WHERE id = ?').run(req.body.txn_sms ? 1 : 0, req.user.id);
    res.json({ ok: true, txn_sms: !!req.body.txn_sms });
  }
);

module.exports = router;