const test = require('node:test');
const assert = require('node:assert');

const {
  matchStay,
  dayBounds,
  isFourDigits,
  isAccessCode,
  checkGuestCode,
} = require('../lib/guest');

// The shape of a PamperHomes hub `reservations` mirror document.
const stay = (over = {}) => ({
  status: 'accepted',
  arrivalDate: '2026-11-10T16:00:00-05:00',
  departureDate: '2026-11-14T11:00:00-05:00',
  phoneLast4: ['0187'],
  ...over,
});
const at = (iso) => Date.parse(iso);
const NOW = at('2026-11-12T12:00:00-05:00');

test('only exactly four digits are a guest code', () => {
  for (const ok of ['0187', '0000']) assert.ok(isFourDigits(ok));
  for (const bad of ['187', '01870', 'abcd', 187, null]) assert.ok(!isFourDigits(bad));
});

test('access codes are four or six digits', () => {
  for (const ok of ['0187', '765432']) assert.ok(isAccessCode(ok));
  for (const bad of ['01870', '1234567', '12ab']) assert.ok(!isAccessCode(bad));
});

test('day bounds use the offset the hub stored', () => {
  const b = dayBounds('2026-11-10T16:00:00-05:00');
  assert.strictEqual(b.start, at('2026-11-10T00:00:00-05:00'));
  assert.strictEqual(b.end, at('2026-11-11T00:00:00-05:00') - 1);
});

test('a matching stay unlocks from check-in day through checkout day', () => {
  const r = [stay()];
  assert.strictEqual(matchStay(r, '0187', at('2026-11-09T23:59:00-05:00')), null);
  const s = matchStay(r, '0187', at('2026-11-10T08:00:00-05:00'));
  assert.ok(s);
  assert.strictEqual(s.endsAt, at('2026-11-15T00:00:00-05:00') - 1);
  assert.ok(matchStay(r, '0187', at('2026-11-14T22:00:00-05:00')));
  assert.strictEqual(matchStay(r, '0187', at('2026-11-15T00:00:01-05:00')), null);
});

test('wrong digits and dead stays do not unlock', () => {
  assert.strictEqual(matchStay([stay()], '1234', NOW), null);
  for (const status of ['cancelled', 'Canceled', 'pending', 'declined', 'denied', 'expired']) {
    assert.strictEqual(matchStay([stay({ status })], '0187', NOW), null, status);
  }
});

test('any phone on the booking counts', () => {
  assert.ok(matchStay([stay({ phoneLast4: ['9999', '0187'] })], '0187', NOW));
});

test('of two matching stays, the one ending later wins', () => {
  const later = stay({ departureDate: '2026-11-20T11:00:00-05:00' });
  const s = matchStay([stay(), later], '0187', NOW);
  assert.strictEqual(s.endsAt, at('2026-11-21T00:00:00-05:00') - 1);
});

const codes = { reviewCode: '135790', ownerCode: '765432' };
const none = async () => [];

test('the owner code gives the owner role', async () => {
  const r = await checkGuestCode('765432', NOW, codes, none);
  assert.deepStrictEqual([r.ok, r.role], [true, 'owner']);
});

test('the review code gives the reviewer role without a reservation', async () => {
  const r = await checkGuestCode('135790', NOW, codes, none);
  assert.deepStrictEqual([r.ok, r.role], [true, 'reviewer']);
});

test('a wrong six digits unlocks nothing and never looks up stays', async () => {
  let looked = false;
  const spy = async () => { looked = true; return [stay()]; };
  assert.ok(!(await checkGuestCode('550187', NOW, codes, spy)).ok);
  assert.ok(!looked);
});

test('unset codes unlock nothing', async () => {
  const empty = { reviewCode: '', ownerCode: '' };
  assert.ok(!(await checkGuestCode('000000', NOW, empty, none)).ok);
});

test('a guest code matches a current stay', async () => {
  const r = await checkGuestCode('0187', NOW, codes, async () => [stay()]);
  assert.deepStrictEqual([r.ok, r.role], [true, 'guest']);
  assert.ok(!(await checkGuestCode('0187', NOW, codes, none)).ok);
});
