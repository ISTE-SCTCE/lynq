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
        column: 'execom_id',
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
          .select('*, profiles!folder_members_user_id_fkey(id, name, email, role, post)')
          .eq('execom_id', widget.folderId)
          .order('execom_role');
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
              if (perms?.isAtLeastTier1 ?? false)
                _actionChip(Icons.person_add_outlined, 'Add Member', () => context.push('/folders/${widget.folderId}/add_member')),
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
              onTap: () {
                if (perms?.isAtLeastTier1 ?? false) {
                  _showMemberActions(context, m);
                } else if (m.user != null) {
                  context.push('/members/${m.userId}');
                }
              },
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

  void _showMemberActions(BuildContext context, FolderMemberModel member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Manage ${member.user?.name ?? 'Member'}', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('View Profile', style: GoogleFonts.inter()),
              onTap: () {
                Navigator.pop(context);
                if (member.user != null) context.push('/members/${member.userId}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text('Change Team', style: GoogleFonts.inter()),
              onTap: () {
                Navigator.pop(context);
                _showChangeTeamDialog(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text('Change Role', style: GoogleFonts.inter()),
              onTap: () {
                Navigator.pop(context);
                _showChangeRoleDialog(member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
              title: Text('Remove from Team', style: GoogleFonts.inter(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _removeMember(member);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _removeMember(FolderMemberModel member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Remove Member?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Text('Are you sure you want to remove ${member.user?.name} from this team?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent))
          ),
        ],
      )
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('folder_members').delete().eq('id', member.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member removed'), backgroundColor: Colors.green));
        _loadData();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  void _showChangeRoleDialog(FolderMemberModel member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Role', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ...['chair', 'vice_chair', 'head', 'secretary', 'joint_secretary', 'member'].map((role) {
              return ListTile(
                title: Text(role.replaceAll('_', ' ').toUpperCase(), style: GoogleFonts.inter()),
                trailing: member.folderRole == role ? const Icon(Icons.check, color: AppTheme.secondary) : null,
                onTap: () {
                  Navigator.pop(context);
                  _changeMemberRole(member, role);
                },
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _changeMemberRole(FolderMemberModel member, String newRole) async {
    if (member.folderRole == newRole) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('folder_members').update({'execom_role': newRole}).eq('id', member.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated'), backgroundColor: Colors.green));
        _loadData();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showChangeTeamDialog(FolderMemberModel member) async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client.from('folders').select().eq('is_forum', true).order('name');
      final folders = (data as List).map((e) => FolderModel.fromJson(e)).where((f) => f.id != widget.folderId).toList();
      setState(() => _isLoading = false);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Move to Team', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (folders.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('No other teams available.')),
              ...folders.map((f) => ListTile(
                title: Text(f.name, style: GoogleFonts.inter()),
                onTap: () {
                  Navigator.pop(context);
                  _changeMemberTeam(member, f.id);
                },
              )),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeMemberTeam(FolderMemberModel member, int newFolderId) async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('folder_members').update({'execom_id': newFolderId}).eq('id', member.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member moved to new team'), backgroundColor: Colors.green));
        _loadData();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }
}
