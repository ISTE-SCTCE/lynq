import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_model.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/primary_button.dart';

class EditMemberScreen extends StatefulWidget {
  final UserModel user;
  const EditMemberScreen({super.key, required this.user});

  @override
  State<EditMemberScreen> createState() => _EditMemberScreenState();
}

class _EditMemberScreenState extends State<EditMemberScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _rollNoCtrl;
  late TextEditingController _branchCtrl;
  late TextEditingController _yearCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.name);
    _phoneCtrl = TextEditingController(text: widget.user.phone ?? '');
    _rollNoCtrl = TextEditingController(text: widget.user.rollNumber ?? '');
    _branchCtrl = TextEditingController(text: widget.user.branch ?? '');
    _yearCtrl = TextEditingController(text: widget.user.year ?? '');
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);
    
    try {
      final updates = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'roll_number': _rollNoCtrl.text.trim(),
        'branch': _branchCtrl.text.trim(),
        'year': _yearCtrl.text.trim(),
      };

      await Supabase.instance.client
          .from('users')
          .update(updates)
          .eq('id', widget.user.id);
          
      // Also update the unified members table if it exists
      final profileRes = await Supabase.instance.client
          .from('members')
          .select('user_id')
          .eq('user_id', widget.user.id);
          
      if ((profileRes as List).isNotEmpty) {
        await Supabase.instance.client
            .from('members')
            .update({
              'name': _nameCtrl.text.trim(),
              'phone': _phoneCtrl.text.trim(),
              'roll_number': _rollNoCtrl.text.trim(),
              'department': _branchCtrl.text.trim(), // In members table it's typically 'department'
              'year': _yearCtrl.text.trim(),
            })
            .eq('user_id', widget.user.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member details updated successfully'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // true indicates success
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
      appBar: AppBar(
        title: Text('Edit Member', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          child: Column(
            children: [
              CustomTextField(
                label: 'Full Name',
                controller: _nameCtrl,
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                label: 'Phone Number',
                controller: _phoneCtrl,
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                label: 'Roll Number',
                controller: _rollNoCtrl,
                prefixIcon: Icons.numbers_outlined,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                label: 'Branch (e.g., CSE)',
                controller: _branchCtrl,
                prefixIcon: Icons.school_outlined,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                label: 'Year (e.g., 2026)',
                controller: _yearCtrl,
                prefixIcon: Icons.calendar_today_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                text: 'Save Changes',
                onPressed: _submit,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
