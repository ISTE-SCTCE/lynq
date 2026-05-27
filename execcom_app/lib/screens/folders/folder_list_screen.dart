import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
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
        final count = await supabase.from('folder_members').select('id').eq('folder_id', f.id);
        _memberCounts[f.id] = (count as List).length;
      }
    } catch (e) {
      debugPrint('Error loading folders: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.read<AuthProvider>().permissions;

    return Scaffold(
      appBar: AppBar(title: Text('Forums', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFolders,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _folders.length,
                itemBuilder: (context, i) {
                  final folder = _folders[i];
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
                                  folder.name.substring(0, folder.name.length > 2 ? 2 : folder.name.length),
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
                },
              ),
            ),
    );
  }
}
