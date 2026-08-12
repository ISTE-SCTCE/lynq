import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/auth_provider.dart';
import '../../models/user_model.dart';
import '../../models/folder_model.dart';
import '../../shared/widgets/glass_card.dart';

class PermissionManagerScreen extends StatefulWidget {
  const PermissionManagerScreen({super.key});

  @override
  State<PermissionManagerScreen> createState() => _PermissionManagerScreenState();
}

class _PermissionManagerScreenState extends State<PermissionManagerScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  
  // Data
  List<UserModel> _allUsers = [];
  List<FolderModel> _forums = [];
  List<FolderPermissionModel> _allPermissions = [];
  List<UserModel> _authorizedCoreMembers = [];
  
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    setState(() => _isLoading = true);
    try {
      final responses = await Future.wait([
        _supabase.from('profiles').select().order('name'),
        _supabase.from('folders').select().eq('is_forum', true).order('name'),
        _supabase.from('folder_permissions').select(),
        _supabase.from('folder_members').select('*, profiles!folder_members_user_id_fkey(*)').eq('execom_id', 0),
      ]);

      if (mounted) {
        setState(() {
          _allUsers = (responses[0] as List).map((u) => UserModel.fromJson(u)).toList();
          _forums = (responses[1] as List).map((f) => FolderModel.fromJson(f)).toList();
          _allPermissions = (responses[2] as List).map((p) => FolderPermissionModel.fromJson(p)).toList();
          _authorizedCoreMembers = (responses[3] as List)
              .where((m) => m['users'] != null)
              .map((m) => UserModel.fromJson(m['users']))
              .toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
      }
    }
  }

  // ── Role Management ──
  Future<void> _updateUserRole(UserModel user, String newRole) async {
    try {
      await _supabase.from('profiles').update({'role': newRole}).eq('id', user.id);
      _fetchAllData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ── Permission Toggles ──
  Future<void> _togglePermission(int folderId, String feature, bool current) async {
    try {
      final existing = _allPermissions.where((p) => p.folderId == folderId && p.feature == feature).firstOrNull;
      
      if (existing != null) {
        await _supabase.from('folder_permissions').update({'allowed': !current}).eq('id', existing.id);
      } else {
        await _supabase.from('folder_permissions').insert({
          'execom_id': folderId,
          'feature': feature,
          'allowed': !current,
        });
      }
      _fetchAllData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating permission: $e')));
    }
  }

  // ── Authorized Core Management ──
  Future<void> _addAuthorizedMember() async {
    final existingIds = _authorizedCoreMembers.map((m) => m.id).toSet();
    final availableUsers = _allUsers.where((u) => !existingIds.contains(u.id)).toList();
    
    final user = await showSearch<UserModel?>(
      context: context,
      delegate: _UserSearchDelegate(availableUsers),
    );
    if (user != null) {
      try {
        await _supabase.from('folder_members').insert({
          'execom_id': 0,
          'user_id': user.id,
          'execom_role': 'viewer',
        });
        _fetchAllData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding member: $e')));
      }
    }
  }

  Future<void> _removeAuthorizedMember(UserModel user) async {
    try {
      await _supabase.from('folder_members').delete().eq('execom_id', 0).eq('user_id', user.id);
      _fetchAllData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error removing member: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final canManageGlobal = auth.permissions?.canManageGlobalPermissions ?? false;

    if (!canManageGlobal) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('Restricted Access', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Only the Chairman can manage permissions.'),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Permission Manager', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 13),
          indicatorColor: AppTheme.secondary,
          tabs: const [
            Tab(text: 'MEMBERS', icon: Icon(Icons.people_outline)),
            Tab(text: 'TEAMS', icon: Icon(Icons.groups_outlined)),
            Tab(text: 'CORE', icon: Icon(Icons.security)),
          ],
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildMembersTab(),
              _buildForumsTab(),
              _buildCoreTab(),
            ],
          ),
    );
  }

  Widget _buildMembersTab() {
    final filtered = _searchQuery.isEmpty ? _allUsers : _allUsers.where((u) => u.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search members...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final user = filtered[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                        child: Text(user.name[0], style: TextStyle(color: AppTheme.secondary)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                            Text(user.email, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      _buildRoleDropdown(user),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown(UserModel user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<String>(
        value: user.role,
        underline: const SizedBox(),
        items: [
          'chairman', 'vice_chairman', 'core_execcom', 'execcom', 'member'
        ].map((r) => DropdownMenuItem(
          value: r,
          child: Text(AppRole.fromString(r).label, style: const TextStyle(fontSize: 11)),
        )).toList(),
        onChanged: (val) => val != null ? _updateUserRole(user, val) : null,
      ),
    );
  }

  Widget _buildForumsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _forums.length,
      itemBuilder: (context, index) {
        final forum = _forums[index];
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: ExpansionTile(
            title: Text(forum.name, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
            subtitle: Text('Team Visual Visibility', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
            children: [
              _buildPermissionToggle(forum.id, FolderFeature.viewBudget, 'Show Budget Bar'),
              _buildPermissionToggle(forum.id, FolderFeature.requestBudget, 'Allow Budget Requests'),
              _buildPermissionToggle(forum.id, FolderFeature.uploadReports, 'Allow Report Uploads'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoreTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Global Configuration', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              Text('Control what features summarized Core members can see globally.', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
              const Divider(height: 32),
              _buildPermissionToggle(0, FolderFeature.viewTotalBudget, 'View Total Organization Budget'),
              _buildPermissionToggle(0, FolderFeature.viewReports, 'View All Submitted Reports'),
              _buildPermissionToggle(0, FolderFeature.manageAll, 'Global Management Access'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Authorized Core Members', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Text('These members will have access to the global features toggled above (only if they hold the Core Execcom role).', 
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 16),
        ..._authorizedCoreMembers.map((user) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                  child: Text(user.name[0], style: TextStyle(color: AppTheme.secondary, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('${user.post ?? 'Core Member'} • ${user.email}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  onPressed: () => _removeAuthorizedMember(user),
                ),
              ],
            ),
          ),
        )),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addAuthorizedMember,
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Add Authorized Member'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionToggle(int folderId, String feature, String label) {
    final isAllowed = _allPermissions.any((p) => p.folderId == folderId && p.feature == feature && p.allowed);
    return ListTile(
      title: Text(label, style: GoogleFonts.inter(fontSize: 14)),
      trailing: Switch(
        value: isAllowed,
        activeColor: AppTheme.secondary,
        onChanged: (val) => _togglePermission(folderId, feature, isAllowed),
      ),
    );
  }
}

class _UserSearchDelegate extends SearchDelegate<UserModel?> {
  final List<UserModel> users;
  _UserSearchDelegate(this.users);

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final filtered = users.where((u) => u.name.toLowerCase().contains(query.toLowerCase())).toList();
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final user = filtered[index];
        return ListTile(
          title: Text(user.name),
          subtitle: Text('${user.post ?? user.role} • ${user.email}'),
          onTap: () => close(context, user),
        );
      },
    );
  }
}

