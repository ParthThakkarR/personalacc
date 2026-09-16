'use strict';
/**
 * Staff book-access (mirrors researched W8: stafftab + accesscontrol).
 * Roles: viewer (view) < entry (view, add) < manager (view, add, edit, totals).
 * Owners bypass everything. Staff act on an owner's book by sending
 * X-Book-Owner-Id; req.book = { ownerId, role, perms, isOwner }.
 */
const { openDb, migrate } = require('../db');

const ROLE_PERMS = {
  viewer: ['view'],
  entry: ['view', 'add'],
  manager: ['view', 'add', 'edit', 'totals'],
};
const OWNER_PERMS = ['view', 'add', 'edit', 'totals', 'manage_staff'];
const ROLES = Object.keys(ROLE_PERMS);

function db() {
  return migrate(openDb());
}

function resolveBook(req, res, next) {
  const header = (req.headers['x-book-owner-id'] || '').toString().trim();
  if (!header) {
    req.book = { ownerId: req.user.id, role: 'owner', perms: OWNER_PERMS, isOwner: true };
    return next();
  }
  const ownerId = Number(header);
  if (!Number.isInteger(ownerId) || ownerId <= 0) {
    return res.status(400).json({ error: 'invalid_book_owner' });
  }
  if (ownerId === req.user.id) {
    req.book = { ownerId: req.user.id, role: 'owner', perms: OWNER_PERMS, isOwner: true };
    return next();
  }
  const row = db()
    .prepare("SELECT * FROM staff_members WHERE owner_id=? AND member_user_id=? AND status='active'")
    .get(ownerId, req.user.id);
  if (!row) return res.status(403).json({ error: 'no_book_access' });
  req.book = { ownerId, role: row.role, perms: ROLE_PERMS[row.role] || [], isOwner: false };
  return next();
}

function requirePerm(perm) {
  return (req, res, next) => {
    if (!req.book || !req.book.perms.includes(perm)) {
      return res.status(403).json({ error: 'forbidden', required: perm });
    }
    return next();
  };
}

/** Staff management endpoints: owner on their OWN book only. */
function requireOwner(req, res, next) {
  if (!req.book || !req.book.isOwner) {
    return res.status(403).json({ error: 'owner_only' });
  }
  return next();
}

/** Owner alert log for staff writes (cf. "alerts when staff makes an entry"). */
function logStaffWrite(req, action, detail) {
  if (req.book && !req.book.isOwner) {
    try {
      db()
        .prepare('INSERT INTO staff_audit (owner_id, actor_user_id, action, detail, created_at) VALUES (?, ?, ?, ?, ?)')
        .run(req.book.ownerId, req.user.id, action, detail || '', Date.now());
    } catch (_) {}
  }
}

module.exports = { ROLE_PERMS, OWNER_PERMS, ROLES, resolveBook, requirePerm, requireOwner, logStaffWrite };
