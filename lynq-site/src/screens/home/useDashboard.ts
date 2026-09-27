import { useEffect, useState, useCallback } from 'react';
import { loadDashboard, type DashboardData } from '../../core/dashboard';

export function useDashboard(userId: string | undefined, allTeams: boolean) {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [updated, setUpdated] = useState<Date | null>(null);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const refresh = useCallback(() => setRevision(value => value + 1), []);
  useEffect(() => {
    setData(null);
    setUpdated(null);
  }, [userId, allTeams]);
  useEffect(() => {
    if (!userId) return;
    let disposed = false;
    let active: AbortController | null = null;
    const fetchData = async () => {
      if (active || document.hidden) return;
      active = new AbortController();
      const timeout = window.setTimeout(() => active?.abort(), 15000);
      setLoading(true);
      try {
        const result = await loadDashboard(userId, allTeams, active.signal);
        if (disposed) return;
        setData(result);
        setError(result.errors.length ? `Could not load: ${result.errors.join(', ')}. Try refreshing.` : '');
        if (!result.errors.length) setUpdated(new Date());
      } catch {
        if (!disposed) setError('The workspace could not connect. Please try again.');
      } finally {
        clearTimeout(timeout);
        active = null;
        if (!disposed) setLoading(false);
      }
    };
    void fetchData();
    const visible = () => { if (!document.hidden) void fetchData(); };
    window.addEventListener('focus', visible);
    window.addEventListener('online', visible);
    document.addEventListener('visibilitychange', visible);
    const timer = window.setInterval(visible, 60000);
    return () => {
      disposed = true;
      active?.abort();
      clearInterval(timer);
      window.removeEventListener('focus', visible);
      window.removeEventListener('online', visible);
      document.removeEventListener('visibilitychange', visible);
    };
  }, [userId, allTeams, revision]);
  return { data, loading, updated, error, refresh };
}
