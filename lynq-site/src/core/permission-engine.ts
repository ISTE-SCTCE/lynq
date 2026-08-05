import { AppRole, appRoleFromString, FolderFeature, BudgetAuthorityPosts } from './constants';
import { UserModel, FolderMemberModel, FolderPermissionModel } from '../models/types';

export class PermissionEngine {
  readonly user: UserModel;
  readonly userFolderMemberships: FolderMemberModel[];
  readonly folderPermissions: Record<number, FolderPermissionModel[]>;

  constructor(
    user: UserModel,
    userFolderMemberships: FolderMemberModel[] = [],
    folderPermissions: Record<number, FolderPermissionModel[]> = {}
  ) {
    this.user = user;
    this.userFolderMemberships = userFolderMemberships;
    this.folderPermissions = folderPermissions;
  }

  get role(): AppRole {
    const dbRole = appRoleFromString(this.user.role);
    // If DB role underreports access: a user in folder_members is at minimum a forum execom member.
    if (dbRole < AppRole.forumExeccom && this.userFolderMemberships.length > 0) {
      return AppRole.forumExeccom;
    }
    return dbRole;
  }

  /// Check user suspension status
  get isSuspended(): boolean {
    if (this.user.status === 'suspended') return true;
    const until = this.user.suspended_until;
    if (until && new Date(until) > new Date()) return true;
    return false;
  }

  // Tier getters
  get isTier1(): boolean { return !this.isSuspended && (this.role === AppRole.chairman || this.role === AppRole.viceChairman); }
  get isTier2(): boolean { return !this.isSuspended && this.role === AppRole.coreExeccom; }
  get isTier3(): boolean { return !this.isSuspended && this.role === AppRole.forumExeccom; }
  get isTier4(): boolean { return !this.isSuspended && this.role === AppRole.panel; }
  get isTier5(): boolean { return !this.isSuspended && this.role === AppRole.restricted; }
  get isTier6(): boolean { return !this.isSuspended && this.role === AppRole.member; }

  get isAtLeastTier1(): boolean { return !this.isSuspended && this.role >= AppRole.viceChairman; }
  get isAtLeastTier2(): boolean { return !this.isSuspended && this.role >= AppRole.coreExeccom; }
  get isAtLeastTier3(): boolean { return !this.isSuspended && this.role >= AppRole.forumExeccom; }
  get isAtLeastTier4(): boolean { return !this.isSuspended && this.role >= AppRole.panel; }

  get isEffectivelyTier1(): boolean {
    return !this.isSuspended && (this.isTier1 || (this.isTier2 && !!this.user.is_sudo));
  }

  // Actions
  get canAddMembers(): boolean { return !this.isSuspended && this._isCommitteeLead; }
  get canRemoveMembers(): boolean { return !this.isSuspended && this.isAtLeastTier1; }
  get canEditMembers(): boolean { return !this.isSuspended && this.isTier1; }
  get canAssignRoles(): boolean { return !this.isSuspended && this.isAtLeastTier1; }
  get canManageFolders(): boolean { return !this.isSuspended && this.isAtLeastTier1; }
  get canManageGlobalPermissions(): boolean { return !this.isSuspended && this.role === AppRole.chairman; }
  get canManageFolderPermissions(): boolean { return !this.isSuspended && this.isAtLeastTier1; }
  get canManagePermissions(): boolean { return !this.isSuspended && (this.canManageGlobalPermissions || this.canManageFolderPermissions); }

  get _isCommitteeLead(): boolean {
    if (this.isSuspended) return false;
    if (this.isAtLeastTier2) return true; // covers Tier1 + Tier2
    if (this.isTier3) {
      const p = (this.user.post || '').toLowerCase();
      return p === 'chair' || p === 'chairman' || p === 'secretary';
    }
    return false;
  }

  get _isTop4(): boolean {
    if (this.isSuspended) return false;
    if (this.isTier1) return true;
    if (this.isTier2) {
      const p = (this.user.post || '').toLowerCase();
      return p === 'secretary' || p === 'treasurer';
    }
    return false;
  }

  canManageMembersInFolder(folderId: number): boolean {
    if (this.isSuspended) return false;
    if (this.isAtLeastTier1) return true;
    if (this.isAtLeastTier2 && this.isMemberOfFolder(folderId)) return true;
    
    // Wire up manageAll bypass
    if (this.canDoInFolder(folderId, FolderFeature.manageAll)) return true;

    // Exact folder-role match
    const fRole = (this.folderRoleIn(folderId) || '').toLowerCase().trim();
    return fRole === 'chair' || fRole === 'head';
  }

  isFeatureEnabledGlobally(feature: string): boolean {
    if (this.isSuspended) return false;
    const perms = this.folderPermissions[0] || [];
    const perm = perms.find((p) => p.feature === feature);
    return perm ? perm.allowed : false;
  }

  // Feature limits
  get canCreateEvents(): boolean { return !this.isSuspended && this.isAtLeastTier3; }
  get canReadReports(): boolean { return !this.isSuspended && (this.isAtLeastTier2 || (this.isMemberOfFolder(0) && this.isFeatureEnabledGlobally(FolderFeature.viewReports))); }
  get canUploadReports(): boolean { return !this.isSuspended && this.isAtLeastTier4; }
  get canViewTotalBudget(): boolean { return !this.isSuspended && (this.isAtLeastTier2 || (this.isMemberOfFolder(0) && this.isFeatureEnabledGlobally(FolderFeature.viewTotalBudget))); }
  get canAccessScopedBudget(): boolean { return !this.isSuspended && this.isAtLeastTier3; }
  get canViewMembers(): boolean { return !this.isSuspended && this.role !== AppRole.restricted; }
  get isPanel(): boolean { return !this.isSuspended && this.isTier4; }
  get canRequestBudget(): boolean { return !this.isSuspended && this.isAtLeastTier3; }
  get canManageBudget(): boolean { return !this.isSuspended && this._isTop4; }
  get canViewInternalAnnouncements(): boolean { return !this.isSuspended && this.isAtLeastTier3; }
  get canManageAnnouncements(): boolean { return !this.isSuspended && this.isAtLeastTier2; }
  get canOverride(): boolean { return !this.isSuspended && this.role === AppRole.chairman; }
  get canAccessChat(): boolean { return !this.isSuspended && this.isAtLeastTier4; }

  get canApproveBudget(): boolean {
    if (this.isSuspended) return false;
    if (this.isEffectivelyTier1) return true;
    if (this.isTier2) return BudgetAuthorityPosts.hasBudgetAuthority(this.user.post);
    return false;
  }

  // Folder Scopes
  isMemberOfFolder(folderId: number): boolean {
    return !this.isSuspended && this.userFolderMemberships.some((m) => m.folder_id === folderId);
  }

  folderRoleIn(folderId: number): string | undefined {
    if (this.isSuspended) return undefined;
    const membership = this.userFolderMemberships.find((m) => m.folder_id === folderId);
    return membership?.folder_role;
  }

  canDoInFolder(folderId: number, feature: string): boolean {
    if (this.isSuspended) return false;
    if (this.isEffectivelyTier1) return true;

    const perms = this.folderPermissions[folderId] || [];

    // If checking regular feature, see if manageAll is globally allowed
    if (feature !== FolderFeature.manageAll) {
      const manageAllPerm = perms.find((p) => p.feature === FolderFeature.manageAll);
      if (manageAllPerm?.allowed) {
        return true;
      }
    }

    const perm = perms.find((p) => p.feature === feature);

    // Option A: Default-allow inside folder for Tier 2/3
    if (this.isAtLeastTier2) {
      if (perm !== undefined) return perm.allowed;
      return true;
    }

    if (!this.isMemberOfFolder(folderId)) return false;

    if (this.isAtLeastTier3) {
      if (perm !== undefined) return perm.allowed;
      return true;
    }

    return perm ? perm.allowed : false;
  }

  canCreateEventInFolder(folderId: number): boolean {
    return !this.isSuspended && this.canCreateEvents && this.canDoInFolder(folderId, FolderFeature.createEvents);
  }

  canUploadReportInFolder(folderId: number): boolean {
    return !this.isSuspended && this.canUploadReports && this.canDoInFolder(folderId, FolderFeature.uploadReports);
  }

  canViewBudgetInFolder(folderId: number): boolean {
    return !this.isSuspended && this.canAccessScopedBudget && this.canDoInFolder(folderId, FolderFeature.viewBudget);
  }

  canRequestBudgetInFolder(folderId: number): boolean {
    return !this.isSuspended && this.canRequestBudget && this.canDoInFolder(folderId, FolderFeature.requestBudget);
  }

  get userFolderIds(): number[] {
    return this.isSuspended ? [] : this.userFolderMemberships.map((m) => m.folder_id);
  }
}
