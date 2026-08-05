import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

export function ProtectedRoute({ children }) {
  const { isAuthenticated, isLoading } = useAuth();
  const location = useLocation();
  if (isLoading) return (
    <div className="min-h-screen flex items-center justify-center bg-[#EBF3FC]">
      <div className="w-10 h-10 border-4 border-[#5F85A2] border-t-transparent rounded-full animate-spin" />
    </div>
  );
  if (!isAuthenticated) return <Navigate to="/login" state={{ from: location }} replace />;
  return children;
}

export function PublicRoute({ children }) {
  const { isAuthenticated, isLoading } = useAuth();
  if (isLoading) return (
    <div className="min-h-screen flex items-center justify-center bg-[#EBF3FC]">
      <div className="w-10 h-10 border-4 border-[#5F85A2] border-t-transparent rounded-full animate-spin" />
    </div>
  );
  if (isAuthenticated) return <Navigate to="/home" replace />;
  return children;
}
