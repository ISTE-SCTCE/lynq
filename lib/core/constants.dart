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

  static AppRole fromString(String? s) {
    if (s == null) return AppRole.member;
    final normalized = s.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
    
    if (normalized == 'restricted') return AppRole.restricted;
    if (normalized == 'panel') return AppRole.panel;

    // Check for forum roles FIRST to prevent "SWAS Chairman" from becoming Tier 1/2
    if (normalized.contains('swas') || 
        normalized.contains('exis') || 
        normalized.contains('genesis') || 
        normalized.contains('torq') || 
        normalized.contains('bits') ||
        normalized.contains('talk') ||
        normalized.contains('nexus') ||
        normalized.contains('forum_execcom') ||
        normalized.contains('forum_secretary')) {
      return AppRole.forumExeccom;
    }
    
    if (normalized.contains('vice') && (normalized.contains('chair') || normalized.contains('chairman'))) {
      return AppRole.viceChairman;
    }
    if (normalized.contains('chair')) {
      return AppRole.chairman;
    }
    
    // Core Execom roles
    if (normalized.contains('core') || 
        normalized.contains('head') || 
        normalized.contains('secretary') || 
        normalized.contains('treasurer') ||
        normalized.contains('webmaster') ||
        normalized.contains('sponsorship') ||
        normalized.contains('logistics') ||
        normalized.contains('hospitality') ||
        normalized.contains('public_relations') ||
        normalized.contains('strategist') ||
        normalized.contains('media') ||
        normalized.contains('design') ||
        normalized.contains('creative') ||
        normalized.contains('technical') ||
        normalized.contains('ideation') ||
        normalized.contains('marketing')) {
      return AppRole.coreExeccom;
    }
    
    // Fallback for general forum execom
    if (normalized.contains('execcom') || 
        normalized.contains('execom') || 
        normalized.contains('coordinator')) {
      return AppRole.forumExeccom;
    }

    return AppRole.member;
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
