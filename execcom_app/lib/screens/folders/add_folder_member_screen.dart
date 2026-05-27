import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/primary_button.dart';

class AddFolderMemberScreen extends StatefulWidget {
  final int folderId;
  const AddFolderMemberScreen({super.key, required this.folderId});

  @override
  State<AddFolderMemberScreen> createState() => _AddFolderMemberScreenState();
}

class _AddFolderMemberScreenState extends State<AddFolderMemberScreen> {
  final _searchCtrl = TextEditingController();
  List<UserModel> _availableUsers = [];
  List<UserModel> _allGlobalUsers = [];
  Set<String> _existingUserIds = {};
  bool _isLoading = true;
  String _searchQuery = '';

  // Quick Enrollment Controllers
  final _quickNameCtrl = TextEditingController();
  final _quickEmailCtrl = TextEditingController();
  final _quickPhoneCtrl = TextEditingController();
  final _quickRollCtrl = TextEditingController();
  final _quickPostCtrl = TextEditingController();
  String _quickRoleInFolder = 'member';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _quickNameCtrl.dispose();
    _quickEmailCtrl.dispose();
    _quickPhoneCtrl.dispose();
    _quickRollCtrl.dispose();
    _quickPostCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      
      // 1. Get existing members to exclude them
      final existingData = await supabase
          .from('folder_members')
          .select('user_id')
          .eq('folder_id', widget.folderId);
      
      _existingUserIds = (existingData as List).map((e) => e['user_id'] as String).toSet();

      // 2. Get all users
      final userData = await supabase.from('users').select().order('name');
      _allGlobalUsers = (userData as List).map((e) => UserModel.fromJson(e)).toList();
      
      _availableUsers = _allGlobalUsers
          .where((u) => !_existingUserIds.contains(u.id))
          .toList();

    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<UserModel> get _filteredUsers {
    if (_searchQuery.trim().isEmpty) return _availableUsers;
    final query = _searchQuery.trim().toLowerCase();
    return _availableUsers.where((u) => 
      u.name.toLowerCase().contains(query) || 
      u.email.toLowerCase().contains(query) ||
      (u.phone ?? '').contains(query) ||
      (u.rollNumber ?? '').toLowerCase().contains(query)
    ).toList();
  }

  UserModel? get _alreadyInForumUser {
    if (_searchQuery.trim().isEmpty) return null;
    final query = _searchQuery.trim().toLowerCase();
    
    try {
      return _allGlobalUsers.firstWhere(
        (u) => _existingUserIds.contains(u.id) && (
          u.name.toLowerCase().contains(query) || 
          u.email.toLowerCase().contains(query) ||
          (u.phone ?? '').contains(query) ||
          (u.rollNumber ?? '').toLowerCase().contains(query)
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _addMember(UserModel user, String role) async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('folder_members').insert({
        'folder_id': widget.folderId,
        'user_id': user.id,
        'folder_role': role,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} added as $role'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRolePicker(UserModel user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HeaderHandle(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Role for ${user.name}', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _roleOption('chair', 'Forum Chair', user),
            _roleOption('vice_chair', 'Vice Chair', user),
            _roleOption('head', 'Forum Head', user),
            _roleOption('secretary', 'Secretary', user),
            _roleOption('joint_secretary', 'Joint Secretary', user),
            _roleOption('member', 'Committee Member', user),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _roleOption(String role, String label, UserModel user) {
    return ListTile(
      title: Text(label, style: GoogleFonts.inter()),
      trailing: const Icon(Icons.add_circle_outline, color: AppTheme.secondary),
      onTap: () {
        Navigator.pop(context);
        _addMember(user, role);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add Forum Member', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: CustomTextField(
              label: 'Search by name or email',
              controller: _searchCtrl,
              prefixIcon: Icons.search,
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _filteredUsers.isEmpty
                  ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredUsers.length,
                    itemBuilder: (ctx, i) {
                      final user = _filteredUsers[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showRolePicker(user),
                          child: GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                                  child: Text(
                                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', 
                                    style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold)
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(user.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                      Text(user.email, style: GoogleFonts.inter(fontSize: 12, color: Colors.white60)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.add_circle_outline, color: AppTheme.secondary, size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. Initial State: Empty search
    if (_searchQuery.trim().isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_search_outlined, size: 64, color: isDark ? AppTheme.secondary : AppTheme.darkGreen),
              ),
              const SizedBox(height: 24),
              Text('Who are you looking for?', 
                style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Search our member directory to quickly add them to this forum.', 
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 40),
            ],
          ),
        ),
      );
    }

    final alreadyIn = _alreadyInForumUser;
    if (alreadyIn != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
              const SizedBox(height: 24),
              Text(alreadyIn.name, style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('This user is already a member of this forum.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => setState(() => _searchCtrl.clear()),
                child: const Text('Clear Search'),
              )
            ],
          ),
        ),
      );
    }
    return _buildQuickEnrollmentForm();
  }

  Widget _buildQuickEnrollmentForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.person_search_outlined, size: 48, color: AppTheme.secondary),
          const SizedBox(height: 16),
          Text('MEMBER NOT IN DIRECTORY', 
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondary, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Text('Enroll "${_searchQuery}"', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('This person isn\'t in our records yet. Fill the details below to add them to this forum and the main directory instantly.', 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 32),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CustomTextField(label: 'Full Name', controller: _quickNameCtrl, prefixIcon: Icons.badge_outlined),
                const SizedBox(height: 16),
                CustomTextField(label: 'Email Address', controller: _quickEmailCtrl, prefixIcon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 16),
                CustomTextField(label: 'Phone (WhatsApp)', controller: _quickPhoneCtrl, prefixIcon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: CustomTextField(label: 'Roll No', controller: _quickRollCtrl, prefixIcon: Icons.numbers_outlined)),
                    const SizedBox(width: 12),
                    Expanded(child: CustomTextField(label: 'Forum Post', controller: _quickPostCtrl, prefixIcon: Icons.work_outline)),
                  ],
                ),
                const SizedBox(height: 20),
                _buildDropdownSmall('Role in Forum', _quickRoleInFolder, 
                  ['chair', 'vice_chair', 'head', 'secretary', 'joint_secretary', 'member'], 
                  (v) => setState(() => _quickRoleInFolder = v!)
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  text: 'Create & Add to Forum', 
                  isLoading: _isLoading,
                  onPressed: _quickCreateAndAdd,
                  icon: Icons.flash_on_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDropdownSmall(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1A),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item.replaceAll('_', ' ').toUpperCase()))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _quickCreateAndAdd() async {
    if (_quickEmailCtrl.text.isEmpty || _quickNameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and Email are required')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Create user
      final res = await Supabase.instance.client.functions.invoke('admin-create-user', body: {
        'name': _quickNameCtrl.text.trim(),
        'email': _quickEmailCtrl.text.trim(),
        'phone': _quickPhoneCtrl.text.trim(),
        'roll_number': _quickRollCtrl.text.trim(),
        'role': 'member', // Default global role
        'post': _quickPostCtrl.text.trim(),
      });

      if (res.status != 200) throw res.data['error'] ?? 'Creation failed';

      final newUserId = res.data['user']['id'];

      // 2. Add to folder
      await Supabase.instance.client.from('folder_members').insert({
        'folder_id': widget.folderId,
        'user_id': newUserId,
        'folder_role': _quickRoleInFolder,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member enrolled and added to forum!'), backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class HeaderHandle extends StatelessWidget {
  const HeaderHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
