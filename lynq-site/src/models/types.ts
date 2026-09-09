export interface UserModel {
  id: string;
  name: string;
  email: string;
  role: string;
  post?: string;
  phone?: string;
  roll_number?: string;
  branch?: string;
  membership_plan?: string;
  membership_date?: string;
  forum?: string;
  expiry_date?: string;
  is_primary_chairman: boolean;
  is_sudo: boolean;
  is_budget_activated: boolean;
  permissions: Record<string, any>;
  last_seen?: string;
  created_at?: string;
  status?: string;
  suspended_until?: string;
}

export interface FolderModel {
  id: number;
  name: string;
  created_at?: string;
}

export interface FolderMemberModel {
  id: number;
  folder_id: number;
  user_id: string;
  folder_role: string;
  created_at?: string;
  // Included from join
  users?: {
    id: string;
    name: string;
    email: string;
    role: string;
    post?: string;
  };
}

export interface FolderPermissionModel {
  id: number;
  folder_id: number;
  feature: string;
  allowed: boolean;
  created_at?: string;
}

export interface EventModel {
  id: number;
  title: string;
  date?: string;
  description?: string;
  type?: string;
  folder_id?: number;
  created_by?: string;
  created_at?: string;
  member_price: number;
  non_member_price: number;
  is_paid: boolean;
  poster_url?: string;
  location?: string;
  allowed_roles?: string[];
  num_days?: number;
  attendance_finalized?: boolean;
  category?: string;
  coordinator_name?: string;
  chair_name?: string;
  template_url?: string;
  certificate_image_url?: string;
  certificate_template_type?: string;
}

export interface AnnouncementModel {
  id: number;
  title: string;
  content?: string;
  created_by?: string;
  visibility: 'public' | 'internal';
  created_at?: string;
}

export interface BudgetRequestModel {
  id: number;
  folder_id: number;
  requested_by: string;
  amount: number;
  reason?: string;
  proposal_url?: string;
  status: 'pending' | 'approved' | 'rejected';
  reviewed_by?: string;
  reviewed_at?: string;
  created_at?: string;
}

export interface EventBudgetModel {
  id: number;
  event_name: string;
  budget_limit: number;
  actual_spent: number;
  date?: string;
}

export interface MessageModel {
  id: number;
  sender_id?: string;
  receiver_id?: string;
  content: string;
  conversation_id?: string;
  read_at?: string;
  timestamp?: string;
  folder_id?: number;
  sender?: string; // senderName in flutter JSON mapper
  is_deleted: boolean;
}

export interface ConversationModel {
  conversation_id: string;
  other_user_id?: string;
  folder_id?: number;
  folder_name?: string;
  last_message: string;
  last_message_time: string;
  unread_count: number;
  is_deleted: boolean;
  sender_name?: string;
  sender_id?: string;
}

export interface ReportModel {
  id: number;
  event_id?: number;
  uploaded_by?: string;
  folder_id?: number;
  title: string;
  content: string;
  file_url?: string;
  status: 'pending' | 'approved' | 'rejected';
  created_at?: string;
}

export interface TaskModel {
  id: number;
  title: string;
  description?: string;
  status: 'pending' | 'in_progress' | 'completed' | 'on_hold';
  priority: 'low' | 'medium' | 'high' | 'critical';
  assigned_to: string[]; // User IDs
  deadline?: string;
  created_by?: string;
  folder_id?: number;
  created_at?: string;
  parent_task_id?: number;
}

export interface FinancialIncomeModel {
  id: number;
  amount: number;
  transaction_date?: string;
  created_by?: string;
  event_id?: number;
  folder_id?: number;
  category: string;
  source?: string;
  description?: string;
  notes?: string;
  attachment_url?: string;
}

export interface FinancialLedgerModel {
  id: number;
  amount: number;
  transaction_date?: string;
  created_by?: string;
  event_id?: number;
  category_id?: number;
  folder_id?: number;
  type: string;
  source?: string;
  category: string;
  description?: string;
  notes?: string;
  attachment_url?: string;
}
