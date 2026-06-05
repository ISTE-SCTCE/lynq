import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth_provider.dart';
import '../../models/task_models.dart';

class SubtaskDetailScreen extends StatefulWidget {
  final int taskId;
  final int subtaskId;
  const SubtaskDetailScreen({super.key, required this.taskId, required this.subtaskId});

  @override
  State<SubtaskDetailScreen> createState() => _SubtaskDetailScreenState();
}

class _SubtaskDetailScreenState extends State<SubtaskDetailScreen> {
  final _supabase = Supabase.instance.client;
  SubtaskModel? _subtask;
  bool _isLoading = true;
  bool _isUploading = false;
  final _driveCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _sage = Color(0xFFB8C4A9);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _loadSubtask();
  }

  @override
  void dispose() {
    _driveCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubtask() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('subtasks')
          .select('*, task_proofs(*)')
          .eq('id', widget.subtaskId)
          .single();
      if (mounted) {
        setState(() {
          _subtask = SubtaskModel.fromJson(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadFile() async {
    final auth = context.read<AuthProvider>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'mp4', 'mov', 'docx', 'doc'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() => _isUploading = true);

    try {
      final ext = file.extension ?? 'jpg';
      final path = 'proofs/${widget.subtaskId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _supabase.storage.from('task-proofs').uploadBinary(path, file.bytes!);
      final publicUrl = _supabase.storage.from('task-proofs').getPublicUrl(path);

      String fileType = 'image';
      if (ext == 'pdf') { fileType = 'pdf'; }
      else if (ext == 'mp4' || ext == 'mov') { fileType = 'video'; }
      else if (ext == 'docx' || ext == 'doc') { fileType = 'document'; }

      await _supabase.from('task_proofs').insert({
        'subtask_id': widget.subtaskId,
        'uploaded_by': auth.authUser?.id,
        'file_url': publicUrl,
        'file_type': fileType,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });

      // Update subtask status to awaiting_verification
      await _supabase.from('subtasks')
          .update({'status': 'awaiting_verification'})
          .eq('id', widget.subtaskId);

      _loadSubtask();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proof uploaded! Awaiting review.'), backgroundColor: _teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _submitDriveLink() async {
    if (_driveCtrl.text.trim().isEmpty) return;
    final auth = context.read<AuthProvider>();
    setState(() => _isUploading = true);
    try {
      await _supabase.from('task_proofs').insert({
        'subtask_id': widget.subtaskId,
        'uploaded_by': auth.authUser?.id,
        'file_url': _driveCtrl.text.trim(),
        'file_type': 'drive_link',
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });
      await _supabase.from('subtasks')
          .update({'status': 'awaiting_verification'})
          .eq('id', widget.subtaskId);
      _driveCtrl.clear();
      _loadSubtask();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drive link submitted!'), backgroundColor: _teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        body: const Center(child: CircularProgressIndicator(color: _terracotta)),
      );
    }
    if (_subtask == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(backgroundColor: _bg),
        body: const Center(child: Text('Subtask not found', style: TextStyle(color: Colors.white38))),
      );
    }

    final subtask = _subtask!;
    final auth = context.watch<AuthProvider>();
    final canVerify = auth.permissions?.isAtLeastTier1 ?? false;
    final isMyTask = subtask.assignedTo.contains(auth.authUser?.id);
    final canUpload = isMyTask || (auth.permissions?.isAtLeastTier2 ?? false);
    final needsProof = subtask.proofRequired &&
        subtask.status != TaskStatus.completed &&
        subtask.status != TaskStatus.awaitingVerification;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text('Subtask Detail',
            style: GoogleFonts.spaceGrotesk(color: _cream, fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSubtask,
        color: _terracotta,
        backgroundColor: _surface,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status header
            _buildStatusHeader(subtask),
            const SizedBox(height: 20),
            // Proof history
            if (subtask.proofs.isNotEmpty) ...[
              _buildProofHistory(subtask.proofs, canVerify),
              const SizedBox(height: 20),
            ],
            // Upload section
            if (canUpload && needsProof) ...[
              _buildUploadSection(),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(SubtaskModel subtask) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: subtask.status.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: subtask.status.color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(subtask.status.icon, color: subtask.status.color, size: 20),
                  const SizedBox(width: 8),
                  Text(subtask.status.label,
                      style: GoogleFonts.inter(color: subtask.status.color, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: subtask.priority.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(subtask.priority.label,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: subtask.priority.color, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(subtask.title,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 20, fontWeight: FontWeight.bold, color: _cream)),
              if (subtask.description != null) ...[
                const SizedBox(height: 8),
                Text(subtask.description!,
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white60)),
              ],
              if (subtask.deadline != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14,
                        color: subtask.isOverdue ? Colors.red.shade400 : Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      '${subtask.deadline!.day}/${subtask.deadline!.month}/${subtask.deadline!.year}',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: subtask.isOverdue ? Colors.red.shade400 : Colors.white38),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProofHistory(List<TaskProofModel> proofs, bool canVerify) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Submitted Proofs',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16, fontWeight: FontWeight.bold, color: _cream)),
        const SizedBox(height: 12),
        ...proofs.map((p) => _ProofCard(
          proof: p,
          canVerify: canVerify,
          onApprove: () => _reviewProof(p, 'approved'),
          onReject: () => _reviewProofReject(p),
        )),
      ],
    );
  }

  Widget _buildUploadSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Submit Proof',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16, fontWeight: FontWeight.bold, color: _cream)),
              const SizedBox(height: 6),
              Text('Upload evidence to mark this subtask complete',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
              const SizedBox(height: 16),
              // Notes field
              TextField(
                controller: _notesCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add a note (optional)',
                  hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _teal),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              // File upload button
              _isUploading
                  ? const Center(child: CircularProgressIndicator(color: _terracotta))
                  : Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _uploadFile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _terracotta,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.upload_file_rounded),
                            label: Text('Upload File',
                                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _driveCtrl,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Or paste Google Drive / external link',
                                  hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.04),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: _teal),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _submitDriveLink,
                              style: IconButton.styleFrom(
                                backgroundColor: _teal.withValues(alpha: 0.2),
                                foregroundColor: _teal,
                              ),
                              icon: const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reviewProof(TaskProofModel proof, String status) async {
    final auth = context.read<AuthProvider>();
    try {
      await _supabase.from('task_proofs').update({
        'status': status,
        'reviewed_by': auth.authUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', proof.id);

      if (status == 'approved') {
        await _supabase.from('subtasks')
            .update({'status': 'completed'})
            .eq('id', widget.subtaskId);
        await _supabase.rpc('update_task_completion', params: {'task_id_param': widget.taskId});
      }
      _loadSubtask();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reviewProofReject(TaskProofModel proof) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Reject Proof', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
        content: TextField(
          controller: reasonCtrl,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Reason for rejection',
            hintStyle: GoogleFonts.inter(color: Colors.white38),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: Text('Reject', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final auth = context.read<AuthProvider>();
      await _supabase.from('task_proofs').update({
        'status': 'rejected',
        'reviewed_by': auth.authUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
        'rejection_reason': reasonCtrl.text.trim(),
      }).eq('id', proof.id);
      await _supabase.from('subtasks')
          .update({'status': 'pending'})
          .eq('id', widget.subtaskId);
      _loadSubtask();
    }
  }
}

// ── Proof Card ─────────────────────────────────────────────────────────────

class _ProofCard extends StatelessWidget {
  final TaskProofModel proof;
  final bool canVerify;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  static const _surface = Color(0xFF1E1E1E);
  static const _terracotta = Color(0xFFD97D55);
  static const _sage = Color(0xFFB8C4A9);
  static const _cream = Color(0xFFF4E9D7);

  const _ProofCard({
    required this.proof,
    required this.canVerify,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: proof.status.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: proof.status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(proof.fileTypeIcon, size: 18, color: proof.status.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fileTypeLabel(proof.fileType),
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 13, fontWeight: FontWeight.w700, color: _cream)),
                    Text(proof.status.label,
                        style: GoogleFonts.inter(fontSize: 11, color: proof.status.color)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(proof.fileUrl)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text('View', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (proof.notes != null) ...[
            const SizedBox(height: 10),
            Text(proof.notes!,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
          ],
          if (proof.rejectionReason != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Rejected: ${proof.rejectionReason}',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.red.shade400)),
            ),
          ],
          if (canVerify && proof.status == ProofStatus.pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade400.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text('Reject', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _sage,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text('Approve', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fileTypeLabel(String type) => switch (type) {
    'pdf' => 'PDF Document',
    'video' => 'Video Proof',
    'document' => 'Word Document',
    'drive_link' => 'Drive Link',
    _ => 'Image Proof',
  };
}
