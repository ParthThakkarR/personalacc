'use strict';
/**
 * OTP request/verify policy (mirrors observed app behavior):
 *  - 6-digit code, 5-minute TTL
 *  - resend cooldown 60 s  ("Resend OTP in %1$s seconds")
 *  - max 5 OTP requests per 15-min window per phone
 *  - max 5 verify attempts → code invalidated
 * Codes are bcrypt-hashed at rest. The OtpSender seam is where a real
 * SMS/Truecaller/Firebase provider plugs in; the demo sender is used when
 * ALLOW_DEMO_OTP=1 (college use, no SMS cost).
 */
const bcrypt = require('bcryptjs');

const OTP_TTL_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 5;
const WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 5;

function now() {
  return Date.now();
}

function issueCode() {
  if (process.env.OTP_FIXED) return process.env.OTP_FIXED;
  return String(Math.floor(100000 + Math.random() * 900000));
}

/** @returns {{ok:true,resend_after_s:number,demo_code?:string}|{error:string,resend_after_s?:number}} */
function requestOtp(db, phone) {
  const t = now();
  const row = db.prepare('SELECT * FROM otp_codes WHERE phone = ?').get(phone);
  let count = 1;
  let windowStart = t;
  if (row) {
    if (t - Number(row.window_start) < WINDOW_MS) {
      count = Number(row.request_count) + 1;
      windowStart = Number(row.window_start);
    }
    if (count > MAX_REQUESTS_PER_WINDOW + 1) {
      return { error: 'too_many_requests' };
    }
    if (t < Number(row.resend_after)) {
      return {
        error: 'resend_cooldown',
        resend_after_s: Math.ceil((Number(row.resend_after) - t) / 1000),
      };
    }
  }
  const code = issueCode();
  const hash = bcrypt.hashSync(code, 8);
  db.prepare(
    `INSERT INTO otp_codes (phone, code_hash, expires_at, attempts, resend_after, request_count, window_start)
     VALUES (?, ?, ?, 0, ?, ?, ?)
     ON CONFLICT(phone) DO UPDATE SET code_hash=excluded.code_hash, expires_at=excluded.expires_at,
       attempts=0, resend_after=excluded.resend_after, request_count=excluded.request_count,
       window_start=excluded.window_start`
  ).run(phone, hash, t + OTP_TTL_MS, t + RESEND_COOLDOWN_MS, count, windowStart);
  const out = { ok: true, resend_after_s: Math.ceil(RESEND_COOLDOWN_MS / 1000) };
  if (process.env.ALLOW_DEMO_OTP === '1' || process.env.OTP_FIXED) out.demo_code = code;
  return out;
}

/** @returns {{ok:true}|{error:'invalid_otp'|'expired_otp'|'too_many_attempts'}} */
function verifyOtp(db, phone, code) {
  const row = db.prepare('SELECT * FROM otp_codes WHERE phone = ?').get(phone);
  if (!row) return { error: 'invalid_otp' };
  if (now() > Number(row.expires_at)) {
    db.prepare('DELETE FROM otp_codes WHERE phone = ?').run(phone);
    return { error: 'expired_otp' };
  }
  if (Number(row.attempts) >= MAX_ATTEMPTS) {
    db.prepare('DELETE FROM otp_codes WHERE phone = ?').run(phone);
    return { error: 'too_many_attempts' };
  }
  if (!bcrypt.compareSync(code, row.code_hash)) {
    const attempts = Number(row.attempts) + 1;
    if (attempts >= MAX_ATTEMPTS) {
      db.prepare('DELETE FROM otp_codes WHERE phone = ?').run(phone);
      return { error: 'too_many_attempts' };
    }
    db.prepare('UPDATE otp_codes SET attempts = ? WHERE phone = ?').run(attempts, phone);
    return { error: 'invalid_otp' };
  }
  db.prepare('DELETE FROM otp_codes WHERE phone = ?').run(phone);
  return { ok: true };
}

module.exports = { requestOtp, verifyOtp, OTP_TTL_MS, RESEND_COOLDOWN_MS, MAX_ATTEMPTS };
