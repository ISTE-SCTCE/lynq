import '../models/user_model.dart';
import '../models/folder_model.dart';
import 'constants.dart';

/// Central permission resolver.
/// Checks: role level → folder membership → folder permissions → post-specific rules.
class PermissionEngine {
  final UserModel user;
  final List<FolderMemberModel> userFolderMemberships;
  final Map<int, List<FolderPermissionModel>> folderPermissions;

  const PermissionEngine({
    required this.user,
    this.userFolderMemberships = const [],
    this.folderPermissions = const {},
  });

  AppRole get role => AppRole.fromString(user.role);

  /// Check user suspension status
  bool get isSuspended {
    if (user.status == 'suspended') return true;
    final until = user.suspendedUntil;
    if (until != null && until.isAfter(DateTime.now())) return true;
    return false;
  }

  // ── Tier-based getters ──

  bool get isTier1 => !isSuspended && (role == AppRole.chairman || role == AppRole.viceChairman);
  bool get isTier2 => !isSuspended && role == AppRole.coreExeccom;
  bool get isTier3 => !isSuspended && role == AppRole.forumExeccom;
  bool get isTier4 => !isSuspended && role == AppRole.panel;
  bool get isTier5 => !isSuspended && role == AppRole.restricted;
  bool get isTier6 => !isSuspended && role == AppRole.member;

  bool get isAtLeastTier1 => !isSuspended && role >= AppRole.viceChairman;
  bool get isAtLeastTier2 => !isSuspended && role >= AppRole.coreExeccom;
  bool get isAtLeastTier3 => !isSuspended && role >= AppRole.forumExeccom;
  bool get isAtLeastTier4 => !isSuspended && role >= AppRole.panel;

  /// Effective Tier 1 (includes Tier 2 with Chairman's Sudo grant)
  bool get isEffectivelyTier1 => !isSuspended && (isTier1 || (isTier2 && user.isSudo));

  // ── Action permissions ──

  bool get canAddMembers => !isSuspended && _isCommitteeLead;
  bool get canRemoveMembers => !isSuspended && isAtLeastTier1;
  bool get canEditMembers => !isSuspended && isTier1;
  bool get canAssignRoles => !isSuspended && isAtLeastTier1;
  bool get canManageFolders => !isSuspended && isAtLeastTier1;
  bool get canManageGlobalPermissions => !isSuspended && role == AppRole.chairman;
  bool get canManageFolderPermissions => !isSuspended && isAtLeastTier1;
  bool get canManagePermissions => !isSuspended && (canManageGlobalPermissions || canManageFolderPermissions);

  /// Committee leadership: Tier 1 & 2 are always leads.
  /// Forum Execom (Tier 3) only if they hold Chair or Secretary position.
  bool get _isCommitteeLead {
    if (isSuspended) return false;
    if (isAtLeastTier2) return true; // Covers Tier 1 + Tier 2
    if (isTier3) {
      final p = user.post?.toLowerCase() ?? '';
      return p == 'chair' || p == 'chairman' || p == 'secretary';
    }
    return false;
  }

  /// Top 4 roles with full administrative and budget authority:
  /// Chairman, Vice Chairman, Secretary, Treasurer.
  bool get _isTop4 {
    if (isSuspended) return false;
    if (isTier1) return true;
    if (isTier2) {
      final p = user.post?.toLowerCase() ?? '';
      return p == 'secretary' || p == 'treasurer';
    }
    return false;
  }

  /// Can manage members within a specific folder/forum
  bool canManageMembersInFolder(int folderId) {
    if (isSuspended) return false;
    if (isAtLeastTier1) return true;
    // Core members assigned to a folder can manage its members
    if (isAtLeastTier2 && isMemberOfFolder(folderId)) return true;
    
    // Wire up manageAll bypass
    if (canDoInFolder(folderId, FolderFeature.manageAll)) return true;

    // Forum Chairs/Heads can manage their own members (exact folder-role match)
    final fRole = folderRoleIn(folderId)?.toLowerCase() ?? '';
    return fRole == 'chair' || fRole == 'head';
  }

  /// Is a specific feature allowed globally (folder_id: 0)
  bool isFeatureEnabledGlobally(String feature) {
    if (isSuspended) return false;
    final perms = folderPermissions[0] ?? [];
    final perm = perms.where((p) => p.feature == feature).firstOrNull;
    return perm?.allowed ?? false;
  }

  // ── Mandated Permissions ──

  /// 1. Event creation privileges restricted exclusively to Tier 3 and above.
  bool get canCreateEvents => !isSuspended && isAtLeastTier3;

  /// 2. Report viewing access is limited to Tier 2 and all tiers above.
  bool get canReadReports => !isSuspended && (isAtLeastTier2 || (isMemberOfFolder(0) && isFeatureEnabledGlobally(FolderFeature.viewReports)));

  bool get canUploadReports => !isSuspended && isAtLeastTier4;

  /// 5. Full organizational budget viewing access is restricted to Tier 2 and above.
  bool get canViewTotalBudget => !isSuspended && (isAtLeastTier2 || (isMemberOfFolder(0) && isFeatureEnabledGlobally(FolderFeature.viewTotalBudget)));

  /// 6. Tier 3 (Forum-Execom) may view their forum budget. No activation gate.
  bool get canAccessScopedBudget => !isSuspended && isAtLeastTier3;

  /// Anyone EXCEPT restricted members can view the org member list (basic details only).
  bool get canViewMembers => !isSuspended && role != AppRole.restricted;

  // ── Legacy/Other Access ──
  bool get isPanel => !isSuspended && isTier4;
  bool get canRequestBudget => !isSuspended && isAtLeastTier3;
  bool get canManageBudget => !isSuspended && _isTop4;

  bool get canViewInternalAnnouncements => !isSuspended && isAtLeastTier3;
  bool get canManageAnnouncements => !isSuspended && isAtLeastTier2;
  bool get canOverride => !isSuspended && role == AppRole.chairman;
  bool get canAccessChat => !isSuspended && isAtLeastTier4;

  /// Budget approve/reject: only effectively Tier 1
  /// or Tier 2 with specific posts (Treasurer, Sub-Treasurer)
  bool get canApproveBudget {
    if (isSuspended) return false;
    if (isEffectivelyTier1) return true;
    if (isTier2) return BudgetAuthorityPosts.hasBudgetAuthority(user.post);
    return false;
  }

  // ── Folder-scoped permissions ──

  /// Is this user a member of a specific folder?
  bool isMemberOfFolder(int folderId) =>
      !isSuspended && userFolderMemberships.any((m) => m.folderId == folderId);

  /// Get the user's role within a folder
  String? folderRoleIn(int folderId) {
    if (isSuspended) return null;
    final membership = userFolderMemberships
        .where((m) => m.folderId == folderId)
        .firstOrNull;
    return membership?.folderRole;
  }

  /// Check if a folder feature is allowed for this user
  bool canDoInFolder(int folderId, String feature) {
    if (isSuspended) return false;
    // Effective Tier 1 can do everything in any folder
    if (isEffectivelyTier1) return true;

    // Check folder-specific permission toggle
    final perms = folderPermissions[folderId] ?? [];

    // If checking a regular feature, see if they have global manageAll allowed
    if (feature != FolderFeature.manageAll) {
      final manageAllPerm = perms.where((p) => p.feature == FolderFeature.manageAll).firstOrNull;
      if (manageAllPerm?.allowed ?? false) {
        return true;
      }
    }

    final perm = perms.where((p) => p.feature == feature).firstOrNull;
    
    // Option A: Default-allow inside folder for Tier 2/3 if not explicitly restricted
    if (isAtLeastTier2) {
      if (perm != null) return perm.allowed;
      return true; 
    }

    if (!isMemberOfFolder(folderId)) return false;

    if (isAtLeastTier3) {
      if (perm != null) return perm.allowed;
      return true;
    }

    return perm?.allowed ?? false;
  }

  /// Can create events in a specific folder
  bool canCreateEventInFolder(int folderId) =>
      !isSuspended && canCreateEvents && canDoInFolder(folderId, FolderFeature.createEvents);

  /// Can upload reports in a specific folder
  bool canUploadReportInFolder(int folderId) =>
      !isSuspended && canUploadReports && canDoInFolder(folderId, FolderFeature.uploadReports);

  /// Can view budget in a specific folder
  bool canViewBudgetInFolder(int folderId) =>
      !isSuspended && canAccessScopedBudget && canDoInFolder(folderId, FolderFeature.viewBudget);

  /// Can request budget in a specific folder (wired up)
  bool canRequestBudgetInFolder(int folderId) =>
      !isSuspended && canRequestBudget && canDoInFolder(folderId, FolderFeature.requestBudget);

  /// Get list of folder IDs this user belongs to
  List<int> get userFolderIds =>
      isSuspended ? [] : userFolderMemberships.map((m) => m.folderId).toList();
}
