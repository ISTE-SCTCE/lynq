import React from 'react';
import { BrowserRouter, Routes, Route, Navigate, Outlet, useLocation } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { useAuth } from './auth-provider';
import { AppRole } from './constants';

// Skeletons for screens (implemented incrementally in core phases)
import { SplashScreen } from '../screens/splash/SplashScreen';
import { LoginScreen } from '../screens/auth/LoginScreen';
import { HomeScreen } from '../screens/home/HomeScreen';
import { FolderListScreen } from '../screens/folders/FolderListScreen';
import { FolderDetailScreen } from '../screens/folders/FolderDetailScreen';
import { FolderPermissionsScreen } from '../screens/folders/FolderPermissionsScreen';
import { MemberListScreen } from '../screens/members/MemberListScreen';
import { MemberDetailScreen } from '../screens/members/MemberDetailScreen';
import { AddMemberScreen } from '../screens/members/AddMemberScreen';
import { ExecomListScreen } from '../screens/members/ExecomListScreen';
import { EventListScreen } from '../screens/events/EventListScreen';
import { EventFormScreen } from '../screens/events/EventFormScreen';
import { CertificateIssuanceScreen } from '../screens/events/CertificateIssuanceScreen';
import { AttendanceReportScreen } from '../screens/events/AttendanceReportScreen';
import { BudgetOverviewScreen } from '../screens/budget/BudgetOverviewScreen';
import { BudgetRequestScreen } from '../screens/budget/BudgetRequestScreen';
import { ReportListScreen } from '../screens/reports/ReportListScreen';
import { ReportUploadScreen } from '../screens/reports/ReportUploadScreen';
import MentronDashboardScreen from '../screens/mentron/MentronDashboardScreen';
import { AnnouncementScreen } from '../screens/announcements/AnnouncementScreen';
import { ChatListScreen } from '../screens/chat/ChatListScreen';
import { ChatScreen } from '../screens/chat/ChatScreen';
import { SettingsScreen } from '../screens/settings/SettingsScreen';
import { PermissionManagerScreen } from '../screens/settings/PermissionManagerScreen';
import { MoreScreen } from '../screens/more/MoreScreen';
import { TaskListScreen } from '../screens/tasks/TaskListScreen';
import { TaskCreateScreen } from '../screens/tasks/TaskCreateScreen';
import { TaskDetailScreen } from '../screens/tasks/TaskDetailScreen';
import { SubtaskDetailScreen } from '../screens/tasks/SubtaskDetailScreen';
import { QrScannerScreen } from '../screens/scan/QrScannerScreen';
import { RegistrationQueueScreen } from '../screens/registrations/RegistrationQueueScreen';

const ProtectedLayout: React.FC = () => {
  const { isAuthenticated, isLoading, isShowingSplash } = useAuth();
  const location = useLocation();

  if (isLoading || isShowingSplash) {
    return <SplashScreen />;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return (
    <div className="app-container" style={{ position: 'relative', width: '100%', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={location.pathname}
          initial={{ opacity: 0, y: 10, scale: 0.995 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -10, scale: 0.995 }}
          transition={{ type: 'spring', stiffness: 450, damping: 30 }}
          style={{ width: '100%', display: 'flex', flexDirection: 'column', flex: 1 }}
        >
          <Outlet />
        </motion.div>
      </AnimatePresence>
    </div>
  );
};

interface GuardProps {
  check: (perms: any, role: AppRole) => boolean;
}

const PermissionGuard: React.FC<GuardProps> = ({ check }) => {
  const { permissions, currentUser, isLoading } = useAuth();
  
  // Wait for auth to fully resolve before making access decisions.
  // Redirecting while loading causes false bounces to /home for valid users.
  if (isLoading || !permissions || !currentUser) {
    return null;
  }

  const role = permissions.role;
  const isAllowed = check(permissions, role);

  if (!isAllowed) {
    return <Navigate to="/home" replace />;
  }

  return <Outlet />;
};

export const AppRouter: React.FC = () => {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/splash" element={<SplashScreen />} />
        <Route path="/login" element={<LoginScreen />} />
        
        {/* Protected Routes */}
        <Route element={<ProtectedLayout />}>
          <Route path="/" element={<Navigate to="/home" replace />} />
          <Route path="/home" element={<HomeScreen />} />
          <Route path="/more" element={<MoreScreen />} />

          {/* Folders */}
          <Route path="/folders" element={<FolderListScreen />} />
          <Route path="/folders/:id" element={<FolderDetailScreen />} />
          <Route element={<PermissionGuard check={(p) => p.canManageFolderPermissions} />}>
            <Route path="/folders/:id/permissions" element={<FolderPermissionsScreen />} />
          </Route>

          {/* Members */}
          <Route element={<PermissionGuard check={(_, role) => role >= AppRole.forumExeccom} />}>
            <Route path="/members" element={<MemberListScreen />} />
            <Route path="/members/:id" element={<MemberDetailScreen />} />
            <Route path="/members-enroll" element={<AddMemberScreen />} />
            <Route path="/execom_list" element={<ExecomListScreen />} />
          </Route>

          {/* Events */}
          <Route path="/events" element={<EventListScreen />} />
          <Route path="/events/create" element={<EventFormScreen />} />
          <Route path="/events/:id/publish" element={<CertificateIssuanceScreen />} />
          <Route path="/events/:id/attendance" element={<AttendanceReportScreen />} />

          {/* Budget */}
          <Route element={<PermissionGuard check={(_, role) => role >= AppRole.forumExeccom} />}>
            <Route path="/budget" element={<BudgetOverviewScreen />} />
            <Route path="/budget/request" element={<BudgetRequestScreen />} />
          </Route>

          {/* Reports */}
          <Route path="/reports" element={<ReportListScreen />} />
          <Route element={<PermissionGuard check={(p) => p.canUploadReports} />}>
            <Route path="/reports/upload" element={<ReportUploadScreen />} />
          </Route>

          {/* Announcements */}
          <Route path="/announcements" element={<AnnouncementScreen />} />

          {/* Chat */}
          <Route element={<PermissionGuard check={(p) => p.canAccessChat} />}>
            <Route path="/chat" element={<ChatListScreen />} />
            <Route path="/chat/:userId" element={<ChatScreen />} />
          </Route>

          {/* Settings */}
          <Route path="/settings" element={<SettingsScreen />} />
          <Route element={<PermissionGuard check={(p) => p.canManageGlobalPermissions} />}>
            <Route path="/settings/permissions" element={<PermissionManagerScreen />} />
          </Route>

          {/* Tasks */}
          <Route path="/tasks" element={<TaskListScreen />} />
          <Route path="/tasks/create" element={<TaskCreateScreen />} />
          <Route path="/tasks/:id" element={<TaskDetailScreen />} />
          <Route path="/tasks/:taskId/subtasks/create" element={<TaskCreateScreen />} />
          <Route path="/tasks/:taskId/subtasks/:subtaskId" element={<SubtaskDetailScreen />} />

          {/* QR Scan */}
          <Route path="/scan" element={<QrScannerScreen />} />

          {/* Registration Queue */}
          <Route element={<PermissionGuard check={(_, role) => role >= AppRole.viceChairman} />}>
            <Route path="/registrations" element={<RegistrationQueueScreen />} />
          </Route>
          {/* Mentron Analytics */}
          <Route path="/mentron" element={<MentronDashboardScreen />} />
        </Route>

        {/* Fallback */}
        <Route path="*" element={<Navigate to="/home" replace />} />
      </Routes>
    </BrowserRouter>
  );
};
