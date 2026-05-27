import { AppRole, appRoleFromString, ExecomFeature, BudgetAuthorityPosts } from './constants';
import { UserModel, ExecomMemberModel, ExecomPermissionModel } from '../models/types';

export class PermissionEngine {
  readonly user: UserModel;
  readonly userExecomMemberships: ExecomMemberModel[];
  readonly execomPermissions: Record<number, ExecomPermissionModel[]>;

  constructor(
    user: UserModel,
    userExecomMemberships: ExecomMemberModel[] = [],
    execomPermissions: Record<number, ExecomPermissionModel[]> = {}
  ) {
    this.user = user;
    this.userExecomMemberships = userExecomMemberships;
    this.execomPermissions = execomPermissions;
  }

  get role(): AppRole {
    return appRoleFromString(this.user.role);
  }

  // Tier getters
  get isTier1(): boolean { return this.role === AppRole.chairman || this.role === AppRole.viceChairman; }
  get isTier2(): boolean { return this.role === AppRole.coreExeccom || this.role === AppRole.facultyAdvisor; }
  get isTier3(): boolean { return this.role === AppRole.forumExeccom; }
  get isTier4(): boolean { return this.role === AppRole.panel; }
  get isTier5(): boolean { return this.role === AppRole.restricted; }
  get isTier6(): boolean { return this.role === AppRole.member; }

  get isAtLeastTier1(): boolean { return this.role >= AppRole.viceChairman; }
  get isAtLeastTier2(): boolean { return this.role >= AppRole.coreExeccom; }
  get isAtLeastTier3(): boolean { return this.role >= AppRole.forumExeccom; }
  get isAtLeastTier4(): boolean { return this.role >= AppRole.panel; }

  get isEffectivelyTier1(): boolean {
    return this.isTier1 || (this.isTier2 && this.user.is_sudo);
  }

  // Actions
  get canAddMembers(): boolean { return this._isCommitteeLead; }
  get canRemoveMembers(): boolean { return this.isAtLeastTier1; }
  get canEditMembers(): boolean { return this.isTier1; }
  get canAssignRoles(): boolean { return this.isAtLeastTier1; }
  get canManageExecom(): boolean { return this.isAtLeastTier1; }
  get canManageGlobalPermissions(): boolean { return this.role === AppRole.chairman; }
  get canManageExecomPermissions(): boolean { return this.isAtLeastTier1; }
  get canManagePermissions(): boolean { return this.canManageGlobalPermissions || this.canManageExecomPermissions; }

  get _isCommitteeLead(): boolean {
    if (this.isAtLeastTier1) return true;
    if (this.isAtLeastTier2) return true;
    if (this.isTier3) {
      const p = (this.user.post || '').toLowerCase();
      return p.includes('chair') || p.includes('secretary');
    }
    return false;
  }

  get _isTop4(): boolean {
    if (this.isTier1) return true;
    if (this.isTier2) {
      const p = (this.user.post || '').toLowerCase();
      return p === 'secretary' || p === 'treasurer';
    }
    return false;
  }

  canManageMembersInExecom(execomId: number): boolean {
    if (this.isAtLeastTier1) return true;
    if (this.isAtLeastTier2 && this.isMemberOfExecom(execomId)) return true;
    const fRole = (this.execomRoleIn(execomId) || '').toLowerCase();
    return fRole.includes('chair') || fRole.includes('head');
  }

  isFeatureEnabledGlobally(feature: string): boolean {
    const perms = this.execomPermissions[0] || [];
    const perm = perms.find((p) => p.feature === feature);
    return perm ? perm.allowed : false;
  }

  // Feature limits
  get canCreateEvents(): boolean { return this.isAtLeastTier3; }
  get canReadReports(): boolean { return this.isAtLeastTier2; }
  get canUploadReports(): boolean { return this.isAtLeastTier4; }
  get canViewTotalBudget(): boolean { return this.isAtLeastTier2; }
  get canAccessScopedBudget(): boolean { return this.isAtLeastTier3; }
  get canViewMembers(): boolean { return this.role !== AppRole.restricted; }
  get isPanel(): boolean { return this.isTier4; }
  get canRequestBudget(): boolean { return this.isAtLeastTier3; }
  get canManageBudget(): boolean { return this._isTop4; }
  get canViewInternalAnnouncements(): boolean { return this.isAtLeastTier3; }
  get canManageAnnouncements(): boolean { return this.isAtLeastTier2; }
  get canOverride(): boolean { return this.role === AppRole.chairman; }
  get canAccessChat(): boolean { return this.isAtLeastTier4; }

  get canApproveBudget(): boolean {
    if (this.isEffectivelyTier1) return true;
    if (this.isTier2) return BudgetAuthorityPosts.hasBudgetAuthority(this.user.post);
    return false;
  }

  // Execom Scopes
  isMemberOfExecom(execomId: number): boolean {
    return this.userExecomMemberships.some((m) => m.execom_id === execomId);
  }

  execomRoleIn(execomId: number): string | undefined {
    const membership = this.userExecomMemberships.find((m) => m.execom_id === execomId);
    return membership?.execom_role;
  }

  canDoInExecom(execomId: number, feature: string): boolean {
    if (this.isEffectivelyTier1) return true;

    const perms = this.execomPermissions[execomId] || [];
    const perm = perms.find((p) => p.feature === feature);

    if (this.isAtLeastTier2) {
      if (perm !== undefined) return perm.allowed;
      return true;
    }

    if (!this.isMemberOfExecom(execomId)) return false;

    if (this.isAtLeastTier3) {
      if (perm !== undefined) return perm.allowed;
      return true;
    }

    return perm ? perm.allowed : false;
  }

  canCreateEventInExecom(execomId: number): boolean {
    return this.canCreateEvents && this.canDoInExecom(execomId, ExecomFeature.createEvents);
  }

  canUploadReportInExecom(execomId: number): boolean {
    return this.canUploadReports && this.canDoInExecom(execomId, ExecomFeature.uploadReports);
  }

  canViewBudgetInExecom(execomId: number): boolean {
    return this.canAccessScopedBudget && this.canDoInExecom(execomId, ExecomFeature.viewBudget);
  }

  get userExecomIds(): number[] {
    return this.userExecomMemberships.map((m) => m.execom_id);
  }
}
