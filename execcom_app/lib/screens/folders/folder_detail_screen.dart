import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../models/folder_model.dart';
import '../../shared/widgets/glass_card.dart';

class FolderDetailScreen extends StatefulWidget {
  final int folderId;
  const FolderDetailScreen({super.key, required this.folderId});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  FolderModel? _folder;
  List<FolderMemberModel> _members = [];
  bool _isLoading = true;
  RealtimeChannel? _membersChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtime();
  }

  void _setupRealtime() {
    _membersChannel = Supabase.instance.client.channel('public:folder_members:${widget.folderId}');
    _membersChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'folder_members',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'folder_id',
        value: widget.folderId,
      ),
      callback: (payload) {
        if (mounted) _loadData(); // Reload completely as it joins `users`
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _membersChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    final supabase = Supabase.instance.client;
    try {
      final folderData = await supabase.from('folders').select().eq('id', widget.folderId).single();
      _folder = FolderModel.fromJson(folderData);

      final memberData = await supabase
          .from('folder_members')
          .select('*, users!folder_members_user_id_fkey(id, name, email, role, post)')
          .eq('folder_id', widget.folderId)
          .order('folder_role');
      _members = (memberData as List).map((e) => FolderMemberModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error loading folder: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Color _roleColor(String role) => switch (role) {
    'chair' => Colors.amber,
    'vice_chair' => Colors.orange,
    'head' => Colors.deepOrange,
    'secretary' => AppTheme.secondary,
    'joint_secretary' => AppTheme.secondary.withValues(alpha: 0.7),
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final perms = context.read<AuthProvider>().permissions;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _folder?.name ?? 'Forum',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (perms?.canManagePermissions ?? false)
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              tooltip: 'Permissions',
              onPressed: () => context.push('/folders/${widget.folderId}/permissions'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final perms = context.read<AuthProvider>().permissions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Forum header
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          _folder!.name.substring(0, _folder!.name.length > 3 ? 3 : _folder!.name.length),
                          style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_folder!.name, style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold)),
                          Text('${_members.length} members', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_folder!.description != null) ...[
                  const SizedBox(height: 12),
                  Text(_folder!.description!, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Quick actions
          Text('Actions', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionChip(Icons.event_outlined, 'Events', () => context.push('/events?folder=${widget.folderId}')),
              if (perms?.canUploadReportInFolder(widget.folderId) ?? false)
                _actionChip(Icons.upload_file_outlined, 'Upload Report', () => context.push('/reports/upload')),
            ],
          ),
          const SizedBox(height: 24),

          // Member list
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Members', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ..._members.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: m.user != null ? () => context.push('/members/${m.userId}') : null,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _roleColor(m.folderRole).withValues(alpha: 0.2),
                      child: Text(
                        (m.user?.name ?? '?').substring(0, 1).toUpperCase(),
                        style: TextStyle(color: _roleColor(m.folderRole), fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.user?.name ?? 'Unknown', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          Text(m.user?.post ?? m.folderRole, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _roleColor(m.folderRole).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        m.folderRole.replaceAll('_', ' '),
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _roleColor(m.folderRole)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.secondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.darkGreen),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
