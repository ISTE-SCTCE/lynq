import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(
    'https://ysllolnoyezfdllqocgv.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzbGxvbG5veWV6ZmRsbHFvY2d2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1MjA0NTcsImV4cCI6MjA4NzA5NjQ1N30.0bQMBFKaQuXEQ3sh1_gfQWgWkcd70SDfy_zMwIQ8myk'
  );

  try {
    print('Testing profiles RPC...');
    final p = await client.rpc('get_all_mentron_profiles');
    final pList = p as List;
    print('Profiles length: ' + pList.length.toString());
    
    print('Testing notes query...');
    final n = await client.from('notes').select('id');
    print('Notes length: ' + (n as List).length.toString());
    
    print('Testing note_views query...');
    final nv = await client.from('note_views').select('views_count');
    print('Note views length: ' + (nv as List).length.toString());
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
