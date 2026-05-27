import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://vwxbgklgkcbwrvtwypfs.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ3eGJna2xna2Nid3J2dHd5cGZzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5OTkxNjIsImV4cCI6MjA4NzU3NTE2Mn0.DcBZJcNw3V0cCmzyZcipfQLYxq7j_PzbEc2UOM3z9FA';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function test() {
  const email = 'aadithyanrs9e@gmail.com';
  const password = 'isteISTE2026';

  console.log('Signing in...');
  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({ email, password });
  if (authError) {
    console.error('Sign-in failed:', authError);
    return;
  }
  const userId = authData.user.id;
  console.log('Sign-in successful. User ID:', userId);
  
  console.log('\nTesting users query...');
  const profileRes = await supabase.from('users').select().eq('id', userId).single();
  console.log('Profile result:', JSON.stringify(profileRes, null, 2));

  console.log('\nTesting execom_members query...');
  const membershipsRes = await supabase.from('execom_members')
    .select('*, users:users(id, name, email, role, post)')
    .eq('user_id', userId);
  console.log('Memberships result:', JSON.stringify(membershipsRes, null, 2));

  console.log('\nTesting execom_permissions query...');
  const permQuery = await supabase.from('execom_permissions').select().eq('execom_id', 0);
  console.log('Permissions result:', JSON.stringify(permQuery, null, 2));
}

test().catch(console.error);
