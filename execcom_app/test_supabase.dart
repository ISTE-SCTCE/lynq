import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://vwxbgklgkcbwrvtwypfs.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ3eGJna2xna2Nid3J2dHd5cGZzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5OTkxNjIsImV4cCI6MjA4NzU3NTE2Mn0.DcBZJcNw3V0cCmzyZcipfQLYxq7j_PzbEc2UOM3z9FA',
  );
  
  final client = Supabase.instance.client;
  
  try {
    print('Signing in...');
    await client.auth.signInWithPassword(email: 'siyavarghese29@gmail.com', password: 'isteISTE2026');
    final user = client.auth.currentUser;
    print('Logged in user: ${user?.id}');
    
    print('Fetching folder_members...');
    final data = await client
          .from('folder_members')
          .select('*, users!folder_members_user_id_fkey(id, name, email, role, post)')
          .eq('user_id', user!.id);
    print('Result: $data');
    
  } catch (e, st) {
    print('Error: $e');
    print('StackTrace: $st');
  }
}
