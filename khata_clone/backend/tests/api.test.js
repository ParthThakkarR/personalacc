'use strict';
/* Integration tests for the proper login system + ledger.
 * Run: npm test — exits 0 on pass, 1 on fail.
 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const TEST_DB = path.join(__dirname, '..', 'data', 'test-khata.db');
try { fs.unlinkSync(TEST_DB); } catch {}
process.env.DB_PATH = TEST_DB;
process.env.JWT_SECRET = 'test-secret-min-32-chars-1234567890';
// OTP seam env (parked): kept so the parked OTP block revives unchanged.
process.env.OTP_FIXED = '123456';
process.env.ALLOW_DEMO_OTP = '1';
process.env.SEED_DEMO = '0';

const app = require('../src/index');

async function main() {
  const server = app.listen(0);
  await new Promise((r) => server.on('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const rq = (p, o = {}) => fetch(base + p, { ...o, headers: { 'content-type': 'application/json', ...(o.headers || {}) } });
  try {
    let r = await rq('/health');
    assert.equal(r.status, 200);
    console.log('PASS health');

    // --- Password auth: register (first device) + login (any device) ---
    r = await rq('/auth/register', { method: 'POST', body: JSON.stringify({ phone: '9876543210', password: 'testpass123' }) });
    assert.equal(r.status, 201);
    let j = await r.json();
    assert.ok(j.access && j.refresh && j.user);
    assert.equal(j.is_new, true);
    console.log('PASS register + session');
    let access = j.access;
    let refresh = j.refresh;
    const ownerId = j.user.id;
    const H = () => ({ authorization: `Bearer ${access}` });

    // duplicate register rejected
    r = await rq('/auth/register', { method: 'POST', body: JSON.stringify({ phone: '9876543210', password: 'testpass123' }) });
    assert.equal(r.status, 409);
    console.log('PASS duplicate register 409');

    // wrong password rejected (generic error: no user enumeration)
    r = await rq('/auth/login', { method: 'POST', body: JSON.stringify({ phone: '9876543210', password: 'wrongpass1' }) });
    assert.equal(r.status, 401);
    j = await r.json();
    assert.equal(j.error, 'invalid_credentials');
    console.log('PASS wrong password rejected');

    // second device: same number + password → same account (account sync)
    r = await rq('/auth/login', { method: 'POST', body: JSON.stringify({ phone: '9876543210', password: 'testpass123' }) });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.equal(j.user.id, ownerId);
    assert.equal(j.is_new, false);
    console.log('PASS login syncs same account');
    access = j.access;
    refresh = j.refresh;

    /* --- OTP block (PARKED — SMS seam, mirrors the parked routes/auth.js block).
     * Re-enable when an SMS provider is funded (and uncomment the routes).
    r = await rq('/auth/request-otp', { method: 'POST', body: JSON.stringify({ phone: '9876543210' }) });
    assert.equal(r.status, 200);
    let j = await r.json();
    assert.equal(j.demo_code, '123456');
    assert.ok(j.resend_after_s > 0);
    console.log('PASS request-otp + demo code');

    r = await rq('/auth/request-otp', { method: 'POST', body: JSON.stringify({ phone: '9876543210' }) });
    assert.equal(r.status, 429);
    j = await r.json();
    assert.equal(j.error, 'resend_cooldown');
    console.log('PASS resend cooldown 429');

    // --- verify: wrong then right ---
    r = await rq('/auth/verify-otp', { method: 'POST', body: JSON.stringify({ phone: '9876543210', code: '000000' }) });
    assert.equal(r.status, 401);
    console.log('PASS wrong OTP rejected');

    r = await rq('/auth/verify-otp', { method: 'POST', body: JSON.stringify({ phone: '9876543210', code: '123456' }) });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.ok(j.access && j.refresh && j.user);
    assert.equal(j.is_new, true);
    console.log('PASS verify-otp + session');
    --- end OTP parked block ---
    */

    // --- me + profile onboarding ---
    r = await rq('/auth/me', { headers: H() });
    assert.equal(r.status, 200);
    console.log('PASS me');

    r = await rq('/auth/profile', { method: 'PATCH', headers: H(), body: JSON.stringify({ name: 'Test Owner', business_name: 'Test Store', business_category: 'Grocery Store' }) });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.equal(j.user.profile_complete, true);
    console.log('PASS profile onboarding');

    // --- refresh rotation + reuse detection ---
    r = await rq('/auth/refresh', { method: 'POST', body: JSON.stringify({ refresh }) });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.ok(j.access && j.refresh);
    const access2 = j.access;
    console.log('PASS refresh rotation');

    r = await rq('/auth/refresh', { method: 'POST', body: JSON.stringify({ refresh }) });
    assert.equal(r.status, 401);
    j = await r.json();
    assert.equal(j.error, 'refresh_reused');
    console.log('PASS refresh reuse detected');
    access = access2;
    refresh = j.refresh || refresh;

    // get a fresh refresh for logout test later (password re-login)
    r = await rq('/auth/login', { method: 'POST', body: JSON.stringify({ phone: '9876543210', password: 'testpass123' }) });
    assert.equal(r.status, 200);
    j = await r.json();
    refresh = j.refresh;
    access = j.access;

    // --- PIN: set, wrong, right ---
    r = await rq('/auth/pin-set', { method: 'POST', headers: H(), body: JSON.stringify({ pin: '4321' }) });
    assert.equal(r.status, 200);
    console.log('PASS pin-set');

    r = await rq('/auth/pin-verify', { method: 'POST', headers: H(), body: JSON.stringify({ pin: '0000' }) });
    assert.equal(r.status, 401);
    j = await r.json();
    assert.equal(j.attempts_left, 4);
    console.log('PASS pin wrong attempt counted');

    r = await rq('/auth/pin-verify', { method: 'POST', headers: H(), body: JSON.stringify({ pin: '4321' }) });
    assert.equal(r.status, 200);
    console.log('PASS pin verify');

    // --- ledger core ---
    r = await rq('/customers', { method: 'POST', headers: H(), body: JSON.stringify({ name: 'Party A', phone: '9800000001' }) });
    assert.equal(r.status, 201);
    const { id: cid } = await r.json();
    console.log('PASS create-customer', cid);

    r = await rq('/transactions', { method: 'POST', headers: H(), body: JSON.stringify({ customer_id: cid, kind: 'CREDIT', amount: 1000, note: 'udhaar' }) });
    assert.equal(r.status, 201);
    r = await rq('/transactions', { method: 'POST', headers: H(), body: JSON.stringify({ customer_id: cid, kind: 'DEBIT', amount: 400 }) });
    assert.equal(r.status, 201);
    console.log('PASS add-transactions');

    r = await rq(`/customers/${cid}`, { headers: H() });
    assert.equal(r.status, 200);
    assert.equal((await r.json()).balance, 600);
    console.log('PASS balance=600');

    r = await rq('/bills', { method: 'POST', headers: H(), body: JSON.stringify({ invoice_no: 'INV-1', gst_slab_index: 5, items: [{ name: 'Rice 5kg', qty: 2, rate: 500 }] }) });
    assert.equal(r.status, 201);
    assert.ok((await r.json()).total > 0);
    console.log('PASS create-bill');

    r = await rq('/reports/summary', { headers: H() });
    assert.equal(r.status, 200);
    console.log('PASS reports/summary');

    // --- Phase 7: expenses ---
    r = await rq('/expenses', { method: 'POST', headers: H(), body: JSON.stringify({ amount: 800, note: 'rent', category: 'Rent' }) });
    assert.equal(r.status, 201);
    const expId = (await r.json()).id;
    r = await rq('/expenses', { headers: H() });
    j = await r.json();
    assert.equal(j.total, 800);
    assert.equal(j.expenses.length, 1);
    console.log('PASS expenses add+list');

    // --- Phase 7: inventory items ---
    r = await rq('/items', { method: 'POST', headers: H(), body: JSON.stringify({ name: 'Atta 5kg', unit: 'KG', rate: 120, stock: 20 }) });
    assert.equal(r.status, 201);
    const itemId = (await r.json()).id;
    r = await rq('/items', { headers: H() });
    j = await r.json();
    assert.ok(j.items.some((i) => i.name === 'Atta 5kg'));
    r = await rq(`/items/${itemId}`, { method: 'PATCH', headers: H(), body: JSON.stringify({ stock: 12 }) });
    assert.equal(r.status, 200);
    r = await rq('/items', { headers: H() });
    assert.equal((await r.json()).items.find((i) => i.id === itemId).stock, 12);
    // bill with item_id deducts stock
    r = await rq('/bills', { method: 'POST', headers: H(), body: JSON.stringify({ invoice_no: 'INV-ITM', items: [{ name: 'Atta 5kg', qty: 2, rate: 120, item_id: itemId }] }) });
    assert.equal(r.status, 201);
    r = await rq('/items', { headers: H() });
    assert.equal((await r.json()).items.find((i) => i.id === itemId).stock, 10);
    console.log('PASS items add/patch + bill stock deduct');

    // --- Phase 7: passbook (JSON + printable HTML) ---
    r = await rq(`/customers/${cid}/passbook`, { headers: H() });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.equal(j.summary.opening, 0);
    assert.equal(j.summary.total_credit, 1000);
    assert.equal(j.summary.total_debit, 400);
    assert.equal(j.summary.closing, 600);
    r = await rq(`/customers/${cid}/passbook.html`, { headers: H() });
    assert.equal(r.status, 200);
    assert.ok((await r.text()).includes('<table'));
    console.log('PASS passbook json + html');

    // --- Phase 7: ledger attachments ---
    r = await rq('/transactions', { method: 'POST', headers: H(), body: JSON.stringify({ customer_id: cid, kind: 'DEBIT', amount: 100, note: 'photo ref' }) });
    const attachTxn = (await r.json()).id;
    r = await rq(`/transactions/${attachTxn}/attachments`, { method: 'POST', headers: H(), body: JSON.stringify({ caption: 'receipt.jpg', data: 'data:image/jpeg;base64,AAAA' }) });
    assert.equal(r.status, 201);
    const attId = (await r.json()).id;
    r = await rq(`/transactions/${attachTxn}/attachments`, { headers: H() });
    j = await r.json();
    assert.equal(j.attachments.length, 1);
    r = await rq(`/transactions/attachments/${attId}/data`, { headers: H() });
    assert.equal((await r.json()).caption, 'receipt.jpg');
    r = await rq(`/transactions/attachments/${attId}`, { method: 'DELETE', headers: H() });
    assert.equal(r.status, 200);
    console.log('PASS ledger attachments add/get/del');

    // --- Phase 7: dashboard ---
    r = await rq('/reports/dashboard', { headers: H() });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.ok(j.receivable >= 0 && typeof j.this_month_expense === 'number');
    assert.ok(Array.isArray(j.trend) && j.trend.length === 6);
    console.log('PASS dashboard/insights');

    // --- Phase 7: expenses recycle ---
    r = await rq(`/expenses/${expId}`, { method: 'DELETE', headers: H() });
    assert.equal(r.status, 200);
    r = await rq('/recycle', { headers: H() });
    assert.ok((await r.json()).expenses.some((e) => e.id === expId));
    r = await rq(`/recycle/expenses/${expId}/restore`, { method: 'POST', headers: H() });
    assert.equal(r.status, 200);
    console.log('PASS expense recycle restore');

    // --- PIN lockout (5 wrongs) ---
    for (let i = 0; i < 4; i++) {
      r = await rq('/auth/pin-verify', { method: 'POST', headers: H(), body: JSON.stringify({ pin: '0000' }) });
      assert.equal(r.status, 401);
    }
    r = await rq('/auth/pin-verify', { method: 'POST', headers: H(), body: JSON.stringify({ pin: '0000' }) });
    assert.equal(r.status, 423);
    console.log('PASS pin lockout 423');

    // --- logout revokes refresh ---
    r = await rq('/auth/logout', { method: 'POST', body: JSON.stringify({ refresh }) });
    assert.equal(r.status, 200);
    r = await rq('/auth/refresh', { method: 'POST', body: JSON.stringify({ refresh }) });
    assert.equal(r.status, 401);
    console.log('PASS logout revokes refresh');

    // --- bad token rejected ---
    r = await rq('/auth/me', { headers: { authorization: 'Bearer bogus.token.here' } });
    assert.equal(r.status, 401);
    console.log('PASS bad token rejected');

    // --- staff roles: invite → claim → gate → promote → revoke ---
    r = await rq('/staff/invite', { method: 'POST', headers: H(), body: JSON.stringify({ phone: '9810000001', role: 'viewer' }) });
    assert.equal(r.status, 201);
    console.log('PASS staff invite');

    // staff registers with a password → pending invite for that phone is claimed
    r = await rq('/auth/register', { method: 'POST', body: JSON.stringify({ phone: '9810000001', password: 'staffpass1' }) });
    assert.equal(r.status, 201);
    j = await r.json();
    assert.equal(j.staff_books.length, 1);
    assert.equal(j.staff_books[0].role, 'viewer');
    console.log('PASS staff claim via password register');
    const staffAccess = j.access;
    const SH = () => ({ authorization: `Bearer ${staffAccess}`, 'x-book-owner-id': String(ownerId) });

    r = await rq('/customers', { headers: SH() });
    assert.equal(r.status, 200);
    r = await rq('/customers', { method: 'POST', headers: SH(), body: JSON.stringify({ name: 'Nope' }) });
    assert.equal(r.status, 403);
    r = await rq('/reports/summary', { headers: SH() });
    assert.equal(r.status, 403);
    console.log('PASS viewer read-only');

    r = await rq('/staff/role', { method: 'POST', headers: H(), body: JSON.stringify({ phone: '9810000001', role: 'entry' }) });
    assert.equal(r.status, 200);
    r = await rq('/customers', { method: 'POST', headers: SH(), body: JSON.stringify({ name: 'Staff Party' }) });
    assert.equal(r.status, 201);
    console.log('PASS entry can add');

    r = await rq('/staff/activity', { headers: H() });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.ok(j.activity.some((a) => a.action === 'customer_add' && a.actor_phone === '9810000001'));
    console.log('PASS staff activity logged');

    r = await rq('/staff/revoke', { method: 'POST', headers: H(), body: JSON.stringify({ phone: '9810000001' }) });
    assert.equal(r.status, 200);
    r = await rq('/customers', { headers: SH() });
    assert.equal(r.status, 403);
    console.log('PASS staff revoke');

    // --- invoice HTML (offline-capable render) ---
    r = await rq('/bills/1/html', { headers: H() });
    assert.equal(r.status, 200);
    const html = await r.text();
    assert.ok(html.includes('INV-1') && html.includes('Total:'));
    console.log('PASS invoice html standard');

    r = await rq('/bills/1/html?template=thermal', { headers: H() });
    assert.equal(r.status, 200);
    assert.ok((await r.text()).includes('TOTAL'));
    console.log('PASS invoice html thermal');

    r = await rq('/bills/9999/html', { headers: H() });
    assert.equal(r.status, 404);
    console.log('PASS invoice 404');

    // --- collections: link → pay → auto ledger entry ---
    r = await rq('/collections/links', { method: 'POST', headers: H(), body: JSON.stringify({ customer_id: cid, amount: 700 }) });
    assert.equal(r.status, 201);
    j = await r.json();
    assert.ok(j.ref && j.link);
    console.log('PASS paylink create', j.ref);

    r = await rq(`/collections/links/${j.ref}/pay`, { method: 'POST', headers: H() });
    assert.equal(r.status, 200);
    r = await rq(`/collections/links/${j.ref}/pay`, { method: 'POST', headers: H() });
    assert.equal(r.status, 409);
    console.log('PASS paylink pay + idempotent');

    r = await rq(`/customers/${cid}`, { headers: H() });
    assert.equal((await r.json()).balance, -200);
    console.log('PASS auto ledger entry (600 - 100 attach DEBIT - 700 = -200)');

    r = await rq('/collections/reminders', { method: 'POST', headers: H(), body: JSON.stringify({ customer_ids: [cid], channel: 'whatsapp', message: 'Please pay your dues' }) });
    assert.equal(r.status, 201);
    assert.equal((await r.json()).queued, 1);
    r = await rq('/collections/reminders', { headers: H() });
    assert.equal((await r.json()).reminders.length, 1);
    console.log('PASS reminders queue+list');

    // --- recycle bin: soft delete → restore → purge ---
    r = await rq('/customers', { method: 'POST', headers: H(), body: JSON.stringify({ name: 'Temp Party' }) });
    const tempId = (await r.json()).id;
    r = await rq('/transactions', { method: 'POST', headers: H(), body: JSON.stringify({ customer_id: tempId, kind: 'CREDIT', amount: 250 }) });
    const tempTxn = (await r.json()).id;
    r = await rq(`/customers/${tempId}`, { method: 'DELETE', headers: H() });
    assert.equal(r.status, 200);
    r = await rq(`/customers/${tempId}`, { headers: H() });
    assert.equal(r.status, 404);
    r = await rq('/recycle', { headers: H() });
    j = await r.json();
    assert.ok(j.customers.some((c) => c.id === tempId));
    console.log('PASS soft delete + recycle lists');

    r = await rq(`/recycle/customers/${tempId}/restore`, { method: 'POST', headers: H() });
    assert.equal(r.status, 200);
    r = await rq(`/customers/${tempId}`, { headers: H() });
    assert.equal((await r.json()).balance, 250);
    console.log('PASS recycle restore keeps balance');

    r = await rq(`/transactions/${tempTxn}`, { method: 'DELETE', headers: H() });
    assert.equal(r.status, 200);
    r = await rq(`/recycle/transactions/${tempTxn}/restore`, { method: 'POST', headers: H() });
    assert.equal(r.status, 200);
    console.log('PASS txn soft delete + restore');

    r = await rq(`/customers/${tempId}`, { method: 'DELETE', headers: H() });
    assert.equal(r.status, 200);
    r = await rq(`/recycle/customers/${tempId}/permanent`, { method: 'DELETE', headers: H() });
    assert.equal(r.status, 200);
    r = await rq('/recycle', { headers: H() });
    j = await r.json();
    assert.ok(!j.customers.some((c) => c.id === tempId));
    console.log('PASS permanent purge');

    // --- backup export/import roundtrip ---
    r = await rq('/backup/export', { headers: H() });
    assert.equal(r.status, 200);
    const dump = await r.json();
    assert.ok(dump.customers.length >= 2 && dump.version === 1);
    const payload = {
      version: 1,
      customers: dump.customers.map((c) => ({ name: c.name, phone: c.phone, address: c.address, opening_balance: c.opening_balance, deleted_at: c.deleted_at })),
      transactions: [],
      bills: [],
    };
    // re-link first txn to first customer for import validation
    if (dump.transactions.length > 0) {
      const t0 = dump.transactions[0];
      payload.transactions.push({ customer_index: 0, kind: t0.kind, amount: t0.amount, note: t0.note || '', txn_date: t0.txn_date });
    }
    r = await rq('/backup/import', { method: 'POST', headers: H(), body: JSON.stringify(payload) });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.equal(j.customers, payload.customers.length);
    r = await rq('/customers', { headers: H() });
    assert.equal((await r.json()).customers.length, payload.customers.length);
    console.log('PASS backup export/import');

    // --- Phase 8: referral code + stats ---
    r = await rq('/business/referral', { headers: H() });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.ok(/^KB[A-Z0-9]{4,}$/.test(j.code), 'referral code shape: ' + j.code);
    assert.equal(j.bonus_per_friend, 100);
    assert.equal(j.friends, 0);
    console.log('PASS referral code generated + stats');

    // --- Phase 8: business card with vCard QR payload ---
    r = await rq('/business/card', { headers: H() });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.ok(j.name && j.business_name && j.phone && j.business_name === 'Test Store');
    assert.ok(j.qr_payload.includes('BEGIN:VCARD') && j.qr_payload.includes('END:VCARD'));
    console.log('PASS business card + vCard payload');

    // --- Phase 8: staff member claims owner's referral (double reward) ---
    r = await rq('/business/referral', { headers: H() });
    const ownerCode = (await r.json()).code;
    r = await rq('/business/referral/claim', { method: 'POST', headers: SH(), body: JSON.stringify({ code: ownerCode }) });
    assert.equal(r.status, 200);
    assert.equal((await r.json()).bonus, 100);
    r = await rq('/business/referral/claim', { method: 'POST', headers: SH(), body: JSON.stringify({ code: ownerCode }) });
    assert.equal(r.status, 409);
    r = await rq('/business/referral', { headers: H() });
    assert.equal((await r.json()).friends, 1);
    console.log('PASS referral claim + one-time check + friend count');

    // --- Phase 9: txn SMS preference toggle ---
    r = await rq('/business/preferences', { method: 'POST', headers: H(), body: JSON.stringify({ txn_sms: true }) });
    assert.equal(r.status, 200);
    r = await rq('/business/preferences', { headers: H() });
    assert.equal((await r.json()).txn_sms, true);
    console.log('PASS txn SMS preference toggle');

    // --- Phase 9: day book (cash register) report ---
    r = await rq('/reports/daybook', { headers: H() });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.ok(Array.isArray(j.transactions) && typeof j.given === 'number' && typeof j.net === 'number');
    assert.ok(Array.isArray(j.days) && j.days.includes(j.date));
    console.log('PASS daybook report');

    // --- Phase 10: invoice seal ---
    r = await rq('/bills', { method: 'POST', headers: H(), body: JSON.stringify({ invoice_no: 'INV-SEAL', gst_slab_index: 5, items: [{ name: 'Rice 5kg', qty: 1, rate: 500 }] }) });
    const sealBillId = (await r.json()).id;
    r = await rq(`/bills/${sealBillId}/html?seal=1`, { headers: H() });
    assert.equal(r.status, 200);
    assert.ok((await r.text()).includes('class="seal"'));
    console.log('PASS invoice seal');

    // --- encrypted PII: plaintext on API, ciphertext at rest, search works ---
    r = await rq('/customers', { method: 'POST', headers: H(), body: JSON.stringify({ name: 'Secret Party', phone: '9811122233', address: 'Hidden Lane' }) });
    assert.equal(r.status, 201);
    const secId = (await r.json()).id;
    r = await rq('/customers', { headers: H() });
    j = await r.json();
    const sec = j.customers.find((c) => c.id === secId);
    assert.equal(sec.name, 'Secret Party');
    assert.equal(sec.phone, '9811122233');
    r = await rq('/customers?q=Secret', { headers: H() });
    j = await r.json();
    assert.ok(j.customers.some((c) => c.id === secId));
    console.log('PASS encrypted PII roundtrip + search');
    const { DatabaseSync } = require('node:sqlite');
    const tdb = new DatabaseSync(TEST_DB);
    const raw = tdb.prepare('SELECT name, phone, address FROM customers WHERE id=?').get(secId);
    assert.ok(String(raw.name).startsWith('v2:') && String(raw.phone).startsWith('v2:') && String(raw.address).startsWith('v2:'));
    tdb.close();
    console.log('PASS PII ciphertext at rest');

    // --- bill unknown item: 400 + no orphan bill left behind ---
    r = await rq('/bills', { headers: H() });
    const billsBefore = (await r.json()).bills.length;
    r = await rq('/bills', { method: 'POST', headers: H(), body: JSON.stringify({ invoice_no: 'INV-ORPHAN', items: [{ name: 'X', qty: 1, rate: 10, item_id: 999999 }] }) });
    assert.equal(r.status, 400);
    r = await rq('/bills', { headers: H() });
    assert.equal((await r.json()).bills.length, billsBefore);
    console.log('PASS bill unknown_item leaves no orphan');

    // --- export → import verbatim (the app's own restore flow) ---
    r = await rq('/backup/export', { headers: H() });
    assert.equal(r.status, 200);
    const dumpA = await r.json();
    r = await rq('/backup/import', { method: 'POST', headers: H(), body: JSON.stringify(dumpA) });
    assert.equal(r.status, 200);
    j = await r.json();
    assert.equal(j.customers, dumpA.customers.length);
    r = await rq('/backup/export', { headers: H() });
    const dumpB = await r.json();
    assert.equal(dumpB.customers.length, dumpA.customers.length);
    assert.equal(dumpB.transactions.length, dumpA.transactions.length);
    assert.equal(dumpB.bills.length, dumpA.bills.length);
    assert.equal(dumpB.bill_items.length, dumpA.bill_items.length);
    console.log('PASS export-import verbatim roundtrip');

    console.log('ALL TESTS PASSED');
  } finally {
    server.close();
    setTimeout(() => process.exit(0), 300);
  }
}

main().catch((e) => { console.error('TEST FAILED', e); setTimeout(() => process.exit(1), 300); });
