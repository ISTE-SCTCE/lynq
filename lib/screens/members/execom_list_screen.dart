import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';

class ExecomListScreen extends StatefulWidget {
  const ExecomListScreen({super.key});

  @override
  State<ExecomListScreen> createState() => _ExecomListScreenState();
}

class _ExecomListScreenState extends State<ExecomListScreen> {
  bool _isLoading = true;
  // Map of team name to list of members
  Map<String, List<Map<String, dynamic>>> _teams = {};
  int _totalExecomCount = 0;

  @override
  void initState() {
    super.initState();
    _loadExecomMembers();
  }

  Future<void> _loadExecomMembers() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('folder_members')
          .select('execom_role, folders!inner(name), profiles!inner(id, name, email, phone, role, post)');
      
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      final Set<String> uniqueUsers = {};

      for (var row in data as List) {
        final folderName = row['folders']['name'] as String;
        final user = row['profiles'] as Map<String, dynamic>;
        uniqueUsers.add(user['id']);
        user['execom_role'] = row['execom_role'];

        grouped.putIfAbsent(folderName, () => []).add(user);
      }

      // Sort members within each team
      final roleWeights = {
        'chairman': 0, 'chair': 0,
        'vice_chairman': 1, 'vice-chair': 1, 'vice chair': 1,
        'head': 2, 'technical head': 2, 'media head': 2, 'marketing head': 2, 'design head': 2,
        'secretary': 3,
        'joint_secretary': 4, 'joint secretary': 4,
        'treasurer': 5, 'sub-treasurer': 5,
        'core_execcom': 6, 'forum_execcom': 6, 'execom': 6,
        'member': 7,
        'panel': 8,
        'restricted': 9,
      };

      final sortedGrouped = Map.fromEntries(
        grouped.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))
          ..map((e) {
            e.value.sort((a, b) {
              final roleA = (a['execom_role'] as String?)?.toLowerCase() ?? 'member';
              final roleB = (b['execom_role'] as String?)?.toLowerCase() ?? 'member';
              final wA = roleWeights[roleA] ?? 10;
              final wB = roleWeights[roleB] ?? 10;
              if (wA != wB) return wA.compareTo(wB);
              
              final nameA = (a['name'] as String?)?.toLowerCase() ?? '';
              final nameB = (b['name'] as String?)?.toLowerCase() ?? '';
              return nameA.compareTo(nameB);
            });
            return e;
          })
      );

      setState(() {
        _teams = sortedGrouped;
        _totalExecomCount = uniqueUsers.length;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading execom members: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _roleColor(String role) => switch (role.toLowerCase()) {
    'chairman' || 'chair'                   => Colors.amber,
    'vice_chairman' || 'vice-chair' 
        || 'vice chair'                     => Colors.orange,
    'core_execcom' || 'secretary' 
        || 'treasurer' || 'sub-treasurer'
        || 'joint secretary'                => AppTheme.secondary,
    'forum_execcom' || 'execom' 
        || 'technical head' || 'media head'
        || 'marketing head' || 'design head'=> Colors.teal,
    'panel'                                 => Colors.blueGrey,
    'restricted'                            => Colors.purple,
    _                                       => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    if (auth.role == AppRole.restricted) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Execom', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Access Denied', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Execom Teams', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _teams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group_off_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text('No Execom members found', style: GoogleFonts.inter(color: Colors.grey)),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Text(
                              'Total Execom Members',
                              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              '$_totalExecomCount',
                              style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ..._teams.entries.map((entry) {
                      final teamName = entry.key;
                      final members = entry.value;
                      return SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                              child: Text(
                                teamName,
                                style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.secondary),
                              ),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final user = members[index];
                                final role = user['role'] as String? ?? 'member';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: GlassCard(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: _roleColor(role).withValues(alpha: 0.2),
                                          child: Text(
                                            (user['name'] as String?)?.isNotEmpty == true ? user['name'][0].toUpperCase() : '?',
                                            style: TextStyle(color: _roleColor(role), fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(user['name'] ?? 'Unknown', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                                              Text(
                                                user['execom_role'] ?? user['post'] ?? AppRole.formatRoleDisplay(role),
                                                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _roleColor(role).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            AppRole.formatRoleDisplay(role),
                                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _roleColor(role)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              childCount: members.length,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
    );
  }
}
