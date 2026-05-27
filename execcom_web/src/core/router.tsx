import React from 'react';
import { BrowserRouter, Routes, Route, Navigate, Outlet } from 'react-router-dom';
import { useAuth } from './auth-provider';
import { AppRole } from './constants';

// Skeletons for screens (implemented incrementally in core phases)
import { SplashScreen } from '../screens/splash/SplashScreen';
import { LoginScreen } from '../screens/auth/LoginScreen';
import { HomeScreen } from '../screens/home/HomeScreen';
import { ExecomListScreen } from '../screens/execom/ExecomListScreen';
import { ExecomDetailScreen } from '../screens/execom/ExecomDetailScreen';
import { ExecomPermissionsScreen } from '../screens/execom/ExecomPermissionsScreen';
import { MemberListScreen } from '../screens/members/MemberListScreen';
import { MemberDetailScreen } from '../screens/members/MemberDetailScreen';
import { AddMemberScreen } from '../screens/members/AddMemberScreen';
import { EventListScreen } from '../screens/events/EventListScreen';
import { EventFormScreen } from '../screens/events/EventFormScreen';
import { BudgetOverviewScreen } from '../screens/budget/BudgetOverviewScreen';
import { BudgetRequestScreen } from '../screens/budget/BudgetRequestScreen';
import { ReportListScreen } from '../screens/reports/ReportListScreen';
import { ReportUploadScreen } from '../screens/reports/ReportUploadScreen';
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

  if (isLoading || isShowingSplash) {
    return <SplashScreen />;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return (
    <div className="app-container">
      <Outlet />
    </div>
  );
};

interface GuardProps {
  check: (perms: any, role: AppRole) => boolean;
}

const PermissionGuard: React.FC<GuardProps> = ({ check }) => {
  const { permissions, currentUser } = useAuth();
  
  if (!permissions || !currentUser) {
    return <Navigate to="/home" replace />;
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

          {/* Execom */}
          <Route path="/execom" element={<ExecomListScreen />} />
          <Route path="/execom/:id" element={<ExecomDetailScreen />} />
          <Route element={<PermissionGuard check={(p) => p.canManageExecomPermissions} />}>
            <Route path="/execom/:id/permissions" element={<ExecomPermissionsScreen />} />
          </Route>

          {/* Members */}
          <Route element={<PermissionGuard check={(_, role) => role >= AppRole.forumExeccom} />}>
            <Route path="/members" element={<MemberListScreen />} />
            <Route path="/members/:id" element={<MemberDetailScreen />} />
          </Route>
          <Route element={<PermissionGuard check={(_, role) => role >= AppRole.forumExeccom} />}>
            <Route path="/members-enroll" element={<AddMemberScreen />} />
          </Route>

          {/* Events */}
          <Route path="/events" element={<EventListScreen />} />
          <Route path="/events/create" element={<EventFormScreen />} />

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
        </Route>

        {/* Fallback */}
        <Route path="*" element={<Navigate to="/home" replace />} />
      </Routes>
    </BrowserRouter>
  );
};
