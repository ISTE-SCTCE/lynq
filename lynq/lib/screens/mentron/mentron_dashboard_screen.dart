import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';
import 'package:go_router/go_router.dart';

class MentronDashboardScreen extends StatefulWidget {
  const MentronDashboardScreen({super.key});

  @override
  State<MentronDashboardScreen> createState() => _MentronDashboardScreenState();
}

class _MentronDashboardScreenState extends State<MentronDashboardScreen> {
  int _registeredStudents = 0;
  int _activeAdmins = 0;
  int _totalNotes = 0;
  int _totalViews = 0;
  bool _isLoading = true;

  late final SupabaseClient _mentronClient;

  RealtimeChannel? _mentronChannel;

  @override
  void initState() {
    super.initState();
    _initMentronClient();
  }

  void _initMentronClient() {
    // Initialize a separate client for Mentron DB
    _mentronClient = SupabaseClient(
      'https://ysllolnoyezfdllqocgv.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzbGxvbG5veWV6ZmRsbHFvY2d2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1MjA0NTcsImV4cCI6MjA4NzA5NjQ1N30.0bQMBFKaQuXEQ3sh1_gfQWgWkcd70SDfy_zMwIQ8myk',
    );
    _fetchMentronMetrics();

    // Subscribe to realtime updates for Mentron platform
    _mentronChannel = _mentronClient
        .channel('mentron_public_profiles')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            _fetchMentronMetrics(showLoading: false);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _mentronChannel?.unsubscribe();
    _mentronClient.dispose();
    super.dispose();
  }

  Future<void> _fetchMentronMetrics({bool showLoading = true}) async {
    try {
      if (showLoading && mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      // Students (assuming role is not 'exec' or 'core', or we can count all distinct profiles)
      // For simplicity, count all profiles
      final profilesResp = await _mentronClient.from('profiles').select('id, role');
      final allProfiles = List<Map<String, dynamic>>.from(profilesResp);
      
      int students = 0;
      int admins = 0;
      for (var profile in allProfiles) {
        final role = profile['role'];
        if (role == 'exec' || role == 'core') {
          admins++;
        } else {
          // If role is null or 'member', they are students
          students++;
        }
      }

      // Total notes
      final notesResp = await _mentronClient.from('notes').select('id');
      final notesCount = (notesResp as List).length;

      // Total views
      final viewsResp = await _mentronClient.from('note_views').select('views_count');
      int viewsSum = 0;
      for (var row in viewsResp) {
        viewsSum += (row['views_count'] as num?)?.toInt() ?? 0;
      }

      if (mounted) {
        setState(() {
          _registeredStudents = students;
          _activeAdmins = admins;
          _totalNotes = notesCount;
          _totalViews = viewsSum;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching Mentron metrics: $e');
      if (mounted && showLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mentron Analytics',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchMentronMetrics(showLoading: true),
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  Text(
                    'Mentron Overview',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Key metrics directly pulled from the Mentron platform.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildMetricCard(
                    title: 'Registered Students',
                    value: _registeredStudents,
                    icon: Icons.school_rounded,
                    color: Colors.blueAccent,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    title: 'Active Administrators',
                    value: _activeAdmins,
                    icon: Icons.admin_panel_settings_rounded,
                    color: Colors.orangeAccent,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    title: 'Total Student Notes',
                    value: _totalNotes,
                    icon: Icons.library_books_rounded,
                    color: Colors.greenAccent,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    title: 'Total Note Views',
                    value: _totalViews,
                    icon: Icons.remove_red_eye_rounded,
                    color: Colors.purpleAccent,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: value),
                    duration: const Duration(milliseconds: 1500),
                    curve: Curves.easeOutQuint,
                    builder: (context, currentVal, child) {
                      return Text(
                        currentVal.toString(),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
