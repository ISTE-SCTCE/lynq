import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(
    'https://ysllolnoyezfdllqocgv.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzbGxvbG5veWV6ZmRsbHFvY2d2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1MjA0NTcsImV4cCI6MjA4NzA5NjQ1N30.0bQMBFKaQuXEQ3sh1_gfQWgWkcd70SDfy_zMwIQ8myk'
  );

  try {
    print('Testing profiles...');
    final p = await client.from('profiles').select();
    final pList = p as List;
    print('Profiles length: ' + pList.length.toString());
    if (pList.isNotEmpty) {
      print('First profile: ' + jsonEncode(pList.first));
    }
  } catch (e) {
    print('Profiles error: ' + e.toString());
  }
}
