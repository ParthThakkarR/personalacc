'use strict';
const { requireAuth } = require('../middleware/common');
const { resolveBook, requirePerm, requireOwner } = require('../middleware/staff');
module.exports = { requireAuth, resolveBook, requirePerm, requireOwner };
