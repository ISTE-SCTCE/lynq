import '../models/user_model.dart';
import '../models/execom_model.dart';
import 'constants.dart';

/// Central permission resolver.
/// Checks: role level → folder membership → folder permissions → post-specific rules.
class PermissionEngine {
  final UserModel user;
  final List<ExecomMemberModel> userExecomMemberships;
  final Map<int, List<ExecomPermissionModel>> folderPermissions;

  const PermissionEngine({
    required this.user,
    this.userExecomMemberships = const [],
    this.folderPermissions = const {},
  });

  AppRole get role => AppRole.fromString(user.role);

  // ── Tier-based getters ──

  bool get isTier1 => role == AppRole.chairman || role == AppRole.viceChairman;
  bool get isTier2 => role == AppRole.coreExeccom;
  bool get isTier3 => role == AppRole.forumExeccom;
  bool get isTier4 => role == AppRole.panel;
  bool get isTier5 => role == AppRole.restricted;
  bool get isTier6 => role == AppRole.member;

  bool get isAtLeastTier1 => role >= AppRole.viceChairman;
  bool get isAtLeastTier2 => role >= AppRole.coreExeccom;
  bool get isAtLeastTier3 => role >= AppRole.forumExeccom;
  bool get isAtLeastTier4 => role >= AppRole.panel;

  /// Effective Tier 1 (includes Tier 2 with Chairman's Sudo grant)
  bool get isEffectivelyTier1 => isTier1 || (isTier2 && user.isSudo);

  // ── Action permissions ──

  bool get canAddMembers => _isCommitteeLead;
  bool get canRemoveMembers => isAtLeastTier1;
  bool get canEditMembers => isTier1;
  bool get canAssignRoles => isAtLeastTier1;
  bool get canManageExecoms => isAtLeastTier1;
  bool get canManageGlobalPermissions => role == AppRole.chairman;
  bool get canManageExecomPermissions => isAtLeastTier1;
  bool get canManagePermissions => canManageGlobalPermissions || canManageExecomPermissions;

  /// Fundamental check for committee leadership (Heads, Chairs, Secretaries)
  bool get _isCommitteeLead {
    if (isAtLeastTier1) return true;
    if (isAtLeastTier2) return true;
    if (isTier3) {
      final p = user.post?.toLowerCase() ?? '';
      return p.contains('chair') || p.contains('secretary');
    }
    return false;
  }

  /// Top 4 roles with full administrative and budget authority:
  /// Chairman, Vice Chairman, Secretary, Treasurer.
  bool get _isTop4 {
    if (isTier1) return true;
    if (isTier2) {
      final p = user.post?.toLowerCase() ?? '';
      return p == 'secretary' || p == 'treasurer';
    }
    return false;
  }

  /// Can manage members within a specific folder/forum
  bool canManageMembersInExecom(int execomId) {
    if (isAtLeastTier1) return true;
    // Core members assigned to a folder can manage its members
    if (isAtLeastTier2 && isMemberOfExecom(execomId)) return true;
    // Forum Chairs/Heads can manage their own members
    final fRole = execomRoleIn(execomId)?.toLowerCase() ?? '';
    return fRole.contains('chair') || fRole.contains('head');
  }

  /// Is a specific feature allowed globally (execom_id: 0)
  bool isFeatureEnabledGlobally(String feature) {
    final perms = folderPermissions[0] ?? [];
    final perm = perms.where((p) => p.feature == feature).firstOrNull;
    return perm?.allowed ?? false;
  }

  // ── Mandated Permissions ──

  /// 1. Event creation privileges restricted exclusively to Tier 3 and above.
  bool get canCreateEvents => isAtLeastTier3;

  /// 2. Report viewing access is limited to Tier 2 and all tiers above.
  bool get canReadReports => isAtLeastTier2;

  bool get canUploadReports => isAtLeastTier4;

  /// 5. Full organizational budget viewing access is restricted to Tier 2 and above.
  bool get canViewTotalBudget => isAtLeastTier2;

  /// 6. Tier 3 (Forum-Execom) may view their forum budget. No activation gate.
  bool get canAccessScopedBudget => isAtLeastTier3;

  /// Anyone EXCEPT restricted members can view the org member list (basic details only).
  bool get canViewMembers => role != AppRole.restricted;

  // ── Legacy/Other Access ──
  bool get isPanel => isTier4;
  bool get canRequestBudget => isAtLeastTier3;
  bool get canManageBudget => _isTop4;

  bool get canViewInternalAnnouncements => isAtLeastTier3;
  bool get canManageAnnouncements => isAtLeastTier2;
  bool get canOverride => role == AppRole.chairman;
  bool get canAccessChat => isAtLeastTier4;

  /// Budget approve/reject: only effectively Tier 1
  /// or Tier 2 with specific posts (Treasurer, Sub-Treasurer)
  bool get canApproveBudget {
    if (isEffectivelyTier1) return true;
    if (isTier2) return BudgetAuthorityPosts.hasBudgetAuthority(user.post);
    return false;
  }

  // ── Execom-scoped permissions ──

  /// Is this user a member of a specific folder?
  bool isMemberOfExecom(int execomId) =>
      userExecomMemberships.any((m) => m.execomId == execomId);

  /// Get the user's role within a folder
  String? execomRoleIn(int execomId) {
    final membership = userExecomMemberships
        .where((m) => m.execomId == execomId)
        .firstOrNull;
    return membership?.execomRole;
  }

  /// Check if a folder feature is allowed for this user
  bool canDoInExecom(int execomId, String feature) {
    // Effective Tier 1 can do everything in any folder
    if (isEffectivelyTier1) return true;

    // Check folder-specific permission toggle
    final perms = folderPermissions[execomId] ?? [];
    final perm = perms.where((p) => p.feature == feature).firstOrNull;
    
    // If not a member, they can only see if it's publicly allowed for their role
    // Core members and above default to true everywhere if not explicitly restricted
    if (isAtLeastTier2) {
      if (perm != null) return perm.allowed;
      return true; 
    }

    if (!isMemberOfExecom(execomId)) return false;

    // Forum Execcom (Tier 3) default to true in their own folder if not explicitly restricted
    if (isAtLeastTier3) {
      if (perm != null) return perm.allowed;
      return true;
    }

    return perm?.allowed ?? false;
  }

  /// Can create events in a specific folder
  bool canCreateEventInExecom(int execomId) =>
      canCreateEvents && canDoInExecom(execomId, ExecomFeature.createEvents);

  /// Can upload reports in a specific folder
  bool canUploadReportInExecom(int execomId) =>
      canUploadReports && canDoInExecom(execomId, ExecomFeature.uploadReports);

  /// Can view budget in a specific folder
  bool canViewBudgetInExecom(int execomId) =>
      canAccessScopedBudget && canDoInExecom(execomId, ExecomFeature.viewBudget);

  /// Get list of folder IDs this user belongs to
  List<int> get userExecomIds =>
      userExecomMemberships.map((m) => m.execomId).toList();
}
