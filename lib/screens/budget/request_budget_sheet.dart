import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';

class RequestBudgetSheet extends StatefulWidget {
  final List<int> myFolderIds;
  const RequestBudgetSheet({super.key, required this.myFolderIds});

  @override
  State<RequestBudgetSheet> createState() => _RequestBudgetSheetState();
}

class _RequestBudgetSheetState extends State<RequestBudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  
  bool _isLoading = false;
  io.File? _selectedFile;
  int? _selectedFolderId;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = io.File(result.files.single.path!);
      });
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() || _selectedFolderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a forum')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      String? fileUrl;
      if (_selectedFile != null) {
        final ext = _selectedFile!.path.split('.').last;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
        final filePath = 'proposals/${user.id}/$fileName';
        
        await Supabase.instance.client.storage
            .from('reports')
            .upload(filePath, _selectedFile!);
            
        fileUrl = Supabase.instance.client.storage
            .from('reports')
            .getPublicUrl(filePath);
      }

      await Supabase.instance.client.from('budget_requests').insert({
        'execom_id': _selectedFolderId,
        'requested_by': user.id,
        'amount': double.parse(_amountController.text),
        'reason': _reasonController.text,
        'proposal_url': fileUrl,
        'status': 'pending',
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Budget Request Submitted!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161925) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Request Budget',
                  style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedFolderId,
              decoration: const InputDecoration(
                labelText: 'Select Forum',
                border: OutlineInputBorder(),
              ),
              items: widget.myFolderIds.map((id) {
                return DropdownMenuItem(
                  value: id,
                  child: Text('Forum ID #$id'),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedFolderId = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_rupee),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) return 'Enter amount';
                if (double.tryParse(val) == null) return 'Invalid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Event Name / Reason',
                border: OutlineInputBorder(),
              ),
              validator: (val) => val == null || val.isEmpty ? 'Enter reason' : null,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_selectedFile != null ? 'File Attached' : 'Attach Proposal (PDF/Doc)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (_selectedFile != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _selectedFile!.path.split(io.Platform.pathSeparator).last,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _submitRequest,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                backgroundColor: const Color(0xFF16C07A),
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text('Submit Request', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
