import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../core/app_cache.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/primary_button.dart';

class MemberListScreen extends StatefulWidget {
  const MemberListScreen({super.key});

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> with SingleTickerProviderStateMixin {
  List<UserModel> _allUsers = [];
  bool _isLoading = true;
  String _filter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final cache = AppCache();
    if (cache.membersList != null) {
      setState(() {
        _allUsers = cache.membersList!;
        _isLoading = false;
      });
      // If not stale, just return early to avoid redundant network calls
      if (!cache.isMembersStale) return;
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final data = await Supabase.instance.client
          .from('members')
          .select('id, name, email, role, post, designation, phone, iste_id, ui_id, department, plan, plan_type, joined_date, registration_date, forum, forum_name, expiry_date, membership_expiry, status, suspended_until')
          .order('created_at', ascending: false);
      _allUsers = (data as List)
          .map((e) => UserModel.fromJson({
                'id': e['id']?.toString() ?? '',
                'name': e['name'],
                'email': e['email'],
                'role': e['role'] == 'user' ? 'member' : e['role'],
                'post': e['post'] ?? e['designation'],
                'phone': e['phone'],
                'roll_number': e['iste_id'] ?? e['ui_id'],
                'branch': e['department'],
                'membership_plan': e['plan'] ?? e['plan_type'],
                'membership_date': e['joined_date'] ?? e['registration_date'],
                'forum': e['forum'] ?? e['forum_name'],
                'expiry_date': e['expiry_date'] ?? e['membership_expiry'],
                'status': e['status'] ?? 'active',
                'suspended_until': e['suspended_until'],
          }))
          .toList();
      
      cache.updateMembers(_allUsers);
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<UserModel> get _filteredUsers {
    var list = _allUsers;
    final now = DateTime.now();
    if (_filter == 'expired') {
      // Parentheses are critical here: without them, the `||` binds loosely
      // and any user with an 'expired' role string would always pass the filter.
      list = list.where((u) =>
          (u.expiryDate != null && u.expiryDate!.isBefore(now)) ||
          u.role.contains('expired')).toList();
    } else if (_filter != 'all') {
      list = list.where((u) => u.role == _filter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((u) =>
          u.name.toLowerCase().contains(query) ||
          u.email.toLowerCase().contains(query) ||
          (u.post ?? '').toLowerCase().contains(query) ||
          (u.phone ?? '').toLowerCase().contains(query) ||
          (u.rollNumber ?? '').toLowerCase().contains(query) ||
          (u.branch ?? '').toLowerCase().contains(query)).toList();
    }
    return list;
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
    final perms = auth.permissions;

    if (auth.role == AppRole.restricted) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Members', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Access Denied', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('You do not have permission to view the member directory.', style: GoogleFonts.inter(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Members', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          if (perms?.canAddMembers ?? false)
            IconButton(icon: const Icon(Icons.person_add_outlined), onPressed: () => context.push('/members-enroll')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  'Total Members',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${_allUsers.length}',
                  style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                ),
              ],
            ),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search by name, email, or post...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              style: GoogleFonts.inter(fontSize: 14),
            ),
          ),
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip('All', 'all'),
                _filterChip('Chairman', 'chairman'),
                _filterChip('Vice Chair', 'vice_chairman'),
                _filterChip('Core Execom', 'core_execcom'),
                _filterChip('Forum Execom', 'forum_execcom'),
                _filterChip('Panel', 'panel'),
                _filterChip('Member', 'member'),
                _filterChip('Expired', 'expired'),
              ],
            ),
          ),
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.group_off_outlined, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text('No members found matching your search', style: GoogleFonts.inter(color: Colors.grey)),
                            const SizedBox(height: 24),
                            if (perms?.canAddMembers ?? false)
                              PrimaryButton(
                                width: 200,
                                text: 'Add New Member',
                                onPressed: () => context.push('/members-enroll'),
                                icon: Icons.person_add,
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                onRefresh: _loadUsers,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, i) {
                    final user = _filteredUsers[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => context.push('/members/${user.id}'),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: _roleColor(user.role).withValues(alpha: 0.2),
                                child: Text(
                                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                  style: TextStyle(color: _roleColor(user.role), fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(user.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                                    Text(
                                      user.post ?? AppRole.fromString(user.role).label,
                                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                                    ),
                                    if (user.membershipDate != null || user.expiryDate != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '${user.membershipDate?.year ?? ''} - ${user.expiryDate?.year ?? 'Present'}',
                                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _roleColor(user.role).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      AppRole.fromString(user.role).label,
                                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _roleColor(user.role)),
                                    ),
                                  ),
                                  if (user.expiryDate != null && user.expiryDate!.isBefore(DateTime.now())) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Expired',
                                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ),
        ],
      ),
      floatingActionButton: (perms?.canAddMembers ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/members-enroll'),
              icon: const Icon(Icons.person_add),
              label: Text('Add Member', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
              backgroundColor: AppTheme.secondary,
              foregroundColor: AppTheme.darkGreen,
            )
          : null,
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: AppTheme.secondary.withValues(alpha: 0.2),
        checkmarkColor: AppTheme.darkGreen,
      ),
    );
  }
}
