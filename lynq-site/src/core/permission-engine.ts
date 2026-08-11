import { AppRole, appRoleFromString, FolderFeature, BudgetAuthorityPosts } from './constants';
import { UserModel, FolderMemberModel, FolderPermissionModel } from '../models/types';

export class PermissionEngine {
  readonly user: UserModel;
  readonly userFolderMemberships: FolderMemberModel[];
  readonly folderPermissions: Record<number, FolderPermissionModel[]>;
  readonly globalPermissions: FolderPermissionModel[];

  constructor(
    user: UserModel,
    userFolderMemberships: FolderMemberModel[] = [],
    folderPermissions: Record<number, FolderPermissionModel[]> = {},
    globalPermissions: FolderPermissionModel[] = []
  ) {
    this.user = user;
    this.userFolderMemberships = userFolderMemberships;
    this.folderPermissions = folderPermissions;
    this.globalPermissions = globalPermissions;
  }

  get role(): AppRole {
    // BUGFIX: previously auto-promoted any user with 1+ folder memberships
    // to forumExeccom regardless of actual DB role. Removed — role must
    // come from profiles.role only. Matches Flutter engine exactly.
    return appRoleFromString(this.user.role);
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
    // BUGFIX: was reading folderPermissions[0], relying on a folder with
    // id=0 that never exists (folders PK is serial starting at 1) — this
    // always returned false. Now reads from a dedicated globalPermissions
    // map, populated separately from the global_feature_permissions table.
    if (this.isSuspended) return false;
    const perm = this.globalPermissions.find((p) => p.feature === feature);
    return perm ? perm.allowed : false;
  }

  // Feature limits
  get canCreateEvents(): boolean { return !this.isSuspended && this.isAtLeastTier3; }
  get canReadReports(): boolean { return !this.isSuspended && (this.isAtLeastTier2 || this.isFeatureEnabledGlobally(FolderFeature.viewReports)); }
  get canUploadReports(): boolean { return !this.isSuspended && this.isAtLeastTier4; }
  get canViewTotalBudget(): boolean { return !this.isSuspended && (this.isAtLeastTier2 || this.isFeatureEnabledGlobally(FolderFeature.viewTotalBudget)); }
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

    // BUGFIX: membership check now applies to ALL tiers uniformly, including
    // Tier2. Previously Tier2 skipped this entirely and could act in folders
    // they were never added to.
    if (!this.isMemberOfFolder(folderId)) return false;

    const perms = this.folderPermissions[folderId] || [];

    // If checking regular feature, see if manageAll is explicitly allowed
    if (feature !== FolderFeature.manageAll) {
      const manageAllPerm = perms.find((p) => p.feature === FolderFeature.manageAll);
      if (manageAllPerm?.allowed) {
        return true;
      }
    }

    const perm = perms.find((p) => p.feature === feature);

    // BUGFIX: default-deny when no explicit permission row exists (was
    // default-allow for Tier2/Tier3 — meant any un-configured feature was
    // silently open). Now every feature must be explicitly granted.
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
