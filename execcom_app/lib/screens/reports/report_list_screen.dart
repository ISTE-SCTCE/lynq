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

        if (myRole == AppRole.chairman) return true; // Chairman sees all

        final uploaderRoleStr = _userCache[uploaderId]?['role'];
        final uploaderRole = AppRole.fromString(uploaderRoleStr);

        if (myRole == AppRole.viceChairman) {
          if (uploaderRole.level <= AppRole.viceChairman.level) return true;
        }
        
        final visibilityRaw = report['visibility'];
        final visibility = visibilityRaw is List ? List<String>.from(visibilityRaw) : <String>[];
        if (visibility.contains(myRole.toDbString())) return true;

        return false;
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
                                    } else if (val == 'delete') {
                                      _deleteReport(report['id'], report['file_url']);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
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
