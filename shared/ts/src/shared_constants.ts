export const SharedConstants = {
  appName: 'Lynq',
  organizationName: 'ISTE SCTCE',
  apiVersion: 'v1',
};

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
  
  if (normalized === 'restricted') return AppRole.restricted;
  if (normalized === 'panel') return AppRole.panel;
  if (normalized === 'chairman' || normalized === 'chair') return AppRole.chairman;
  if (normalized === 'vice_chairman' || normalized === 'vice_chair') return AppRole.viceChairman;
  
  // Check for forum roles FIRST to prevent "SWAS Chairman" from becoming Tier 1/2
  if (normalized.includes('swas') || 
      normalized.includes('exis') || 
      normalized.includes('genesis') || 
      normalized.includes('torq') || 
      normalized.includes('bits') ||
      normalized.includes('talk') ||
      normalized.includes('nexus') ||
      normalized.includes('forum_execcom') ||
      normalized.includes('forum_secretary')) {
    return AppRole.forumExeccom;
  }
  
  // Core Execom roles
  if (normalized.includes('core') || 
      normalized.includes('head') || 
      normalized.includes('secretary') || 
      normalized.includes('treasurer') ||
      normalized.includes('webmaster') ||
      normalized.includes('sponsorship') ||
      normalized.includes('logistics') ||
      normalized.includes('hospitality') ||
      normalized.includes('public_relations') ||
      normalized.includes('strategist') ||
      normalized.includes('media') ||
      normalized.includes('design') ||
      normalized.includes('creative') ||
      normalized.includes('technical') ||
      normalized.includes('ideation') ||
      normalized.includes('marketing') ||
      normalized.includes('coordination')) {
    return AppRole.coreExeccom;
  }
  
  // Fallback for general forum execom
  if (normalized.includes('execcom') || 
      normalized.includes('execom') || 
      normalized.includes('coordinator')) {
    return AppRole.forumExeccom;
  }

  return AppRole.member;
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
  static createEvents = 'create_events';
  static uploadReports = 'upload_reports';
  static viewBudget = 'view_budget';
  static requestBudget = 'request_budget';
  static viewTotalBudget = 'view_total_budget';
  static manageAll = 'manage_all';
  static viewReports = 'view_reports';

  static all = [
    FolderFeature.createEvents,
    FolderFeature.uploadReports,
    FolderFeature.viewBudget,
    FolderFeature.requestBudget,
    FolderFeature.viewTotalBudget,
    FolderFeature.viewReports,
    FolderFeature.manageAll,
  ];

  static label(feature: string): string {
    switch (feature) {
      case FolderFeature.createEvents:
        return 'Create/Edit Events';
      case FolderFeature.uploadReports:
        return 'Upload Reports';
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
