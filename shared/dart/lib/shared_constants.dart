class SharedConstants {
  static const String appName = 'Lynq';
  static const String organizationName = 'ISTE SCTCE';
  static const String apiVersion = 'v1';
}

/// Role hierarchy for the Execcom Management System.
/// Higher level = more authority.
enum AppRole {
  member(0, 'General Members'),
  restricted(1, 'Restricted'),
  panel(2, 'Panel'),
  forumExeccom(3, 'Forum-Execom'),
  coreExeccom(4, 'Core Execom'),
  viceChairman(5, 'Vice Chairman'),
  chairman(6, 'Chairman');

  final int level;
  final String label;
  const AppRole(this.level, this.label);

  /// Parse role from the DB. Post-migration, profiles.role is a strict
  /// PostgreSQL ENUM (app_role) — always one of the 7 canonical values.
  /// BUGFIX: previously did fuzzy substring matching (`.contains('head')`,
  /// `.contains('design')` etc) against free-text role/post strings, which
  /// was necessary when role was unstructured text but is now fragile and
  /// unnecessary — a post literally containing "head" (e.g. "Overhead
  /// Logistics") could be misclassified as coreExeccom. Exact match only.
  static AppRole fromString(String? s) {
    if (s == null) return AppRole.member;
    final normalized = s.toLowerCase().trim().replaceAll(' ', '_').replaceAll('-', '_');
    return switch (normalized) {
      'chairman' => AppRole.chairman,
      'vice_chairman' => AppRole.viceChairman,
      'core_execcom' => AppRole.coreExeccom,
      'forum_execcom' => AppRole.forumExeccom,
      'panel' => AppRole.panel,
      'restricted' => AppRole.restricted,
      'member' => AppRole.member,
      _ => AppRole.member, // unknown value — safe default, never escalate
    };
  }

  /// Format a database role string for display, preserving forum names (e.g. exis_secretary -> EXIS Secretary)
  static String formatRoleDisplay(String? dbRole) {
    if (dbRole == null) return AppRole.member.label;
    final roleEnum = AppRole.fromString(dbRole);
    
    // For forum execom, try to format the actual dbRole string
    if (roleEnum == AppRole.forumExeccom && dbRole != 'forum_execcom') {
      final parts = dbRole.split(RegExp(r'[_-]'));
      if (parts.isNotEmpty) {
        final forums = ['exis', 'bits', 'torq', 'genesis', 'swas', 'talk', 'nexus'];
        if (forums.contains(parts[0].toLowerCase())) {
          final forumName = parts[0].toUpperCase();
          final position = parts.length > 1 
            ? parts.sublist(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1).toLowerCase()).join(' ')
            : 'Execom';
          return '$forumName $position';
        } else {
           return parts.map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1).toLowerCase()).join(' ');
        }
      }
    }
    
    return roleEnum.label;
  }

  /// Convert to database string
  String toDbString() => switch (this) {
    AppRole.chairman => 'chairman',
    AppRole.viceChairman => 'vice_chairman',
    AppRole.coreExeccom => 'core_execcom',
    AppRole.forumExeccom => 'forum_execcom',
    AppRole.panel => 'panel',
    AppRole.restricted => 'restricted',
    AppRole.member => 'member',
  };

  bool operator >=(AppRole other) => level >= other.level;
  bool operator >(AppRole other) => level > other.level;
  bool operator <(AppRole other) => level < other.level;
}

/// Permission features that can be toggled per folder
class FolderFeature {
  static const String createEvents = 'create_events';
  static const String uploadReports = 'upload_reports';
  static const String viewBudget = 'view_budget';
  static const String requestBudget = 'request_budget';
  static const String viewTotalBudget = 'view_total_budget';
  static const String manageAll = 'manage_all';
  static const String viewReports = 'view_reports';

  static const List<String> all = [
    createEvents,
    uploadReports,
    viewBudget,
    requestBudget,
    viewTotalBudget,
    viewReports,
    manageAll,
  ];

  static String label(String feature) => switch (feature) {
    createEvents => 'Create/Edit Events',
    uploadReports => 'Upload Reports',
    viewBudget => 'View Forum Budget',
    requestBudget => 'Request Budget',
    viewTotalBudget => 'View Total ISTE Budget',
    viewReports => 'View All Reports',
    manageAll => 'Full Management Access',
    _ => feature,
  };
}

/// Posts that have budget authority
class BudgetAuthorityPosts {
  static const List<String> posts = [
    'Treasurer',
    'Sub-Treasurer',
    'Chairman',
    'Vice Chairman',
  ];

  static bool hasBudgetAuthority(String? post) =>
      post != null && posts.any((p) => post.toLowerCase() == p.toLowerCase());
}
