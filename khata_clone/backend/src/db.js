'use strict';
/**
 * SQLite (Node built-in node:sqlite) + schema + seed.
 * Clean-room schema inspired by APK analysis:
 *  - users (OTP auth; PIN/AppLock like AppLockActivity)
 *  - otp_codes (hashed OTP + resend cooldown + attempt limit, cf. login_waiting_for_code)
 *  - refresh_tokens (opaque, hashed, rotatable — cf. KbAuthenticationSession/refreshToken)
 *  - customers (khata parties), transactions (CREDIT=udhaar given / DEBIT=received)
 *  - bills + bill_items (GST slabs from assets/gst_slabs.json)
 */
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'khata.db');

function openDb() {
  fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
  const db = new DatabaseSync(DB_PATH);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
  return db;
}

function columnNames(db, table) {
  try {
    return db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
  } catch {
    return [];
  }
}

function migrate(db = openDb()) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL DEFAULT 'Shop Owner',
      business_name TEXT DEFAULT '',
      business_category TEXT DEFAULT '',
      pin_hash TEXT,
      pin_fail_count INTEGER NOT NULL DEFAULT 0,
      pin_locked_until INTEGER NOT NULL DEFAULT 0,
      password_hash TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      phone TEXT DEFAULT '',
      address TEXT DEFAULT '',
      opening_balance INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('CREDIT','DEBIT')),
      amount INTEGER NOT NULL CHECK (amount > 0),
      note TEXT DEFAULT '',
      txn_date TEXT NOT NULL DEFAULT (date('now')),
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_txn_user_customer ON transactions(user_id, customer_id);
    CREATE TABLE IF NOT EXISTS bills (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
      invoice_no TEXT NOT NULL,
      invoice_date TEXT NOT NULL DEFAULT (date('now')),
      gst_slab_index INTEGER NOT NULL DEFAULT 1,
      discount INTEGER NOT NULL DEFAULT 0,
      total INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(user_id, invoice_no)
    );
    CREATE TABLE IF NOT EXISTS bill_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      qty REAL NOT NULL DEFAULT 1,
      unit TEXT NOT NULL DEFAULT 'PCS',
      rate INTEGER NOT NULL DEFAULT 0,
      amount INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token_hash TEXT NOT NULL UNIQUE,
      expires_at INTEGER NOT NULL,
      revoked_at INTEGER,
      replaced_by INTEGER REFERENCES refresh_tokens(id) ON DELETE SET NULL,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_tokens(user_id);
    CREATE TABLE IF NOT EXISTS staff_members (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      member_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      phone TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('manager','entry','viewer')),
      status TEXT NOT NULL DEFAULT 'invited' CHECK (status IN ('invited','active','revoked')),
      created_at INTEGER NOT NULL,
      UNIQUE(owner_id, phone)
    );
    CREATE TABLE IF NOT EXISTS staff_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      actor_user_id INTEGER NOT NULL,
      action TEXT NOT NULL,
      detail TEXT DEFAULT '',
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_staff_member ON staff_members(member_user_id, status);
    CREATE TABLE IF NOT EXISTS collection_links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      amount INTEGER NOT NULL CHECK (amount > 0),
      ref TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','paid','expired')),
      created_at INTEGER NOT NULL,
      paid_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS reminders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      channel TEXT NOT NULL CHECK (channel IN ('sms','whatsapp','call')),
      message TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent')),
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      amount INTEGER NOT NULL CHECK (amount > 0),
      note TEXT DEFAULT '',
      category TEXT NOT NULL DEFAULT 'General',
      expense_date TEXT NOT NULL DEFAULT (date('now')),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      deleted_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      unit TEXT NOT NULL DEFAULT 'PCS',
      rate INTEGER NOT NULL DEFAULT 0,
      stock REAL NOT NULL DEFAULT 0,
      gst_slab_index INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      deleted_at INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_items_user ON items(user_id);
    CREATE TABLE IF NOT EXISTS ledger_attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      mime TEXT NOT NULL DEFAULT 'image/jpeg',
      data TEXT NOT NULL,
      caption TEXT DEFAULT '',
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_attachments_txn ON ledger_attachments(transaction_id);
    CREATE TABLE IF NOT EXISTS referrals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      referrer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      referee_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      bonus INTEGER NOT NULL DEFAULT 100,
      created_at INTEGER NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_referrals_referee ON referrals(referee_user_id);
  `);

  // Idempotent upgrades for DBs created by earlier versions:
  for (const col of ['pin_fail_count', 'pin_locked_until']) {
    if (!columnNames(db, 'users').includes(col)) {
      db.exec(`ALTER TABLE users ADD COLUMN ${col} INTEGER NOT NULL DEFAULT 0`);
    }
  }
  // Password login (AUTH_MODE=password). Idempotent upgrade for DBs
  // created before password auth shipped.
  if (!columnNames(db, 'users').includes('password_hash')) {
    db.exec('ALTER TABLE users ADD COLUMN password_hash TEXT');
  }
  // One-time backfill: LAN-demo account created before password auth shipped.
  // Prod sets SEED_DEMO=0 (that phone must not exist there — see deploy doc §6).
  try {
    const demo = db.prepare("SELECT id FROM users WHERE phone='9999999999' AND password_hash IS NULL").get();
    if (demo) {
      const bcrypt = require('bcryptjs');
      db.prepare('UPDATE users SET password_hash=? WHERE id=?').run(bcrypt.hashSync('demo1234', 8), demo.id);
    }
  } catch { /* users table edge cases: seed will handle fresh DBs */ }
  // Refer & earn: personal invite code per account.
  if (!columnNames(db, 'users').includes('referral_code')) {
    db.exec('ALTER TABLE users ADD COLUMN referral_code TEXT');
  }
  // Transaction SMS preference (txn_sms toggle, cf. Phase 9 cash register).
  if (!columnNames(db, 'users').includes('txn_sms_enabled')) {
    db.exec('ALTER TABLE users ADD COLUMN txn_sms_enabled INTEGER NOT NULL DEFAULT 0');
  }
  // Backfill codes for accounts created before the referral feature shipped.
  db.prepare("UPDATE users SET referral_code = 'KB' || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', ((id * 37) % 31) + 1, 4) || substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', ((id * 97) % 31) + 1, 4) WHERE referral_code IS NULL OR referral_code = ''").run();
  // Soft-delete (recycle bin, cf. recyclebin/deletekhata modules).
  for (const table of ['customers', 'transactions']) {
    if (!columnNames(db, table).includes('deleted_at')) {
      db.exec(`ALTER TABLE ${table} ADD COLUMN deleted_at INTEGER`);
    }
  }
  // Bills can reference inventory items (item_id on bill_items, cf. inventory module).
  if (!columnNames(db, 'bill_items').includes('item_id')) {
    db.exec('ALTER TABLE bill_items ADD COLUMN item_id INTEGER');
  }
  // OTP table v2: hashed code + cooldown + attempts. Rebuild if old schema seen.
  const otpCols = columnNames(db, 'otp_codes');
  if (otpCols.length > 0 && !otpCols.includes('code_hash')) {
    db.exec('DROP TABLE otp_codes');
  }
  db.exec(`
    CREATE TABLE IF NOT EXISTS otp_codes (
      phone TEXT PRIMARY KEY,
      code_hash TEXT NOT NULL,
      expires_at INTEGER NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      resend_after INTEGER NOT NULL DEFAULT 0,
      request_count INTEGER NOT NULL DEFAULT 0,
      window_start INTEGER NOT NULL DEFAULT 0
    );
  `);
  return db;
}

function seedIfEmpty(db = migrate()) {
  const row = db.prepare('SELECT COUNT(*) AS c FROM users').get();
  if (row && row.c > 0) return { seeded: false };
  const bcrypt = require('bcryptjs');
  const pinHash = bcrypt.hashSync('1234', 8);
  // LAN-demo password (documented in README). Production sets SEED_DEMO=0,
  // so this account — and its known password — never exists on a server.
  const demoPassHash = bcrypt.hashSync('demo1234', 8);
  const ins = db.prepare(
    'INSERT INTO users (phone, name, business_name, business_category, pin_hash, password_hash) VALUES (?, ?, ?, ?, ?, ?)'
  );
  const demo = ins.run('9999999999', 'Demo Owner', 'Demo General Store', 'Grocery Store', pinHash, demoPassHash);
  const userId = Number(demo.lastInsertRowid);
  const addC = db.prepare(
    'INSERT INTO customers (user_id, name, phone, address, opening_balance) VALUES (?, ?, ?, ?, ?)'
  );
  const c1 = addC.run(userId, 'Ramesh Kumar', '9811111111', 'Main Market', 0);
  const c2 = addC.run(userId, 'Suresh Traders', '9822222222', 'Grain Mandi', 5000);
  const addT = db.prepare(
    "INSERT INTO transactions (user_id, customer_id, kind, amount, note, txn_date) VALUES (?, ?, ?, ?, ?, date('now'))"
  );
  addT.run(userId, Number(c1.lastInsertRowid), 'CREDIT', 1500, 'Udhaar - rice bag');
  addT.run(userId, Number(c1.lastInsertRowid), 'DEBIT', 500, 'Cash received');
  addT.run(userId, Number(c2.lastInsertRowid), 'CREDIT', 8000, 'Opening stock');
  const addItem = db.prepare(
    'INSERT INTO items (user_id, name, unit, rate, stock, gst_slab_index) VALUES (?, ?, ?, ?, ?, ?)'
  );
  addItem.run(userId, 'Atta 5kg', 'PCS', 120, 40, 2);
  addItem.run(userId, 'Basmati Rice 1kg', 'KG', 95, 80, 2);
  addItem.run(userId, 'Sugar 1kg', 'KG', 45, 120, 1);
  const addExp = db.prepare(
    "INSERT INTO expenses (user_id, amount, note, category, expense_date) VALUES (?, ?, ?, ?, date('now'))"
  );
  addExp.run(userId, 5000, 'Shop rent', 'Rent');
  addExp.run(userId, 1250, 'Electricity bill', 'Utilities');
  return { seeded: true, userId };
}

if (require.main === module) {
  const db = migrate();
  const r = seedIfEmpty(db);
  console.log('DB ready at', DB_PATH, r);
  db.close();
}

module.exports = { openDb, migrate, seedIfEmpty, DB_PATH };
