// Pure validation checks; no network, credentials, or database mutations.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../src/screens/scan/scan-validation.ts'), 'utf8');
const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
const context = { exports: {} };
vm.runInNewContext(output, context);
const { parsePositiveInteger, isFreshQrTimestamp, isValidAttendanceDay } = context.exports;
assert.equal(parsePositiveInteger('42'), 42);
for (const input of [null, '', '0', '-1', '1x', '1.5', 'NaN', '9007199254740992']) {
  assert.equal(parsePositiveInteger(input), null, String(input));
}
assert.equal(isValidAttendanceDay(1, 1), true);
assert.equal(isValidAttendanceDay(3, 3), true);
for (const [day, count] of [[0, 3], [4, 3], [1.2, 3], [1, 0], [NaN, 3]]) {
  assert.equal(isValidAttendanceDay(day, count), false);
}
const now = 100000;
for (const timestamp of [now, now - 30000, now + 5000]) assert.equal(isFreshQrTimestamp(timestamp, now), true);
for (const timestamp of [now - 30001, now + 5001, NaN, Infinity, null, '100000']) {
  assert.equal(isFreshQrTimestamp(timestamp, now), false);
}
console.log('PASS: event ID, day range, expired/future/malformed QR timestamp checks.');
