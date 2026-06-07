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

  Map<String, int> _departmentCounts = {};
  Map<String, int> _yearCounts = {};

  bool _isLoading = true;

  late final SupabaseClient _mentronClient;
  RealtimeChannel? _mentronChannel;

  @override
  void initState() {
    super.initState();
    _initMentronClient();
  }

  void _initMentronClient() {
    _mentronClient = SupabaseClient(
      'https://ysllolnoyezfdllqocgv.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlzbGxvbG5veWV6ZmRsbHFvY2d2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1MjA0NTcsImV4cCI6MjA4NzA5NjQ1N30.0bQMBFKaQuXEQ3sh1_gfQWgWkcd70SDfy_zMwIQ8myk',
    );
    _fetchMentronMetrics();

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

      // Fetch from Mentron DB (Bypassing RLS with SECURITY DEFINER RPCs)
      final profilesResp = await _mentronClient.rpc('get_all_mentron_profiles');
      final allProfiles = List<Map<String, dynamic>>.from(profilesResp);

      int students = 0;
      int admins = 0;
      Map<String, int> deptCounts = {};
      Map<String, int> yrCounts = {};

      for (var profile in allProfiles) {
        final role = profile['role'];
        if (role == 'exec' || role == 'core' || role == 'admin' || role == 'mentor' || role == 'superadmin') {
          admins++;
        } else {
          students++;
        }

        final dept = profile['department']?.toString().trim();
        if (dept != null && dept.isNotEmpty) {
          deptCounts[dept] = (deptCounts[dept] ?? 0) + 1;
        }

        final yr = profile['year']?.toString().trim();
        if (yr != null && yr.isNotEmpty) {
          final yearLabel = 'Year $yr';
          yrCounts[yearLabel] = (yrCounts[yearLabel] ?? 0) + 1;
        }
      }

      final notesResp = await _mentronClient.rpc('get_all_mentron_notes');
      final notesCount = (notesResp as List).length;

      final viewsResp = await _mentronClient.rpc('get_all_mentron_note_views');
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
          _departmentCounts = deptCounts;
          _yearCounts = yrCounts;
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
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform Overview',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Core metrics sourced directly from the Mentron platform.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Core Metrics Grid
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 0.85,
                      children: [
                        _buildSquareMetricCard('Registered\nStudents', _registeredStudents, Icons.school_rounded, Colors.blueAccent, isDark),
                        _buildSquareMetricCard('Active\nAdmins', _activeAdmins, Icons.admin_panel_settings_rounded, Colors.orangeAccent, isDark),
                        _buildSquareMetricCard('Total\nNotes', _totalNotes, Icons.library_books_rounded, Colors.greenAccent, isDark),
                        _buildSquareMetricCard('Total\nViews', _totalViews, Icons.remove_red_eye_rounded, Colors.purpleAccent, isDark),
                      ],
                    ),

                    const SizedBox(height: 40),
                    Text(
                      'Student Demographics',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Insights into the user base distribution.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Demographics Visualizations
                    _buildBarChart('Department Distribution', _departmentCounts, AppTheme.primary, isDark),
                    const SizedBox(height: 24),
                    _buildBarChart('Year-wise Distribution', _yearCounts, AppTheme.secondary, isDark),
                    const SizedBox(height: 40),

                    // Event Suggestions Engine
                    Text(
                      'Event Suggestions',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Generated from demographic data.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSuggestionsEngine(isDark),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSquareMetricCard(String title, int value, IconData icon, Color color, bool isDark) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart(String title, Map<String, int> data, Color barColor, bool isDark) {
    if (data.isEmpty) {
      return GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              'No data available for $title',
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    final sortedEntries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sortedEntries.first.value;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...sortedEntries.map((e) {
              final pct = maxVal == 0 ? 0.0 : e.value / maxVal;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.grey[300] : Colors.grey[800],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${e.value}',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Container(
                              height: 8,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: pct),
                              duration: const Duration(milliseconds: 1200),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Container(
                                  height: 8,
                                  width: constraints.maxWidth * value,
                                  decoration: BoxDecoration(
                                    color: barColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsEngine(bool isDark) {
    if (_departmentCounts.isEmpty && _yearCounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final suggestions = <Widget>[];

    // Top Department Rule
    if (_departmentCounts.isNotEmpty) {
      final topDept = _departmentCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      if (topDept.value > 5) {
        suggestions.add(_buildSuggestionCard(
          icon: Icons.lightbulb_outline,
          color: Colors.amber,
          title: 'Host a ${topDept.key} Workshop',
          description: 'With ${topDept.value} students registered, a specialized event for this department would see high engagement.',
          isDark: isDark,
        ));
      }
    }

    // Top Year Rule
    if (_yearCounts.isNotEmpty) {
      final topYear = _yearCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
      if (topYear.key.contains('1')) {
        suggestions.add(_buildSuggestionCard(
          icon: Icons.group_add_rounded,
          color: Colors.green,
          title: 'Organize a First-Year Orientation',
          description: 'A large portion of users are 1st-year students. Consider a mentorship session.',
          isDark: isDark,
        ));
      } else if (topYear.key.contains('4')) {
        suggestions.add(_buildSuggestionCard(
          icon: Icons.work_outline_rounded,
          color: Colors.blue,
          title: 'Placement \u0026 Career Guidance',
          description: 'Many final-year students are registered. A career guidance session is recommended.',
          isDark: isDark,
        ));
      }
    }

    if (suggestions.isEmpty) {
      suggestions.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'More data needed to generate confident suggestions.',
            style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return Column(children: suggestions);
  }

  Widget _buildSuggestionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
