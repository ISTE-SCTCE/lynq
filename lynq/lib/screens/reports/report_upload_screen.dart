import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/auth_provider.dart';
import '../../core/permission_engine.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/primary_button.dart';
import '../../core/constants.dart';

class ReportUploadScreen extends StatefulWidget {
  final Map<String, dynamic>? existingReport;
  const ReportUploadScreen({super.key, this.existingReport});

  @override
  State<ReportUploadScreen> createState() => _ReportUploadScreenState();
}

class _ReportUploadScreenState extends State<ReportUploadScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  File? _selectedFile;
  String? _fileName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingReport != null) {
      _titleCtrl.text = widget.existingReport!['title'] ?? '';
      _contentCtrl.text = widget.existingReport!['content'] ?? '';
      if (widget.existingReport!['file_url'] != null) {
        _fileName = widget.existingReport!['file_url'].split('/').last;
      }
      if (widget.existingReport!['file_url'] != null) {
        _fileName = widget.existingReport!['file_url'].split('/').last;
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final size = await file.length();
        if (size > 10 * 1024 * 1024) { // 10 MB limit
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File must be smaller than 10MB'), backgroundColor: Colors.red));
          return;
        }
        setState(() {
          _selectedFile = file;
          _fileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title is required')));
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      String? fileUrl;
      
      if (_selectedFile != null && _fileName != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storagePath = 'reports/$timestamp-$_fileName';
        
        await Supabase.instance.client.storage.from('reports').upload(storagePath, _selectedFile!);
        fileUrl = Supabase.instance.client.storage.from('reports').getPublicUrl(storagePath);
      }

      if (widget.existingReport == null) {
        await Supabase.instance.client.from('event_reports').insert({
          'title': _titleCtrl.text.trim(),
          'content': _contentCtrl.text.trim(),
          'file_url': fileUrl,
          'uploaded_by': Supabase.instance.client.auth.currentUser?.id,
          'created_by_email': Supabase.instance.client.auth.currentUser?.email,
        });
      } else {
        await Supabase.instance.client.from('event_reports').update({
          'title': _titleCtrl.text.trim(),
          'content': _contentCtrl.text.trim(),
          if (fileUrl != null) 'file_url': fileUrl,
        }).eq('id', widget.existingReport!['id']);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report uploaded successfully'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.read<AuthProvider>().permissions;
    if (perms == null || !perms.canUploadReports) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unauthorized')),
        body: const Center(child: Text('You do not have permission to upload reports.')),
      );
    }

    final isEditing = widget.existingReport != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Report' : 'Upload Report', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Report Title',
                  prefixIcon: const Icon(Icons.title, size: 18),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contentCtrl,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'Report Content / Description',
                  prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 120), child: Icon(Icons.article_outlined, size: 18)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _fileName ?? 'No file attached',
                        style: TextStyle(color: _fileName != null ? Colors.white : Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      onPressed: _pickFile,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    if (_fileName != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _selectedFile = null;
                          _fileName = null;
                        }),
                        color: Colors.redAccent,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(text: isEditing ? 'Update Report' : 'Upload Report', onPressed: _submit, isLoading: _isLoading),
            ],
          ),
        ),
      ),
    );
  }
}
