import test from 'node:test';
import assert from 'node:assert/strict';
import {
  digitsOnly,
  formatMoney,
  isStaleModalResponse,
  parseTipInput,
  quickTipAmounts,
  shouldHandleEscape,
} from '../src/format.js';

test('formatMoney formats non-negative integers with commas', () => {
  assert.equal(formatMoney(0), '0');
  assert.equal(formatMoney(5860), '5,860');
  assert.equal(formatMoney(100000), '100,000');
  assert.equal(formatMoney(-5), '0');
  assert.equal(formatMoney(NaN), '0');
});

test('digitsOnly strips non-digit characters', () => {
  assert.equal(digitsOnly('1,000abc'), '1000');
  assert.equal(digitsOnly(' -50.5 '), '505');
  assert.equal(digitsOnly(''), '');
});

test('quickTipAmounts filters presets to configured min..max bounds', () => {
  assert.deepEqual(quickTipAmounts(1, 100000), [100, 500, 1000, 5000]);
  assert.deepEqual(quickTipAmounts(200, 1000), [500, 1000]);
  assert.deepEqual(quickTipAmounts(10000, 50000), []);
});

test('parseTipInput accepts valid integer strings within bounds', () => {
  assert.deepEqual(parseTipInput('1000', 1, 100000), { ok: true, value: 1000 });
  assert.deepEqual(parseTipInput(' 1 ', 1, 100000), { ok: true, value: 1 });
  assert.deepEqual(parseTipInput('100000', 1, 100000), { ok: true, value: 100000 });
});

test('parseTipInput rejects empty, decimals, non-digits, zero, negative, and out-of-range', () => {
  for (const bad of ['', '   ', '0', '-10', '10.5', '100abc', '100001', '1e3']) {
    const res = parseTipInput(bad, 1, 100000);
    assert.equal(res.ok, false, `expected reject for ${JSON.stringify(bad)}`);
    assert.equal(typeof res.error, 'string');
    assert.ok(res.error.length > 0);
  }
});

test('modal guard blocks Escape while submitting and detects stale RPC responses', () => {
  assert.equal(shouldHandleEscape('tip', false), true);
  assert.equal(shouldHandleEscape('tip', true), false);
  assert.equal(shouldHandleEscape(null, false), false);

  assert.equal(isStaleModalResponse('busk_1', 'busk_1'), false);
  assert.equal(isStaleModalResponse('busk_2', 'busk_1'), true);
  assert.equal(isStaleModalResponse(null, 'busk_1'), true);
});
