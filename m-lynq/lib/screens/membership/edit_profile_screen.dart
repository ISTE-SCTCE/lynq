import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _rollNoCtrl;
  late TextEditingController _branchCtrl;
  late TextEditingController _yearCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    final profile = auth.profile ?? {};

    _nameCtrl = TextEditingController(text: profile['name'] as String? ?? auth.name);
    _phoneCtrl = TextEditingController(text: profile['phone'] as String? ?? '');
    _rollNoCtrl = TextEditingController(text: profile['roll_number'] as String? ?? '');
    _branchCtrl = TextEditingController(text: profile['branch'] as String? ?? '');
    _yearCtrl = TextEditingController(text: profile['year'] as String? ?? '');
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final updates = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'roll_number': _rollNoCtrl.text.trim(),
        'branch': _branchCtrl.text.trim(),
        'year': _yearCtrl.text.trim(),
      };

      // Update users table
      await Supabase.instance.client
          .from('users')
          .update(updates)
          .eq('id', userId);

      final memberUpdates = Map<String, dynamic>.from(updates)..remove('year');

      // Upsert members row — inserts if not found, updates if exists.
      // Eliminates the redundant select-before-write round-trip.
      await Supabase.instance.client
          .from('members')
          .upsert({...memberUpdates, 'user_id': userId}, onConflict: 'user_id');

      // Refresh auth state
      await ref.read(authProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Edit Profile', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildTextField('Full Name', _nameCtrl, Icons.person_outline),
            const SizedBox(height: 16),
            _buildTextField('Phone Number', _phoneCtrl, Icons.phone_outlined, isNumber: true),
            const SizedBox(height: 16),
            _buildTextField('Roll Number', _rollNoCtrl, Icons.numbers_outlined),
            const SizedBox(height: 16),
            _buildTextField('Branch (e.g., CSE)', _branchCtrl, Icons.school_outlined),
            const SizedBox(height: 16),
            _buildTextField('Year (e.g., 2026)', _yearCtrl, Icons.calendar_today_outlined, isNumber: true),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6FA4AF), // teal
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isLoading ? null : _saveProfile,
                child: _isLoading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Save Changes', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: GoogleFonts.inter(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF6FA4AF)), // teal
        ),
      ),
    );
  }
}
