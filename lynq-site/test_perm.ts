import fs from 'fs';
import path from 'path';
import { appRoleFromString } from './src/core/constants';
import { PermissionEngine } from './src/core/permission-engine';

function assert(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(`Assertion failed: ${message}`);
  }
}

async function runTests() {
  console.log('Running TypeScript PermissionEngine tests...');
  const matrixPath = path.resolve('../shared/permission_matrix.json');
  const matrix = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));

  // 1. Role tests
  console.log('\n- Running Role Parsing Tests...');
  for (const tc of matrix.role_tests) {
    const parsed = appRoleFromString(tc.input);
    const expected = (AppRole as any)[tc.expected];
    assert(parsed === expected, `Role parsing mismatch for "${tc.input}". Expected: ${tc.expected} (${expected}), Got: ${parsed}`);
  }
  console.log('  Role Parsing Tests: PASS');

  // 2. Global permission tests
  console.log('\n- Running Global Permission Tests...');
  for (const tc of matrix.permission_tests) {
    const user = {
      id: tc.user.id,
      name: tc.user.name,
      email: tc.user.email,
      role: tc.user.role,
      is_sudo: tc.user.is_sudo,
      status: tc.user.status,
      suspended_until: tc.user.suspended_until,
    };
    const engine = new PermissionEngine(user as any, [], {});

    if (tc.expected.isSuspended !== undefined) {
      assert(engine.isSuspended === tc.expected.isSuspended, `${tc.description}: isSuspended mismatch. Expected: ${tc.expected.isSuspended}, Got: ${engine.isSuspended}`);
    }
    if (tc.expected.isEffectivelyTier1 !== undefined) {
      assert(engine.isEffectivelyTier1 === tc.expected.isEffectivelyTier1, `${tc.description}: isEffectivelyTier1 mismatch. Expected: ${tc.expected.isEffectivelyTier1}, Got: ${engine.isEffectivelyTier1}`);
    }

    for (const [key, expectedVal] of Object.entries(tc.expected)) {
      if (key === 'isSuspended' || key === 'isEffectivelyTier1') continue;
      const actualVal = (engine as any)[key];
      assert(actualVal === expectedVal, `${tc.description}: Permission "${key}" mismatch. Expected: ${expectedVal}, Got: ${actualVal}`);
    }
  }
  console.log('  Global Permission Tests: PASS');

  // 3. Folder permission tests
  console.log('\n- Running Folder Permission Tests...');
  for (const tc of matrix.folder_permission_tests) {
    const user = {
      id: tc.user.id,
      name: tc.user.name,
      email: tc.user.email,
      role: tc.user.role,
      is_sudo: tc.user.is_sudo,
      status: tc.user.status,
    };

    const memberships = tc.memberships.map((m: any) => ({
      id: 0,
      folder_id: m.folder_id,
      user_id: user.id,
      folder_role: m.folder_role,
    }));

    const permissionsMap: Record<number, any[]> = {};
    for (const p of tc.permissions) {
      const fid = p.folder_id;
      if (!permissionsMap[fid]) permissionsMap[fid] = [];
      permissionsMap[fid].push({
        id: 0,
        execom_id: fid,
        feature: p.feature,
        allowed: p.allowed,
      });
    }

    const engine = new PermissionEngine(user as any, memberships as any, permissionsMap);

    for (const check of tc.checks) {
      const fid = check.folder_id;
      const expected = check.expected;
      if (check.check_type === 'canManageMembersInFolder') {
        const actual = engine.canManageMembersInFolder(fid);
        assert(actual === expected, `${tc.description}: canManageMembersInFolder mismatch. Expected: ${expected}, Got: ${actual}`);
      } else {
        const feature = check.feature;
        const actual = engine.canDoInFolder(fid, feature);
        assert(actual === expected, `${tc.description}: canDoInFolder("${feature}") mismatch. Expected: ${expected}, Got: ${actual}`);
      }
    }
  }
  console.log('  Folder Permission Tests: PASS');

  console.log('\nALL TS TESTS PASSED SUCCESSFULLY! 🎉');
}

import { AppRole } from './src/core/constants';

runTests().catch((err) => {
  console.error('\n❌ Test execution failed:');
  console.error(err.message);
  process.exit(1);
});
