import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as io;
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../models/app_models.dart';
import '../../models/folder_model.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/primary_button.dart';

class BudgetRequestScreen extends StatefulWidget {
  final int? folderId;
  final String? mode; // 'request' or 'allocate'
  const BudgetRequestScreen({super.key, this.folderId, this.mode});

  @override
  State<BudgetRequestScreen> createState() => _BudgetRequestScreenState();
}

class _BudgetRequestScreenState extends State<BudgetRequestScreen> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  int? _selectedFolderId;
  List<FolderModel> _folders = [];
  PlatformFile? _pickedFile;
  bool _isLoading = false;
  bool _isInit = true;

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.folderId;
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      
      // Get role
      final userRes = await client.from('users').select('role').eq('id', userId ?? '').single();
      final role = AppRole.fromString(userRes['role']);

      var query = client.from('folders').select();
      
      if (role >= AppRole.coreExeccom) {
        // No extra filters for core
      } else {
        final folderMembership = client.from('folder_members').select('folder_id').eq('user_id', userId ?? '').then((res) => (res as List).map((m) => m['folder_id']).toList());
        final folderIds = await folderMembership;
        if (folderIds.isEmpty) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        query = query.inFilter('id', folderIds);
      }

      final data = await query.order('name');
      if (mounted) {
        setState(() {
          _folders = (data as List).map((e) => FolderModel.fromJson(e)).toList();
          if (_selectedFolderId == null && _folders.isNotEmpty) {
            _selectedFolderId = _folders.first.id;
          }
          _isInit = false;
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) setState(() => _isInit = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
    );

    if (result != null) {
      setState(() => _pickedFile = result.files.first);
    }
  }


  Future<void> _submit() async {
    if (_amountCtrl.text.isEmpty || _selectedFolderId == null) return;
    setState(() => _isLoading = true);
    
    final isAllocation = widget.mode == 'allocate';
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    try {
      String? proposalUrl;
      
      if (_pickedFile != null) {
        final fileBytes = _pickedFile!.bytes;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_pickedFile!.name}';
        final path = 'proposals/$fileName';

        if (fileBytes != null) {
          await Supabase.instance.client.storage
              .from('budget-proposals')
              .uploadBinary(path, fileBytes);
        } else if (_pickedFile!.path != null) {
          final file = io.File(_pickedFile!.path!);
          await Supabase.instance.client.storage
              .from('budget-proposals')
              .upload(path, file);
        }


        proposalUrl = Supabase.instance.client.storage
            .from('budget-proposals')
            .getPublicUrl(path);
      }

      await Supabase.instance.client.from('budget_requests').insert({
        'folder_id': _selectedFolderId,
        'requested_by': currentUserId,
        'amount': double.parse(_amountCtrl.text.trim()),
        'reason': _reasonCtrl.text.trim(),
        'proposal_url': proposalUrl,
        'status': isAllocation ? 'approved' : 'pending',
        if (isAllocation) 'reviewed_by': currentUserId,
        if (isAllocation) 'reviewed_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAllocation ? 'Allocation added' : 'Request submitted'), 
            backgroundColor: Colors.green
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAllocation = widget.mode == 'allocate';

    return Scaffold(
      appBar: AppBar(title: Text(isAllocation ? 'Allocate Budget' : 'Request Budget', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: _isInit 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_folders.isNotEmpty) ...[
                    Text('Target Folder', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _selectedFolderId,
                          isExpanded: true,
                          dropdownColor: AppTheme.darkGreen,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                          items: _folders.map((f) => DropdownMenuItem<int?>(value: f.id, child: Text(f.name))).toList(),
                          onChanged: (val) => setState(() => _selectedFolderId = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  CustomTextField(label: 'Amount (₹)', controller: _amountCtrl, prefixIcon: Icons.currency_rupee, keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  CustomTextField(label: 'Description / Purpose', controller: _reasonCtrl, prefixIcon: Icons.description_outlined, maxLines: 3),
                  const SizedBox(height: 16),
                  if (!isAllocation) ...[
                    Text('Proposal Document (Optional)', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickFile,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _pickedFile != null ? Icons.description : Icons.upload_file,
                              color: _pickedFile != null ? AppTheme.secondary : Colors.white70,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _pickedFile?.name ?? 'Select proposal file (PDF, DOC, Images)',
                                style: GoogleFonts.inter(
                                  color: _pickedFile != null ? Colors.white : Colors.white54,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_pickedFile != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
                                onPressed: () => setState(() => _pickedFile = null),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  PrimaryButton(
                    text: isAllocation ? 'Add Allocation' : 'Submit Request', 
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
