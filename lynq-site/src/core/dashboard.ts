import { supabase } from './supabase-client';

export interface DashboardData {
  events: { id: string; title: string; date: string }[];
  tasks: { id: string; title: string; deadline: string | null }[];
  teams: { id: number; name: string }[];
  counts: { members: number | null; events: number | null; tasks: number | null };
  errors: string[];
}

// All requests use the signed-in client and existing database policies.
// UI permissions are navigation hints, never a replacement for database authorization.
export async function loadDashboard(userId: string, allTeams: boolean, signal: AbortSignal): Promise<DashboardData> {
  const now = new Date();
  const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  const teamsRequest = async () => {
    let query = supabase.from('folders').select('id, name').order('name').limit(4);
    if (!allTeams) {
      const memberships = await supabase.from('folder_members').select('execom_id')
        .eq('user_id', userId).abortSignal(signal);
      if (memberships.error) return { data: null, error: memberships.error };
      const ids = [...new Set((memberships.data ?? []).map(row => row.execom_id))];
      if (!ids.length) return { data: [], error: null };
      query = query.in('id', ids);
    }
    return query.abortSignal(signal);
  };
  const [events, tasks, members, eventCount, teams] = await Promise.all([
    supabase.from('events').select('id, title, date').gte('date', today).order('date').limit(4).abortSignal(signal),
    supabase.from('tasks').select('id, title, deadline', { count: 'exact' })
      .neq('status', 'completed').contains('assigned_to', [userId])
      .order('deadline', { nullsFirst: false }).limit(4).abortSignal(signal),
    supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('is_iste_member', true).abortSignal(signal),
    supabase.from('events').select('id', { count: 'exact', head: true }).abortSignal(signal),
    teamsRequest(),
  ]);
  return {
    events: events.data ?? [], tasks: tasks.data ?? [], teams: teams.data ?? [],
    counts: {
      members: members.error ? null : members.count,
      events: eventCount.error ? null : eventCount.count,
      tasks: tasks.error ? null : tasks.count,
    },
    errors: [
      events.error && 'Upcoming events', tasks.error && 'Your tasks',
      members.error && 'Member count', eventCount.error && 'Event count', teams.error && 'Teams',
    ].filter((value): value is string => Boolean(value)),
  };
}
