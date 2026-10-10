import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyProbeError, probeIssues } from '../src/telegram/integrity.ts';

const tg = (desc: string) => `TG getFile failed (400): {"ok":false,"error_code":400,"description":"${desc}"}`;

test('classifyProbeError: 400 is bad400 unless the file is too big for the cloud API', () => {
  assert.equal(classifyProbeError(400, tg('Bad Request: wrong file_id or the file is temporarily unavailable')), 'bad400');
  assert.equal(classifyProbeError(400, tg('Bad Request: invalid file_id')), 'bad400');
  assert.equal(classifyProbeError(400, tg('Bad Request: file is too big')), 'transient');
});

test('classifyProbeError: 401 is unauthorized, everything else transient', () => {
  assert.equal(classifyProbeError(401, 'Unauthorized'), 'unauthorized');
  for (const s of [404, 429, 500, 502]) assert.equal(classifyProbeError(s, 'x'), 'transient');
  assert.equal(classifyProbeError(undefined, 'The operation was aborted due to timeout'), 'transient');
});

const empty = { probed: 12, bad400: [], unauthorized: 0, transient: 0 };

test('probeIssues: healthy run reports nothing', () => {
  assert.deepEqual(probeIssues(empty), []);
  assert.deepEqual(probeIssues({ ...empty, probed: 0 }), []);
});

test('probeIssues: a single 400 lists the key but does not blame the token', () => {
  const lines = probeIssues({ ...empty, bad400: [{ bucket: 'b', key: 'k.txt' }] });
  assert.match(lines[0], /1 of 12/);
  assert.match(lines[0], /Nothing was deleted/);
  assert.equal(lines[1], '- b/k.txt');
  assert.ok(!lines.some(l => /different bot/.test(l)));
});

test('probeIssues: every probe 400 points at a different bot, diagnosis before the key list', () => {
  const bad = [1, 2, 3].map(i => ({ bucket: 'b', key: `k${i}` }));
  const lines = probeIssues({ ...empty, probed: 3, bad400: bad });
  assert.match(lines[0], /different bot/);
  assert.ok(lines.indexOf('- b/k1') > 0);
});

test('probeIssues: listing is capped and long keys are cut before escaping', () => {
  const bad = Array.from({ length: 12 }, (_, i) => ({ bucket: 'b', key: 'x'.repeat(1000) + i }));
  const lines = probeIssues({ ...empty, bad400: bad });
  const listed = lines.filter(l => l.startsWith('- '));
  assert.equal(listed.length, 10);
  for (const l of listed) assert.ok(l.length <= 200);
});

test('probeIssues: 401 and degraded Telegram are reported', () => {
  assert.ok(probeIssues({ ...empty, unauthorized: 12 }).some(l => /401/.test(l)));
  assert.ok(probeIssues({ ...empty, transient: 7 }).some(l => /degraded/.test(l)));
  assert.deepEqual(probeIssues({ ...empty, transient: 5 }), []);
});
