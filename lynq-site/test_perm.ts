import { AppRole, appRoleFromString, FolderFeature } from './src/core/constants';
import { PermissionEngine } from './src/core/permission-engine';

const roleStr = 'BITS Joint Secretary';
const dbRole = appRoleFromString(roleStr);
console.log('appRoleFromString:', dbRole);

const engine = new PermissionEngine(
  { id: '123', role: roleStr, post: 'BITS Joint Secretary', name: 'Sree', email: 's@a.com' } as any,
  [{ folder_id: 29 }] as any,
  {}
);

console.log('engine.role:', engine.role);
console.log('engine.isAtLeastTier2:', engine.isAtLeastTier2);
console.log('engine.canViewTotalBudget:', engine.canViewTotalBudget);
