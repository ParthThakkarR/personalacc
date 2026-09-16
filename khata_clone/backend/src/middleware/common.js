'use strict';
const { authRequired } = require('../utils/jwt');

function requireAuth(req, res, next) {
  return authRequired(req, res, next);
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  console.error(err);
  const status = err.status || 500;
  res.status(status).json({ error: err.code || 'internal_error', message: err.message || 'Something went wrong' });
}

function validate(schema, source = 'body') {
  return (req, res, next) => {
    const parsed = schema.safeParse(req[source]);
    if (!parsed.success) {
      return res.status(400).json({ error: 'validation_error', details: parsed.error.flatten() });
    }
    req[source] = parsed.data;
    return next();
  };
}

module.exports = { requireAuth, errorHandler, validate };
