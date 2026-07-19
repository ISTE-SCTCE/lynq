import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../shared/widgets/glass_card.dart';
import '../../core/auth_provider.dart';
import '../../core/constants.dart';
import '../../shared/widgets/document_preview_screen.dart';
import 'report_upload_screen.dart';

class ReportListScreen extends StatefulWidget {
  const ReportListScreen({super.key});

  @override
  State<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends State<ReportListScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _reports = [];
  final Map<String, Map<String, dynamic>> _userCache = {};
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupRealtime();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _setupRealtime() {
    _subscription = _supabase
        .from('event_reports')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((data) async {
      
      final userIds = data.map((e) => e['uploaded_by'] as String?).whereType<String>().toSet();
      final missingIds = userIds.difference(_userCache.keys.toSet());
      
      if (missingIds.isNotEmpty) {
        try {
          final users = await _supabase
              .from('users')
              .select('id, name, post, role')
              .inFilter('id', missingIds.toList());
          for (var u in users) {
            _userCache[u['id']] = u;
          }
        } catch (e) {
          debugPrint('Error fetching user cache: $e');
        }
      }

      if (!mounted) return;
      
      final authProvider = context.read<AuthProvider>();
      final myRole = authProvider.role;
      final myId = _supabase.auth.currentUser?.id;

      final filteredData = data.where((report) {
        final uploaderId = report['uploaded_by'];
        if (uploaderId == myId) return true; // Uploader always sees their own

        final isGlobal = authProvider.permissions?.isMemberOfFolder(0) ?? false;
        final canViewGlobally = isGlobal && (authProvider.permissions?.isFeatureEnabledGlobally(FolderFeature.viewReports) ?? false);
        
        if (myRole == AppRole.chairman || myRole == AppRole.viceChairman || canViewGlobally) return true; // Tier 1 and explicit globals see all

        final uploaderRoleStr = _userCache[uploaderId]?['role'];
        final uploaderRole = AppRole.fromString(uploaderRoleStr);

        // Tier logic: Higher AppRole level = lower tier number (Tier 1 = Chairman)
        if (myRole.level < uploaderRole.level) return false;
        
        // Team Isolation: If report belongs to a team, you must be in that team or be Tier 2
        final execomId = report['execom_id'] as int?;
        if (execomId != null && myRole.level < AppRole.coreExeccom.level) {
          final myFolderIds = authProvider.permissions?.userFolderIds ?? [];
          if (!myFolderIds.contains(execomId)) {
            return false; // Cross-team isolation
          }
        }
        
        // Team Restriction Overrides Check
        final restrictedRaw = report['restricted_teams'];
        final restrictedTeams = restrictedRaw is List ? restrictedRaw : [];
        if (restrictedTeams.isNotEmpty) {
           final myFolderIds = authProvider.permissions?.userFolderIds ?? [];
           for (final rTeam in restrictedTeams) {
              final teamId = int.tryParse(rTeam.toString());
              if (teamId != null && myFolderIds.contains(teamId)) {
                 return false; // Specifically restricted by Tier 1
              }
           }
        }

        return true;
      }).toList();

      // Sort descending by created_at since stream order doesn't always guarantee descending
      filteredData.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
        final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      setState(() {
        _reports = filteredData;
        _isLoading = false;
      });
    }, onError: (err) {
      debugPrint('Realtime error: $err');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _deleteReport(String id, String? fileUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text('Are you sure you want to delete this report? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Delete', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (fileUrl != null && fileUrl.contains('/storage/v1/object/public/reports/')) {
        final path = fileUrl.split('/storage/v1/object/public/reports/').last;
        try {
          await _supabase.storage.from('reports').remove([path]);
        } catch (e) {
          debugPrint('Error deleting file: $e');
        }
      }
      
      await _supabase.from('event_reports').delete().eq('id', id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report deleted')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _showManageVisibilityDialog(Map<String, dynamic> report) async {
    final supabase = Supabase.instance.client;
    List<Map<String, dynamic>> teams = [];
    try {
      final res = await supabase.from('folders').select('id, name').eq('is_forum', true).order('name');
      teams = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load teams: $e')));
      return;
    }

    if (!mounted) return;
    
    final currentRaw = report['restricted_teams'];
    final restrictedTeams = (currentRaw is List ? currentRaw : []).map((e) => int.tryParse(e.toString())).whereType<int>().toSet();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text('Manage Team Visibility', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: teams.length,
                  itemBuilder: (context, index) {
                    final team = teams[index];
                    final teamId = team['id'] as int;
                    final isRestricted = restrictedTeams.contains(teamId);
                    return CheckboxListTile(
                      title: Text(team['name'], style: GoogleFonts.inter(color: Colors.white)),
                      subtitle: Text(isRestricted ? 'Restricted (Hidden)' : 'Default Access', style: GoogleFonts.inter(color: isRestricted ? Colors.redAccent : Colors.grey, fontSize: 12)),
                      value: isRestricted,
                      activeColor: Colors.redAccent,
                      checkColor: Colors.white,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            restrictedTeams.add(teamId);
                          } else {
                            restrictedTeams.remove(teamId);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await supabase.from('event_reports').update({
                        'restricted_teams': restrictedTeams.toList(),
                      }).eq('id', report['id']);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visibility updated'), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating: $e'), backgroundColor: Colors.red));
                    }
                  },
                  child: const Text('Save Restrictions'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = _supabase.auth.currentUser?.id;
    final myRole = context.read<AuthProvider>().role;

    return Scaffold(
      appBar: AppBar(
        title: Text('View Reports', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? const Center(child: Text('No reports available.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final report = _reports[index];
                    final uploaderData = _userCache[report['uploaded_by']];
                    final uploaderName = uploaderData?['name'] ?? 'Unknown';
                    final uploaderPost = uploaderData?['post'] ?? '';
                    final uploaderDisplay = uploaderPost.isNotEmpty ? '$uploaderName ($uploaderPost)' : uploaderName;
                    
                    final isOwner = report['uploaded_by'] == myId;
                    final canManage = isOwner || myRole >= AppRole.viceChairman;

                    return GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  report['title'] ?? 'No Title',
                                  style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (canManage)
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onSelected: (val) {
                                    if (val == 'edit') {
                                      Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => ReportUploadScreen(existingReport: report)
                                      ));
                                    } else if (val == 'manage_teams') {
                                      _showManageVisibilityDialog(report);
                                    } else if (val == 'delete') {
                                      _deleteReport(report['id'], report['file_url']);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    if (myRole >= AppRole.viceChairman)
                                      const PopupMenuItem(value: 'manage_teams', child: Text('Manage Team Visibility')),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Uploaded by: $uploaderDisplay',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            report['content'] ?? '',
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                          if (report['file_url'] != null) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => DocumentPreviewScreen(
                                    title: report['title'] ?? 'Document Preview',
                                    fileUrl: report['file_url'],
                                  )
                                ));
                              },
                              icon: const Icon(Icons.visibility),
                              label: const Text('Preview Document'),
                            )
                          ]
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
