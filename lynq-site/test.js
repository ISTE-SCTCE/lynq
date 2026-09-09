import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://vwxbgklgkcbwrvtwypfs.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ3eGJna2xna2Nid3J2dHd5cGZzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5OTkxNjIsImV4cCI6MjA4NzU3NTE2Mn0.DcBZJcNw3V0cCmzyZcipfQLYxq7j_PzbEc2UOM3z9FA';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function test() {
  const { data: authData } = await supabase.auth.signInWithPassword({
    email: 'siyavarghese29@gmail.com',
    password: 'isteISTE2026'
  });
  
  // Try selecting from folders
  const { data: fData, error: fError } = await supabase.from('folders').select('*').limit(1);
  console.log("folders:", fError ? fError.message : "Exists");
  
  // Try selecting from execom_members
  const { data: mData, error: mError } = await supabase.from('execom_members').select('*').limit(1);
  console.log("execom_members:", mError ? mError.message : "Exists");

  // Try selecting from execom_permissions
  const { data: pData, error: pError } = await supabase.from('execom_permissions').select('*').limit(1);
  console.log("execom_permissions:", pError ? pError.message : "Exists");
}

test();
