import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://vwxbgklgkcbwrvtwypfs.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ3eGJna2xna2Nid3J2dHd5cGZzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5OTkxNjIsImV4cCI6MjA4NzU3NTE2Mn0.DcBZJcNw3V0cCmzyZcipfQLYxq7j_PzbEc2UOM3z9FA';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
