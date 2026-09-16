'use strict';
/**
 * Closed-vault allow-list (private-database mode).
 *
 * The admin pre-adds the approved phone numbers via the ALLOWED_PHONES env
 * var (comma-separated 10-digit numbers, e.g. the 10 trusted users).
 *
 *  - List UNSET/EMPTY  → open registration (college LAN-demo behavior).
 *  - List SET          → /auth/register and /auth/login accept ONLY listed
 *    phones. Everyone else is rejected and can never create an account,
 *    claim a staff invite, or read a single row.
 *  - Production FAILS CLOSED: server refuses to start in NODE_ENV=production
 *    without a non-empty list (see src/index.js).
 */
const PHONE_RE = /^[0-9]{10}$/;

function allowedPhones() {
  return (process.env.ALLOWED_PHONES || '')
    .split(',')
    .map((s) => s.trim())
    .filter((p) => PHONE_RE.test(p));
}

function allowListEnforced() {
  return allowedPhones().length > 0;
}

function isPhoneAllowed(phone) {
  const list = allowedPhones();
  return list.length === 0 || list.includes(phone);
}

module.exports = { allowedPhones, allowListEnforced, isPhoneAllowed };
