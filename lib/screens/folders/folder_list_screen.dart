import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/permission_engine.dart';
import '../../models/folder_model.dart';
import '../../shared/widgets/glass_card.dart';

class FolderListScreen extends StatefulWidget {
  const FolderListScreen({super.key});

  @override
  State<FolderListScreen> createState() => _FolderListScreenState();
}

class _FolderListScreenState extends State<FolderListScreen> {
  List<FolderModel> _folders = [];
  Map<int, int> _memberCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final supabase = Supabase.instance.client;
    try {
      final data = await supabase.from('folders').select().eq('is_forum', true).order('sort_order');
      _folders = (data as List).map((e) => FolderModel.fromJson(e)).toList();

      // Count members per folder
      for (final f in _folders) {
        final count = await supabase.from('folder_members').select('id').eq('execom_id', f.id);
        _memberCounts[f.id] = (count as List).length;
      }
    } catch (e) {
      debugPrint('Error loading folders: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _getCategory(String name) {
    final lower = name.toLowerCase();
    if (lower == 'exis' || lower == 'genesis' || lower == 'bits' || lower == 'torq') {
      return 'Forums';
    } else if (lower == 'swas') {
      return 'Sub-Society';
    } else {
      return 'Functional Teams';
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.read<AuthProvider>().permissions;

    // Group folders
    final Map<String, List<FolderModel>> groupedFolders = {
      'Forums': [],
      'Sub-Society': [],
      'Functional Teams': [],
    };

    for (final folder in _folders) {
      final category = _getCategory(folder.name);
      groupedFolders[category]?.add(folder);
    }

    return Scaffold(
      appBar: AppBar(title: Text('Teams', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFolders,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (groupedFolders['Forums']!.isNotEmpty) ...[
                    _buildSectionHeader('Forums'),
                    const SizedBox(height: 12),
                    ...groupedFolders['Forums']!.map((f) => _buildFolderCard(f, perms)),
                    const SizedBox(height: 24),
                  ],
                  if (groupedFolders['Sub-Society']!.isNotEmpty) ...[
                    _buildSectionHeader('Sub-Society'),
                    const SizedBox(height: 12),
                    ...groupedFolders['Sub-Society']!.map((f) => _buildFolderCard(f, perms)),
                    const SizedBox(height: 24),
                  ],
                  if (groupedFolders['Functional Teams']!.isNotEmpty) ...[
                    _buildSectionHeader('Functional Teams'),
                    const SizedBox(height: 12),
                    ...groupedFolders['Functional Teams']!.map((f) => _buildFolderCard(f, perms)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.spaceGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : AppTheme.darkGreen,
      ),
    );
  }

  Widget _buildFolderCard(FolderModel folder, PermissionEngine? perms) {
    final count = _memberCounts[folder.id] ?? 0;
    final userRole = perms?.folderRoleIn(folder.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/folders/${folder.id}'),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    folder.name.substring(0, folder.name.length > 2 ? 2 : folder.name.length).toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count members${userRole != null ? ' · You: $userRole' : ''}',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
