'use strict';
require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const { migrate, openDb, seedIfEmpty } = require('./db');
const { errorHandler } = require('./middleware/common');

const app = express();
app.use(helmet());
// Native mobile apps send no Origin header; browsers must match the allow-list.
// Set ALLOWED_ORIGINS=https://your-docs-site (comma-separated) in production.
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
app.use(
  cors({
    origin: (origin, cb) => {
      if (!origin) return cb(null, true);
      if (ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
      return cb(new Error('cors_not_allowed'));
    },
  })
);
app.use(express.json({ limit: '1mb' }));
app.use(morgan('dev'));
app.use(rateLimit({ windowMs: 60 * 1000, max: 300 }));

// Stricter bucket for OTP endpoints (mirrors server-driven resend/attempt limits)
// NOTE: OTP routes are parked (see routes/auth.js seam); limits stay so the
// seam revives protected. Password login/register get the same treatment.
app.use('/auth/request-otp', rateLimit({ windowMs: 15 * 60 * 1000, max: 30 }));
app.use('/auth/verify-otp', rateLimit({ windowMs: 15 * 60 * 1000, max: 60 }));
app.use('/auth/login', rateLimit({ windowMs: 15 * 60 * 1000, max: 60 }));
app.use('/auth/register', rateLimit({ windowMs: 60 * 60 * 1000, max: 20 }));

const db = migrate(openDb());
if (process.env.SEED_DEMO !== '0') seedIfEmpty(db);

app.get('/health', (req, res) => res.json({ ok: true, service: 'khata-clone-backend', time: new Date().toISOString() }));
app.use('/auth', require('./routes/auth'));
app.use('/customers', require('./routes/customers'));
app.use('/transactions', require('./routes/transactions'));
app.use('/bills', require('./routes/bills'));
app.use('/reports', require('./routes/reports'));
app.use('/staff', require('./routes/staff'));
app.use('/collections', require('./routes/collections'));
app.use('/recycle', require('./routes/recycle'));
app.use('/backup', require('./routes/backup'));
app.use('/expenses', require('./routes/expenses'));
app.use('/items', require('./routes/items'));
app.use('/business', require('./routes/business'));
app.use(errorHandler);

const PORT = Number(process.env.PORT || 8080);
if (process.env.NODE_ENV === 'production' && (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32)) {
  console.error('Refusing to start: set a strong JWT_SECRET (>=32 chars) in production.');
  process.exit(1);
}
if (require.main === module) {
  app.listen(PORT, () => console.log(`khata-clone backend on http://localhost:${PORT}`));
}
module.exports = app;
