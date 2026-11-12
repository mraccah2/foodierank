const test = require('node:test');
const assert = require('node:assert');

const { takeoutPrefix } = require('../lib/account');

test('takeout prefix is scoped to one user folder', () => {
  assert.strictEqual(takeoutPrefix('abcDEF123_-x'), 'takeout/abcDEF123_-x/');
});

test('takeout prefix refuses uids that would widen the delete', () => {
  // An empty uid would produce "takeout//" today, but any slip toward
  // "takeout/" deletes every user's archives, so refuse rather than trust it.
  for (const uid of ['', '/', 'a/b', '../x', 'a b', undefined, null]) {
    assert.throws(() => takeoutPrefix(uid), /Refusing/);
  }
});
