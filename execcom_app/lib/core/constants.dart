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

  /// Parse from database string
  static AppRole fromString(String? s) {
    final normalized = s?.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
    return switch (normalized) {
      'chairman' => AppRole.chairman,
      'vice_chairman' => AppRole.viceChairman,
      'core_execcom' || 'core_execom' => AppRole.coreExeccom,
      'forum_execcom' || 'forum_execom' || 'execcom' => AppRole.forumExeccom,
      'panel' => AppRole.panel,
      'restricted' => AppRole.restricted,
      _ => AppRole.member,
    };
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
class ExecomFeature {
  static const String viewEvents = 'view_events';
  static const String createEvents = 'create_events';
  static const String uploadReports = 'upload_reports';
  static const String viewMembers = 'view_members';
  static const String manageMembers = 'manage_members';
  static const String viewBudget = 'view_budget';
  static const String requestBudget = 'request_budget';
  static const String viewTotalBudget = 'view_total_budget';
  static const String manageAll = 'manage_all';
  static const String viewReports = 'view_reports';

  static const List<String> all = [
    viewEvents,
    createEvents,
    uploadReports,
    viewMembers,
    manageMembers,
    viewBudget,
    requestBudget,
    viewTotalBudget,
    viewReports,
    manageAll,
  ];

  static String label(String feature) => switch (feature) {
    viewEvents => 'View Events',
    createEvents => 'Create/Edit Events',
    uploadReports => 'Upload Reports',
    viewMembers => 'View Members',
    manageMembers => 'Manage Members',
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
