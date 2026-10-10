import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rateLimitKey } from '../src/utils/ip.ts';

test('rateLimitKey: IPv4 keeps the full address', () => {
  assert.equal(rateLimitKey('1.2.3.4'), '1.2.3.4');
});

test('rateLimitKey: addresses in one IPv6 /64 share a key', () => {
  assert.equal(rateLimitKey('2001:db8:1:2:3:4:5:6'), '2001:db8:1:2::/64');
  assert.equal(rateLimitKey('2001:DB8:1:2:ffff::9'), '2001:db8:1:2::/64');
  assert.notEqual(rateLimitKey('2001:db8:1:3::1'), rateLimitKey('2001:db8:1:2::1'));
});

test('rateLimitKey: compressed IPv6 is expanded before taking the prefix', () => {
  assert.equal(rateLimitKey('2001:db8::1'), '2001:db8:0:0::/64');
  assert.equal(rateLimitKey('::1'), '0:0:0:0::/64');
  assert.equal(rateLimitKey('2001:0db8:0000:0042::7'), '2001:db8:0:42::/64');
});

test('rateLimitKey: missing or malformed input collapses to one shared key', () => {
  assert.equal(rateLimitKey(null), 'unknown');
  assert.equal(rateLimitKey(''), 'unknown');
  assert.equal(rateLimitKey('not-an-ip'), 'unknown');
  assert.equal(rateLimitKey('1::2::3'), 'unknown');
});
