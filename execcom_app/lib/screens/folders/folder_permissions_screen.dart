import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/folder_model.dart';
import '../../shared/widgets/glass_card.dart';

class FolderPermissionsScreen extends StatefulWidget {
  final int folderId;
  const FolderPermissionsScreen({super.key, required this.folderId});

  @override
  State<FolderPermissionsScreen> createState() => _FolderPermissionsScreenState();
}

class _FolderPermissionsScreenState extends State<FolderPermissionsScreen> {
  Map<String, bool> _permissions = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final data = await Supabase.instance.client
          .from('folder_permissions')
          .select()
          .eq('folder_id', widget.folderId);
      final perms = (data as List).map((e) => FolderPermissionModel.fromJson(e)).toList();
      _permissions = {for (final p in perms) p.feature: p.allowed};
    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);
    try {
      for (final entry in _permissions.entries) {
        await Supabase.instance.client
            .from('folder_permissions')
            .update({'allowed': entry.value})
            .eq('folder_id', widget.folderId)
            .eq('feature', entry.key);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Folder Permissions', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _savePermissions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Toggle which features are enabled for execcom-level members in this folder.',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
                ...FolderFeature.all.map((feature) => GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SwitchListTile(
                    title: Text(FolderFeature.label(feature), style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    value: _permissions[feature] ?? false,
                    activeColor: AppTheme.secondary,
                    onChanged: (v) => setState(() => _permissions[feature] = v),
                  ),
                )),
              ],
            ),
    );
  }
}
