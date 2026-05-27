export enum AppRole {
  member = 0,
  restricted = 1,
  panel = 2,
  forumExeccom = 3,
  coreExeccom = 4,
  viceChairman = 5,
  chairman = 6,
}

export const AppRoleLabels: Record<AppRole, string> = {
  [AppRole.member]: 'General Members',
  [AppRole.restricted]: 'Restricted',
  [AppRole.panel]: 'Panel',
  [AppRole.forumExeccom]: 'Forum-Execom',
  [AppRole.coreExeccom]: 'Core Execom',
  [AppRole.viceChairman]: 'Vice Chairman',
  [AppRole.chairman]: 'Chairman',
};

export function appRoleFromString(s?: string): AppRole {
  if (!s) return AppRole.member;
  const normalized = s.toLowerCase().replace(/ /g, '_').replace(/-/g, '_');
  switch (normalized) {
    case 'chairman':
      return AppRole.chairman;
    case 'vice_chairman':
      return AppRole.viceChairman;
    case 'core_execcom':
    case 'core_execom':
      return AppRole.coreExeccom;
    case 'forum_execcom':
    case 'forum_execom':
    case 'execcom':
      return AppRole.forumExeccom;
    case 'panel':
      return AppRole.panel;
    case 'restricted':
      return AppRole.restricted;
    default:
      return AppRole.member;
  }
}

export function appRoleToDbString(role: AppRole): string {
  switch (role) {
    case AppRole.chairman:
      return 'chairman';
    case AppRole.viceChairman:
      return 'vice_chairman';
    case AppRole.coreExeccom:
      return 'core_execcom';
    case AppRole.forumExeccom:
      return 'forum_execcom';
    case AppRole.panel:
      return 'panel';
    case AppRole.restricted:
      return 'restricted';
    default:
      return 'member';
  }
}

export class FolderFeature {
  static viewEvents = 'view_events';
  static createEvents = 'create_events';
  static uploadReports = 'upload_reports';
  static viewMembers = 'view_members';
  static manageMembers = 'manage_members';
  static viewBudget = 'view_budget';
  static requestBudget = 'request_budget';
  static viewTotalBudget = 'view_total_budget';
  static manageAll = 'manage_all';
  static viewReports = 'view_reports';

  static all = [
    FolderFeature.viewEvents,
    FolderFeature.createEvents,
    FolderFeature.uploadReports,
    FolderFeature.viewMembers,
    FolderFeature.manageMembers,
    FolderFeature.viewBudget,
    FolderFeature.requestBudget,
    FolderFeature.viewTotalBudget,
    FolderFeature.viewReports,
    FolderFeature.manageAll,
  ];

  static label(feature: string): string {
    switch (feature) {
      case FolderFeature.viewEvents:
        return 'View Events';
      case FolderFeature.createEvents:
        return 'Create/Edit Events';
      case FolderFeature.uploadReports:
        return 'Upload Reports';
      case FolderFeature.viewMembers:
        return 'View Members';
      case FolderFeature.manageMembers:
        return 'Manage Members';
      case FolderFeature.viewBudget:
        return 'View Forum Budget';
      case FolderFeature.requestBudget:
        return 'Request Budget';
      case FolderFeature.viewTotalBudget:
        return 'View Total ISTE Budget';
      case FolderFeature.viewReports:
        return 'View All Reports';
      case FolderFeature.manageAll:
        return 'Full Management Access';
      default:
        return feature;
    }
  }
}

export class BudgetAuthorityPosts {
  static posts = ['Treasurer', 'Sub-Treasurer', 'Chairman', 'Vice Chairman'];

  static hasBudgetAuthority(post?: string): boolean {
    if (!post) return false;
    const lower = post.toLowerCase();
    return this.posts.some((p) => lower === p.toLowerCase());
  }
}
