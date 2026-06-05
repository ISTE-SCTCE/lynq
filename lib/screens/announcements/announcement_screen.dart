import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../models/app_models.dart';
import '../../shared/widgets/glass_card.dart';

class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  List<AnnouncementModel> _announcements = [];
  bool _isLoading = true;
  RealtimeChannel? _announcementsChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _setupRealtime();
  }

  void _setupRealtime() {
    _announcementsChannel = Supabase.instance.client.channel('public:announcements');
    _announcementsChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'announcements',
      callback: (payload) {
        if (!mounted) return;
        final eventType = payload.eventType;
        if (eventType == PostgresChangeEvent.insert) {
          final newAnn = AnnouncementModel.fromJson(payload.newRecord);
          setState(() {
            _announcements.insert(0, newAnn);
          });
        } else if (eventType == PostgresChangeEvent.update) {
          final updatedAnn = AnnouncementModel.fromJson(payload.newRecord);
          setState(() {
            final index = _announcements.indexWhere((a) => a.id == updatedAnn.id);
            if (index != -1) _announcements[index] = updatedAnn;
          });
        } else if (eventType == PostgresChangeEvent.delete) {
          final deletedId = payload.oldRecord['id'] as int;
          setState(() {
            _announcements.removeWhere((a) => a.id == deletedId);
          });
        }
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _announcementsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client.from('announcements').select().order('created_at', ascending: false);
      _announcements = (data as List).map((e) => AnnouncementModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showCreateDialog() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String visibility = 'public';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('New Announcement', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 12),
                TextField(controller: contentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Content')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: visibility,
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('Public (all members)')),
                    DropdownMenuItem(value: 'internal', child: Text('Internal (execcom+)')),
                  ],
                  onChanged: (v) => setDialogState(() => visibility = v ?? 'public'),
                  decoration: const InputDecoration(labelText: 'Visibility'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.isEmpty) return;
                await Supabase.instance.client.from('announcements').insert({
                  'title': titleCtrl.text.trim(),
                  'content': contentCtrl.text.trim(),
                  'visibility': visibility,
                  'created_by': Supabase.instance.client.auth.currentUser?.id,
                });
                if (mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.read<AuthProvider>().permissions;

    return Scaffold(
      appBar: AppBar(title: Text('Announcements', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      floatingActionButton: (perms?.canManageAnnouncements ?? false)
          ? FloatingActionButton(
              onPressed: _showCreateDialog,
              backgroundColor: AppTheme.secondary,
              foregroundColor: AppTheme.darkGreen,
              child: const Icon(Icons.add),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _announcements.isEmpty
              ? Center(child: Text('No announcements', style: GoogleFonts.inter(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _announcements.length,
                    itemBuilder: (context, i) {
                      final ann = _announcements[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    ann.visibility == 'internal' ? Icons.lock_outline : Icons.campaign_outlined,
                                    size: 18,
                                    color: ann.visibility == 'internal' ? Colors.orange : AppTheme.secondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(ann.title, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (ann.visibility == 'internal' ? Colors.orange : Colors.green).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      ann.visibility,
                                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              if (ann.content != null && ann.content!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(ann.content!, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                              ],
                              if (ann.createdAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${ann.createdAt!.day}/${ann.createdAt!.month}/${ann.createdAt!.year}',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.withValues(alpha: 0.6)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
