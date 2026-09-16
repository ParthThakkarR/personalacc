const crypto = require('node:crypto');

// AES-256-GCM field cipher for confidential data at rest.
// Output format:  "v2:" + base64(iv(12) || authTag(16) || ciphertext)
// On any failure (wrong key, tampered value) decryptCell throws; route code
// treats PII as unrecoverable rather than leaking partial data.
//
// The key is an opaque secret, >= 32 chars, provided via CIPHER_KEY. In
// production the server refuses to start without it. For dev/demo the secret
// is derived from JWT_SECRET so the demo still runs offline.

let _devWarned = false;

function keyMaterial() {
  const provided = process.env.CIPHER_KEY;
  if (typeof provided === 'string' && provided.length >= 32) {
    return crypto.createHash('sha256').update(provided).digest();
  }
  if (process.env.NODE_ENV === 'production') {
    throw new Error('production: CIPHER_KEY (>=32 chars) is required for at-rest encryption');
  }
  if (!_devWarned) {
    console.warn('[cipher] no CIPHER_KEY set; deriving dev key from JWT_SECRET');
    _devWarned = true;
  }
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
    throw new Error('CIPHER_KEY or a strong JWT_SECRET (>=32 chars) is required');
  }
  return crypto.createHash('sha256').update(process.env.JWT_SECRET).digest();
}

/** Encrypt a string (or nullish) for storage. Returns nullish untouched. */
function encryptCell(value) {
  if (value === null || value === undefined || value === '') return value;
  const key = keyMaterial();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(String(value), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return 'v2:' + Buffer.concat([iv, tag, ct]).toString('base64');
}

/**
 * Decrypt a cell written by encryptCell. Legacy rows stored in plaintext are
 * returned untouched so pre-hardening data remains readable.
 */
function decryptCell(value) {
  if (value === null || value === undefined || value === '') return value;
  if (!String(value).startsWith('v2:')) return value;
  const key = keyMaterial();
  const raw = Buffer.from(String(value).slice(3), 'base64');
  if (raw.length < 12 + 16 + 1) {
    throw new Error('corrupt encrypted cell');
  }
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const ct = raw.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8');
}

/** Encrypt a single field on a payload object when the field is a string. */
function encField(obj, field) {
  if (obj && typeof obj[field] === 'string') obj[field] = encryptCell(obj[field]);
  return field;
}

/** Decrypt a single field on a payload object when the field looks encrypted. */
function decField(obj, field) {
  if (obj && typeof obj[field] === 'string') obj[field] = decryptCell(obj[field]);
  return field;
}

module.exports = { encryptCell, decryptCell, encField, decField, keyMaterial };
