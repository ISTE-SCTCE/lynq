import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../models/folder_model.dart';
import '../../shared/widgets/glass_card.dart';
import 'edit_member_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  final String userId;
  const MemberDetailScreen({super.key, required this.userId});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  UserModel? _user;
  String? _linkedUserId; // user_id from members table (for cross-table role updates)
  List<FolderMemberModel> _memberships = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final supabase = Supabase.instance.client;
    try {
      final data = await supabase
          .from('members')
          .select('id, name, email, role, post, designation, phone, iste_id, ui_id, department, plan, plan_type, joined_date, registration_date, forum, forum_name, expiry_date, membership_expiry, status, suspended_until, user_id')
          .eq('id', widget.userId)
          .single();

      // Stash user_id from members table for cross-table updates
      _linkedUserId = data['user_id'] as String?;

      _user = UserModel.fromJson({
        'id': data['id']?.toString() ?? '',
        'name': data['name'],
        'email': data['email'],
        'role': data['role'] == 'user' ? 'member' : data['role'],
        'post': data['post'] ?? data['designation'],
        'phone': data['phone'],
        'roll_number': data['iste_id'] ?? data['ui_id'],
        'branch': data['department'],
        'membership_plan': data['plan'] ?? data['plan_type'],
        'membership_date': data['joined_date'] ?? data['registration_date'],
        'forum': data['forum'] ?? data['forum_name'],
        'expiry_date': data['expiry_date'] ?? data['membership_expiry'],
        'status': data['status'],
        'suspended_until': data['suspended_until'],
      });

      final mData = await supabase
          .from('folder_members')
          .select('*, folders!folder_members_execom_id_fkey(id, name)')
          .eq('user_id', widget.userId);
      _memberships = (mData as List).map((e) => FolderMemberModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showChangeRoleDialog() {
    if (_user == null) return;
    String selectedRole = _user!.role;
    bool isSaving = false;

    final customRoles = [
      'exis_secretary', 'exis_joint_secretary', 'exis_coordinator',
      'bits_secretary', 'bits_joint_secretary', 'bits_coordinator',
      'genesis_secretary', 'genesis_joint_secretary', 'genesis_coordinator',
      'torq_secretary', 'torq_joint_secretary', 'torq_coordinator',
      'swas_secretary', 'swas_joint_secretary', 'swas_coordinator',
      'nexus_head', 'nexus_coordinator',
    ];
    
    // Ensure the current role is always an option to avoid dropdown assertions
    List<String> allValues = [
      ...AppRole.values.where((r) => r != AppRole.restricted).map((e) => e.toDbString()),
      ...customRoles
    ];
    if (!allValues.contains(selectedRole)) {
      selectedRole = AppRole.member.toDbString();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Change Role', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
          content: SingleChildScrollView(
            child: DropdownButtonFormField<String>(
              value: selectedRole,
              dropdownColor: Colors.grey[900],
              style: GoogleFonts.inter(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              items: [
                ...AppRole.values
                    .where((r) => r != AppRole.restricted)
                    .map((r) => DropdownMenuItem(value: r.toDbString(), child: Text(r.label))),
                const DropdownMenuItem(value: '', enabled: false, child: Divider(color: Colors.white24)),
                ...customRoles.map((r) => DropdownMenuItem(value: r, child: Text(AppRole.formatRoleDisplay(r)))),
              ],
              onChanged: (v) {
                if (v != null && v.isNotEmpty) {
                  setState(() => selectedRole = v);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
            ),
            TextButton(
              onPressed: isSaving ? null : () async {
                final currentUser = context.read<AuthProvider>().currentUser;
                final targetRole = AppRole.fromString(selectedRole);
                
                // Restriction: Only Chair/Vice-Chair can promote to Execcom+
                if (targetRole >= AppRole.forumExeccom) {
                  final curRole = AppRole.fromString(currentUser?.role);
                  if (curRole < AppRole.viceChairman) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Only Chairman/Vice Chairman can promote to Execcom+')),
                    );
                    return;
                  }
                }

                setState(() => isSaving = true);
                try {
                  await Supabase.instance.client
                      .from('members')
                      .update({'role': selectedRole})
                      .eq('id', _user!.id);
                  // Use the already-loaded user_id — avoids a second DB round-trip
                  if (_linkedUserId != null) {
                    await Supabase.instance.client
                        .from('profiles')
                        .update({'role': selectedRole})
                        .eq('id', _linkedUserId!);
                  }
                  Navigator.pop(context);
                  _loadUser();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated')));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                } finally {
                  setState(() => isSaving = false);
                }
              },
              child: Text('Update', style: GoogleFonts.inter(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddtoForumDialog() async {
    if (_user == null) return;
    
    setState(() => _isLoading = true);
    List<FolderModel> availableForums = [];
    try {
      // 1. Get all forums
      final foldersRes = await Supabase.instance.client
          .from('folders')
          .select()
          .eq('is_forum', true)
          .order('name');
      
      final allForums = (foldersRes as List).map((e) => FolderModel.fromJson(e)).toList();
      
      // 2. Filter out already joined
      final joinedIds = _memberships.map((m) => m.folderId).toSet();
      availableForums = allForums.where((f) => !joinedIds.contains(f.id)).toList();
      
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (availableForums.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member is already in all available forums')));
      return;
    }

    FolderModel? selectedForum = availableForums[0];
    String selectedRole = 'member';
    bool isSaving = false;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Add to Forum', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<FolderModel>(
                value: selectedForum,
                dropdownColor: Colors.grey[900],
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Select Forum',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                items: availableForums.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
                onChanged: (v) => setState(() => selectedForum = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                dropdownColor: Colors.grey[900],
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Role in Forum',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                items: ['chair', 'vice_chair', 'head', 'secretary', 'joint_secretary', 'member']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' ').toUpperCase())))
                    .toList(),
                onChanged: (v) => setState(() => selectedRole = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
            ),
            TextButton(
              onPressed: isSaving ? null : () async {
                setState(() => isSaving = true);
                try {
                  await Supabase.instance.client.from('folder_members').insert({
                    'execom_id': selectedForum!.id,
                    'user_id': _user!.id,
                    'execom_role': selectedRole,
                  });
                  Navigator.pop(context);
                  _loadUser();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to forum successfully'), backgroundColor: Colors.green));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                } finally {
                  setState(() => isSaving = false);
                }
              },
              child: Text('Add Member', style: GoogleFonts.inter(color: AppTheme.secondary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeMember() async {
    final supabase = Supabase.instance.client;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Member?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove ${_user?.name}? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await supabase.from('members').delete().eq('id', widget.userId);
      if (_linkedUserId != null) {
        await supabase.from('profiles').delete().eq('id', _linkedUserId!);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error removing member: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _demoteToMember() async {
    final supabase = Supabase.instance.client;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Demote Execom Member?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Text('Are you sure you want to remove ${_user?.name} from their Execom position? They will become a general member and lose access to this app.', style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Demote', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await supabase.from('members').update({'role': 'member'}).eq('id', widget.userId);
      // Remove from all forums
      await supabase.from('folder_members').delete().eq('user_id', widget.userId);
      // Sync to users table using the already-loaded _linkedUserId
      if (_linkedUserId != null) {
        await supabase.from('profiles').update({'role': 'member'}).eq('id', _linkedUserId!);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member demoted successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error demoting member: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _suspendMember() async {
    final supabase = Supabase.instance.client;
    
    int? selectedDays;
    final confirm = await showDialog<int>(
      context: context,
      builder: (context) {
        int duration = 7;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text('Suspend Member?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Select suspension duration for ${_user?.name}:', style: GoogleFonts.inter(color: Colors.white70)),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: duration,
                  dropdownColor: Colors.grey[800],
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('1 Week (7 Days)', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 30, child: Text('1 Month (30 Days)', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 180, child: Text('6 Months (180 Days)', style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (v) => setState(() => duration = v!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, null), child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70))),
              TextButton(
                onPressed: () => Navigator.pop(context, duration),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text('Suspend', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    );

    if (confirm == null) return;

    setState(() => _isLoading = true);
    final suspendedUntil = DateTime.now().add(Duration(days: confirm));
    
    try {
      await supabase.from('members').update({
        'status': 'suspended',
        'suspended_until': suspendedUntil.toIso8601String(),
      }).eq('id', widget.userId);
      
      try {
        final memberData = await supabase.from('members').select('user_id').eq('id', widget.userId).single();
        if (memberData['user_id'] != null) {
          await supabase.from('profiles').update({
            'status': 'suspended',
            'suspended_until': suspendedUntil.toIso8601String(),
          }).eq('id', memberData['user_id']);
        }
      } catch (_) {}
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member suspended successfully')),
        );
        _loadUser();
      }
    } catch (e) {
      debugPrint('Error suspending member: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unsuspendMember() async {
    final supabase = Supabase.instance.client;
    
    setState(() => _isLoading = true);
    try {
      await supabase.from('members').update({
        'status': 'active',
        'suspended_until': null,
      }).eq('id', widget.userId);
      
      try {
        final memberData = await supabase.from('members').select('user_id').eq('id', widget.userId).single();
        if (memberData['user_id'] != null) {
          await supabase.from('profiles').update({
            'status': 'active',
            'suspended_until': null,
          }).eq('id', memberData['user_id']);
        }
      } catch (_) {}
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member unsuspended successfully')),
        );
        _loadUser();
      }
    } catch (e) {
      debugPrint('Error unsuspending member: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Member Details')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_rounded, size: 80, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 24),
              Text(
                'Member Not Found',
                style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Text(
                'The user you are looking for does not exist or has been removed.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  foregroundColor: AppTheme.darkGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final perms = context.read<AuthProvider>().permissions;

    return Scaffold(
      appBar: AppBar(
        title: Text(_user?.name ?? 'Member', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          if (perms?.canEditMembers ?? false)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => EditMemberScreen(user: _user!)),
                );
                if (result == true) {
                  setState(() => _isLoading = true);
                  _loadUser();
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Header card
                      GlassCard(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: AppTheme.secondary.withValues(alpha: 0.2),
                              child: Text(
                                _user!.name.isNotEmpty ? _user!.name[0].toUpperCase() : '?',
                                style: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(_user!.name, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
                            if (_user!.post != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(_user!.post!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(AppRole.formatRoleDisplay(_user!.role), style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(_user!.email, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                            if (_user!.status == 'suspended') ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                                ),
                                child: Text('SUSPENDED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Academic & Membership Details
                      Text('Member Details', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _detailRow(Icons.numbers_outlined, 'Roll Number', _user!.rollNumber ?? 'Not set'),
                            const Divider(height: 24, color: Colors.white10),
                            _detailRow(Icons.school_outlined, 'Branch', _user!.branch ?? 'Not set'),
                            const Divider(height: 24, color: Colors.white10),
                            _detailRow(Icons.phone_outlined, 'Phone', _user!.phone ?? 'Not set'),
                            const Divider(height: 24, color: Colors.white10),
                            _detailRow(Icons.card_membership_outlined, 'Plan', _user!.membershipPlan ?? 'Not set'),
                            const Divider(height: 24, color: Colors.white10),
                            _detailRow(Icons.calendar_today_outlined, 'Joined', _user!.membershipDate != null ? '${_user!.membershipDate!.day}/${_user!.membershipDate!.month}/${_user!.membershipDate!.year}' : 'Not set'),
                            const Divider(height: 24, color: Colors.white10),
                            _detailRow(Icons.event_busy_outlined, 'Expires', _user!.expiryDate != null ? '${_user!.expiryDate!.day}/${_user!.expiryDate!.month}/${_user!.expiryDate!.year}' : 'Not set'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Forum memberships
                      Text('Forum Memberships', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      if (_user!.forum != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.hub_outlined, size: 20, color: AppColors.primary),
                                const SizedBox(width: 12),
                                Expanded(child: Text('Primary Forum: ${_user!.forum}', style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Primary', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ..._memberships.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text(m.folderName ?? 'Folder #${m.folderId}', style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.secondary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(m.folderRole, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      )),

                      // Actions
                      if (perms?.canEditMembers ?? false) ...[
                        const SizedBox(height: 24),
                        Text('Actions', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!['member', 'user'].contains(_user!.role.toLowerCase()))
                              _actionBtn(Icons.arrow_downward, 'Demote to General Member', _demoteToMember, isDestructive: true),
                            _actionBtn(Icons.add_to_photos_outlined, 'Add to Forum', _showAddtoForumDialog),
                            if (perms!.canAssignRoles)
                              _actionBtn(Icons.swap_vert, 'Change Role', _showChangeRoleDialog),
                            if (_user!.role == 'member' && _user!.status == 'active')
                              _actionBtn(Icons.block, 'Suspend Member', _suspendMember, isDestructive: true),
                            if (_user!.role == 'member' && _user!.status == 'suspended')
                              _actionBtn(Icons.how_to_reg, 'Unsuspend Member', _unsuspendMember),
                            if (perms.canRemoveMembers)
                              _actionBtn(Icons.delete_forever, 'Permanently Delete Member', _removeMember, isDestructive: true),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white38),
        const SizedBox(width: 12),
        Text('$label:', style: GoogleFonts.inter(fontSize: 13, color: Colors.white54)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, {bool isDestructive = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (isDestructive ? Colors.red : AppTheme.secondary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (isDestructive ? Colors.red : AppTheme.secondary).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isDestructive ? Colors.red : AppTheme.darkGreen),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: isDestructive ? Colors.red : null,
            )),
          ],
        ),
      ),
    );
  }
}
