import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme.dart';
import '../../models/app_models.dart';
import '../../shared/widgets/glass_card.dart';

import 'certificate_template_calibrator_screen.dart';

class CertificateIssuanceScreen extends StatefulWidget {
  final EventModel event;
  const CertificateIssuanceScreen({super.key, required this.event});

  @override
  State<CertificateIssuanceScreen> createState() => _CertificateIssuanceScreenState();
}

class _CertificateIssuanceScreenState extends State<CertificateIssuanceScreen> {
  final _supabase = Supabase.instance.client;

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isProcessing = false;

  /// All attendees fetched from `attendance` JOIN `users`.
  List<Map<String, dynamic>> _attendees = [];

  /// IDs of attendees who already have a certificate for this event.
  Set<String> _alreadyIssuedIds = {};

  // ── Template config ────────────────────────────────────────────────────────
  String? _uploadedTemplateUrl;
  Uint8List? _pickedHtmlBytes;
  String? _pickedHtmlName;

  // ── Progress ────────────────────────────────────────────────────────────────
  int _processedCount = 0;
  String _progressMessage = '';

  // ── Result state (set after a publish run) ─────────────────────────────────
  int? _lastSuccessCount;
  bool _isCompleted = false;

  // ── Derived counts ──────────────────────────────────────────────────────────
  int get _attendeeCount => _attendees.length;
  int get _issuedCount => _alreadyIssuedIds.length;
  int get _pendingCount => _attendeeCount - _issuedCount;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────
  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _lastSuccessCount = null;
    });

    try {
      // 1. Fetch event template config
      final eventRow = await _supabase
          .from('events')
          .select('template_url, attendance_finalized')
          .eq('id', widget.event.id)
          .maybeSingle();

      // 2. Fetch attendance rows
      final attendanceRows = await _supabase
          .from('attendance')
          .select('user_id')
          .eq('event_id', widget.event.id);

      final rows = (attendanceRows as List).cast<Map<String, dynamic>>();

      // 3. Fetch user info for unique user_ids
      final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
      Map<String, Map<String, dynamic>> usersMap = {};
      if (userIds.isNotEmpty) {
        final usersRows = await _supabase
            .from('profiles')
            .select('id, name, roll_number, branch')
            .inFilter('id', userIds);
        for (final u in (usersRows as List)) {
          usersMap[u['id'] as String] = u as Map<String, dynamic>;
        }
      }

      // Build structured attendees list
      final List<Map<String, dynamic>> attendeesList = [];
      // Deduplicate user_ids for certificate generation per event
      final Set<String> seenUserIds = {};
      for (final r in rows) {
        final uid = r['user_id'] as String;
        if (!seenUserIds.contains(uid)) {
          seenUserIds.add(uid);
          attendeesList.add({
            'user_id': uid,
            'users': usersMap[uid],
          });
        }
      }

      // 4. Fetch which user_ids already have a certificate for this event
      final issuedRows = await _supabase
          .from('certificates')
          .select('user_id')
          .eq('event_id', widget.event.id);

      final issuedIds = ((issuedRows as List).cast<Map<String, dynamic>>())
          .map((r) => r['user_id'] as String)
          .toSet();

      if (mounted) {
        setState(() {
          _attendees = attendeesList;
          _alreadyIssuedIds = issuedIds;
          _uploadedTemplateUrl = eventRow?['template_url'] as String?;
          _isCompleted = eventRow?['attendance_finalized'] as bool? ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error loading event stats: $e');
    }
  }

  // ── Image Template Pick / Upload ──────────────────────────────────────────
  Future<void> _pickHtmlTemplate() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _pickedHtmlBytes = result.files.single.bytes;
          _pickedHtmlName = result.files.single.name;
        });
      }
    } catch (e) {
      _showSnack('Error picking image: $e', isError: true);
    }
  }

  Future<void> _uploadHtmlTemplate() async {
    if (_pickedHtmlBytes == null) {
      _showSnack('Please select an image file first.', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressMessage = 'Uploading Image template…';
    });

    try {
      final ext = _pickedHtmlName?.split('.').last ?? 'png';
      final fileName = 'template_event_${widget.event.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = 'templates/$fileName';

      String url = '';
      try {
        await _supabase.storage
            .from('certificate_templates')
            .uploadBinary(path, _pickedHtmlBytes!, fileOptions: FileOptions(contentType: 'image/$ext'));
        url = _supabase.storage.from('certificate_templates').getPublicUrl(path);
      } catch (_) {
        await _supabase.storage
            .from('event_posters')
            .uploadBinary(path, _pickedHtmlBytes!, fileOptions: FileOptions(contentType: 'image/$ext'));
        url = _supabase.storage.from('event_posters').getPublicUrl(path);
      }

      await _supabase
          .from('events')
          .update({
            'template_url': url,
            'certificate_image_url': url,
            'certificate_template_type': 'image',
          })
          .eq('id', widget.event.id);

      setState(() {
        _uploadedTemplateUrl = url;
        _pickedHtmlBytes = null;
        _pickedHtmlName = null;
        _isProcessing = false;
        _progressMessage = '';
      });
      _showSnack('Image certificate template saved successfully!');
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _progressMessage = '';
      });
      _showSnack('Upload failed: $e', isError: true);
    }
  }

  Future<void> _finalizeEvent() async {
    setState(() {
      _isProcessing = true;
      _progressMessage = 'Finalizing event…';
    });
    try {
      await _supabase
          .from('events')
          .update({'attendance_finalized': true})
          .eq('id', widget.event.id);
      
      setState(() {
        _isCompleted = true;
      });
      
      _showSnack('Event marked as Completed!');
    } catch (e) {
      _showSnack('Failed to finalize event: $e', isError: true);
    } finally {
      await _loadStats();
      debugPrint('[Publish Debug] _isCompleted: $_isCompleted, templateUrl: $_uploadedTemplateUrl, attendees: $_attendeeCount, pending: $_pendingCount');
      setState(() {
        _isProcessing = false;
        _progressMessage = '';
      });
    }
  }

  // ── Publish certificates ──────────────────────────────────────────────────
  Future<void> _publishCertificates() async {
    if (_uploadedTemplateUrl == null) {
      _showSnack('Please upload an HTML template first.', isError: true);
      return;
    }
    if (_attendees.isEmpty) {
      _showSnack('No attendees found for this event.', isError: true);
      return;
    }

    final eligible = _attendees.where((row) {
      final uid = row['user_id'] as String?;
      return uid != null && !_alreadyIssuedIds.contains(uid);
    }).toList();

    if (eligible.isEmpty) {
      _showSnack('All $_attendeeCount attendees already have certificates.', isError: false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Publish Certificates?', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
        content: Text(
          'This will generate HTML certificates for ${eligible.length} eligible attendee${eligible.length == 1 ? '' : 's'} of "${widget.event.title}".'
          '${_issuedCount > 0 ? '\n\n$_issuedCount attendee${_issuedCount == 1 ? '' : 's'} already have certificates and will be skipped.' : ''}',
          style: GoogleFonts.inter(color: Colors.white60, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Publish ${eligible.length}', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _progressMessage = 'Starting certificate generation…';
      _lastSuccessCount = null;
    });

    int successCount = 0;
    int errorCount = 0;
    final total = eligible.length;

    for (int i = 0; i < eligible.length; i++) {
      final row = eligible[i];
      final userMap = row['users'] as Map<String, dynamic>?;
      final userId = row['user_id'] as String?;
      final userName = userMap?['name'] as String? ?? 'Member';

      if (userId == null) continue;

      if (mounted) {
        setState(() {
          _processedCount = i + 1;
          _progressMessage = 'Publishing for $userName (${i + 1}/$total)…';
        });
      }

      try {
        final finalCertUrl = 'template:$_uploadedTemplateUrl';
        await Future.delayed(const Duration(milliseconds: 30));

        // Upsert into certificates table
        await _supabase.from('certificates').upsert({
          'user_id': userId,
          'event_id': widget.event.id,
          'student_name': userName,
          'title': 'Certificate of Participation — ${widget.event.title}',
          'description':
              'Awarded for attending ${widget.event.title} on ${_formatDate(widget.event.date)}',
          'file_url': finalCertUrl,
          'issued_by': _supabase.auth.currentUser?.id,
          'issued_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,event_id');

        successCount++;
      } catch (e) {
        debugPrint('Error issuing cert for $userId: $e');
        errorCount++;
      }
    }

    // Re-fetch from DB so counts are always accurate
    await _loadStats();

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _progressMessage = '';
        _lastSuccessCount = successCount;
      });

      final parts = <String>['✓ Published $successCount certificate${successCount == 1 ? '' : 's'}'];
      if (_issuedCount > 0) parts.add('$_issuedCount already existed');
      if (errorCount > 0) parts.add('$errorCount failed');
      _showSnack(parts.join(' · '), isError: errorCount > 0 && successCount == 0);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter()),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Publish Certificates',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          if (!_isLoading && !_isProcessing) ...[
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: Colors.blueAccent),
              tooltip: 'Calibrate Field Positions',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CertificateTemplateCalibratorScreen(
                      eventId: widget.event.id,
                      eventTitle: widget.event.title,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh stats',
              onPressed: _loadStats,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Event info card ──────────────────────────────────
                      _buildEventInfoCard(isDark),
                      const SizedBox(height: 20),

                      // ── Completion status banner ─────────────────────────
                      if (!_isCompleted)
                        _buildLockedBanner()
                      else
                        _buildCompletedBanner(),
                      const SizedBox(height: 20),

                      // ── Stats row ────────────────────────────────────────
                      _buildStatsRow(isDark),
                      const SizedBox(height: 20),

                      // ── Last publish result ───────────────────────────────
                      if (_lastSuccessCount != null) ...[
                        _buildResultBanner(isDark),
                        const SizedBox(height: 20),
                      ],

                      // ── Image Template Management ────────────────────────
                      _buildSectionTitle('Image Certificate Template', isDark),
                      const SizedBox(height: 8),
                      Text(
                        'Configure the image template layout file which will render personalized certificates dynamically for the attendees.',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      _buildHtmlTemplateCard(isDark),
                      const SizedBox(height: 24),

                      // ── Publish CTA ──────────────────────────────────────
                      _buildPublishSection(isDark),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),

                // ── Processing overlay ────────────────────────────────────
                if (_isProcessing) _buildProcessingOverlay(),
              ],
            ),
    );
  }

  // ── Widget builders ───────────────────────────────────────────────────────

  Widget _buildEventInfoCard(bool isDark) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_rounded, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.event.title,
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  if (widget.event.date != null)
                    Text(_formatDate(widget.event.date),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54)),
                ],
              ),
            ),
            if (_isCompleted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 13, color: Colors.green),
                    const SizedBox(width: 5),
                    Text('Completed',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock_rounded, color: Colors.orange, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Certificate Publishing Locked',
                    style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.orange)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Certificates can only be published after the event ends and attendance is finalised. '
            'Mark the event as completed below to enable publishing.',
            style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.orange.withValues(alpha: 0.85),
                height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _finalizeEvent,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text('Mark Event Completed', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Event completed — you can now publish certificates to all attendees.',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(child: _buildStatChip(
            'Attendees', _attendeeCount, Icons.people_rounded, Colors.blueAccent, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatChip(
            'Issued', _issuedCount, Icons.workspace_premium_rounded, Colors.amber, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatChip(
            'Pending', _pendingCount < 0 ? 0 : _pendingCount,
            Icons.pending_rounded, Colors.orangeAccent, isDark)),
      ],
    );
  }

  Widget _buildStatChip(String label, int value, IconData icon, Color color, bool isDark) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text('$value',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black45)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBanner(bool isDark) {
    final success = _lastSuccessCount ?? 0;
    final allDone = success == 0 && _issuedCount == _attendeeCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.withValues(alpha: 0.12),
            Colors.green.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allDone
                      ? 'All certificates already published'
                      : 'Published $success certificate${success == 1 ? '' : 's'}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.green),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_issuedCount of $_attendeeCount attendees now have certificates.',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHtmlTemplateCard(bool isDark) {
    final hasUploadedTemplate = _uploadedTemplateUrl != null;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasUploadedTemplate) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Image Template Configured',
                            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                        const SizedBox(height: 4),
                        Text(
                          'An active image template is attached to this event.',
                          style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Image Template Missing',
                            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
                        const SizedBox(height: 4),
                        Text(
                          'Upload an image file to enable certificate issuance.',
                          style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (_pickedHtmlName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.file_present_rounded, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pickedHtmlName!,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueAccent),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white54 : Colors.black54),
                      onPressed: () {
                        setState(() {
                          _pickedHtmlBytes = null;
                          _pickedHtmlName = null;
                        });
                      },
                    )
                  ],
                ),
              ),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickHtmlTemplate,
                    icon: const Icon(Icons.image_rounded, size: 18),
                    label: Text(_pickedHtmlName != null ? 'Change File' : 'Pick Image File', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (_pickedHtmlBytes != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _uploadHtmlTemplate,
                      icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text('Save Template', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublishSection(bool isDark) {
    final templateReady = _uploadedTemplateUrl != null;

    final canPublish = _isCompleted &&
        templateReady &&
        _attendeeCount > 0 &&
        _pendingCount > 0;

    Widget buildLabel() {
      if (!_isCompleted) {
        return Text('Event Not Yet Completed',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700));
      }
      if (!templateReady) {
        return Text('Upload HTML Template First',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700));
      }
      if (_attendeeCount == 0) {
        return Text('No Attendees Found',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700));
      }
      if (_pendingCount == 0) {
        return Text('All Certificates Already Published',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700));
      }
      return Text(
        'Publish Certificates to $_pendingCount Attendee${_pendingCount == 1 ? '' : 's'}',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Publish Certificates', isDark),
        const SizedBox(height: 10),

        if (_attendeeCount == 0 && _isCompleted) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.people_outline_rounded,
                    color: isDark ? Colors.white38 : Colors.black38, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No attendance records found for this event. '
                    'Certificates cannot be issued without attendees.',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black54,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Main publish button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_isProcessing || !canPublish) ? null : _publishCertificates,
            icon: const Icon(Icons.workspace_premium_rounded),
            label: buildLabel(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.06),
              disabledForegroundColor: isDark ? Colors.white30 : Colors.black26,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildProcessingOverlay() {
    final total = _attendees.where((r) {
      final uid = r['user_id'] as String?;
      return uid != null && !_alreadyIssuedIds.contains(uid);
    }).length;

    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  _progressMessage,
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                if (total > 0) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: total > 0 ? _processedCount / total : 0,
                    backgroundColor: Colors.white12,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_processedCount / $total',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12, color: Colors.white38),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
