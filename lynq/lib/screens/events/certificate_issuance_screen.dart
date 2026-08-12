import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme.dart';
import '../../models/app_models.dart';
import 'template_editor_screen.dart';
import '../../shared/utils/dynamic_template_parser.dart';
import '../../shared/utils/dynamic_certificate_pdf_engine.dart';

class CertificateIssuanceScreen extends StatefulWidget {
  final EventModel event;
  const CertificateIssuanceScreen({super.key, required this.event});

  @override
  State<CertificateIssuanceScreen> createState() => _CertificateIssuanceScreenState();
}

class _CertificateIssuanceScreenState extends State<CertificateIssuanceScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isProcessing = false;

  List<Map<String, dynamic>> _attendees = [];
  Set<String> _alreadyIssuedIds = {};

  String? _activeTemplateId;
  String? _activeTemplateUrl;
  List<FieldConfig> _fieldConfigs = [];

  int _processedCount = 0;
  int _failedCount = 0;
  String _progressMessage = '';
  int? _lastSuccessCount;
  bool _isCompleted = false;

  static const Color accentGreen = Color(0xFF16C07A);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color darkCardBg = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _loadStatsAndTemplate();
  }

  Future<void> _loadStatsAndTemplate() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Event Status
      final evRow = await _supabase
          .from('events')
          .select('attendance_finalized, certificate_image_url, template_url')
          .eq('id', widget.event.id)
          .maybeSingle();

      if (evRow != null) {
        _isCompleted = evRow['attendance_finalized'] ?? false;
        _activeTemplateUrl = (evRow['certificate_image_url'] as String?) ?? (evRow['template_url'] as String?);
      }

      // 2. Try fetching Active Template & Fields from certificate_templates table
      try {
        final tmplRow = await _supabase
            .from('certificate_templates')
            .select('id, template_file_url')
            .eq('event_id', widget.event.id)
            .order('created_at', ascending: false)
            .maybeSingle();

        if (tmplRow != null) {
          _activeTemplateId = tmplRow['id'] as String?;
          _activeTemplateUrl = (tmplRow['template_file_url'] as String?) ?? _activeTemplateUrl;
        }
      } catch (e) {
        debugPrint('certificate_templates table check: $e');
      }

      _activeTemplateId ??= 'event_${widget.event.id}';

      if (_activeTemplateId != null) {
        try {
          final fieldsRes = await _supabase
              .from('certificate_template_fields')
              .select()
              .eq('template_id', _activeTemplateId!);
          final List rows = fieldsRes as List? ?? [];
          _fieldConfigs = rows.map((r) => FieldConfig.fromMap(r as Map<String, dynamic>)).toList();
        } catch (_) {}
      }

      // 3. Fetch Registered Attendees
      final attRes = await _supabase
          .from('attendance')
          .select('user_id')
          .eq('event_id', widget.event.id);
      final List attRows = attRes as List? ?? [];
      final userIds = attRows.map((r) => r['user_id'] as String).toSet().toList();

      if (userIds.isNotEmpty) {
        final profilesRes = await _supabase
            .from('profiles')
            .select('id, name')
            .inFilter('id', userIds);
        final List profiles = profilesRes as List? ?? [];
        final profileMap = Map.fromEntries(profiles.map((p) => MapEntry(p['id'] as String, p['name'] as String? ?? 'Member')));

        _attendees = userIds.map((uid) => {
          'user_id': uid,
          'name': profileMap[uid] ?? 'Member',
        }).toList();
      }

      // 4. Fetch Already Issued Certificates
      final certsRes = await _supabase
          .from('certificates')
          .select('user_id')
          .eq('event_id', widget.event.id);
      final List certRows = certsRes as List? ?? [];
      _alreadyIssuedIds = certRows.map((r) => r['user_id'] as String).toSet();

    } catch (e) {
      debugPrint('Error loading stats: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadNewTemplate() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'svg'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() {
      _isProcessing = true;
      _progressMessage = 'Uploading template image...';
    });

    try {
      final ext = file.extension ?? 'png';
      final storagePath = 'templates/${widget.event.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      String publicUrl = '';

      // 1. Storage Upload with multi-bucket fallback
      try {
        await _supabase.storage.from('certificate_templates').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
        publicUrl = _supabase.storage.from('certificate_templates').getPublicUrl(storagePath);
      } catch (sErr) {
        debugPrint('certificate_templates bucket fallback: $sErr');
        final fallbackPath = 'certificates/${widget.event.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _supabase.storage.from('event_posters').uploadBinary(
          fallbackPath,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
        publicUrl = _supabase.storage.from('event_posters').getPublicUrl(fallbackPath);
      }

      // 2. Table Insert with fallback
      try {
        final tmplRes = await _supabase.from('certificate_templates').insert({
          'event_id': widget.event.id,
          'name': 'Template - ${widget.event.title}',
          'template_file_url': publicUrl,
          'template_format': 'image',
          'natural_width': 2000,
          'natural_height': 1414,
        }).select('id').maybeSingle();

        if (tmplRes != null && tmplRes['id'] != null) {
          _activeTemplateId = tmplRes['id'] as String;
        }
      } catch (tErr) {
        debugPrint('certificate_templates table fallback: $tErr');
        _activeTemplateId = 'event_${widget.event.id}';
      }

      _activeTemplateUrl = publicUrl;

      // 3. Update events table
      await _supabase.from('events').update({
        'certificate_image_url': publicUrl,
        'template_url': publicUrl,
        'certificate_template_type': 'image',
      }).eq('id', widget.event.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template uploaded successfully! Opening layout editor...')),
        );
        _openTemplateEditor();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload template: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progressMessage = '';
        });
        _loadStatsAndTemplate();
      }
    }
  }

  void _openTemplateEditor() {
    if (_activeTemplateUrl == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateEditorScreen(
          event: widget.event,
          templateId: _activeTemplateId ?? 'event_${widget.event.id}',
          templateUrl: _activeTemplateUrl!,
        ),
      ),
    ).then((_) => _loadStatsAndTemplate());
  }

  Future<void> _generateAllCertificates() async {
    if (_activeTemplateUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a template image first.')),
      );
      return;
    }

    final eligible = _attendees.where((a) => !_alreadyIssuedIds.contains(a['user_id'])).toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All attendees already have certificates.')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _failedCount = 0;
      _progressMessage = 'Preparing batch generation...';
    });

    int successCount = 0;
    final total = eligible.length;

    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(_activeTemplateUrl!));
      final res = await req.close();
      final imageBytes = await res.fold<List<int>>(<int>[], (acc, data) => acc..addAll(data));

      final dateStr = widget.event.date != null
          ? '${widget.event.date!.day}/${widget.event.date!.month}/${widget.event.date!.year}'
          : '';

      for (int i = 0; i < eligible.length; i++) {
        final attendee = eligible[i];
        final userId = attendee['user_id'] as String;
        final name = attendee['name'] as String;

        setState(() {
          _progressMessage = 'Generating for $name (${i + 1}/$total)...';
          _processedCount = i + 1;
        });

        try {
          final certNum = 'ISTE-${widget.event.id}-${userId.replaceAll('-', '').substring(0, 6).toUpperCase()}';
          final fieldValues = DynamicTemplateParser.resolveValues(
            event: {
              'title': widget.event.title,
              'date': dateStr,
              'location': widget.event.location,
            },
            studentName: name,
            certificateId: certNum,
          );

          final pdfBytes = await DynamicCertificatePdfEngine.renderImageCertificate(
            imageBytes: imageBytes,
            fieldValues: fieldValues,
            fieldConfigs: _fieldConfigs,
          );

          final storagePath = '${widget.event.id}/$userId.pdf';
          await _supabase.storage.from('certificates').uploadBinary(
            storagePath,
            pdfBytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
          );

          final signedUrl = await _supabase.storage.from('certificates').createSignedUrl(storagePath, 31536000);

          await _supabase.from('certificates').upsert({
            'event_id': widget.event.id,
            'user_id': userId,
            'template_id': _activeTemplateId,
            'student_name': name,
            'certificate_number': certNum,
            'certificate_url': signedUrl,
            'storage_path': storagePath,
            'file_url': signedUrl,
            'title': 'Certificate of Participation — ${widget.event.title}',
            'status': 'completed',
            'issued_at': DateTime.now().toIso8601String(),
          }, onConflict: 'event_id,user_id');

          successCount++;
        } catch (err) {
          debugPrint('Error generating cert for $userId: $err');
          _failedCount++;
        }
      }
    } catch (e) {
      debugPrint('Batch generation error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progressMessage = '';
          _lastSuccessCount = successCount;
        });
        _loadStatsAndTemplate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _attendees.length - _alreadyIssuedIds.length;
    final dateStr = widget.event.date != null
        ? '${widget.event.date!.day}/${widget.event.date!.month}/${widget.event.date!.year}'
        : 'N/A';

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Publish Certificates', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: _loadStatsAndTemplate),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Details Card
                  _buildDarkCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.event.title, style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                            const SizedBox(width: 6),
                            Text('Date: $dateStr', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                            const SizedBox(width: 16),
                            const Icon(Icons.people, size: 14, color: Colors.white70),
                            const SizedBox(width: 6),
                            Text('Attendees: ${_attendees.length}', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Template Card with Clean Responsive Action Buttons
                  _buildDarkCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Certificate Template', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: accentGreen)),
                        const SizedBox(height: 8),
                        if (_activeTemplateUrl != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.check_circle, size: 16, color: accentGreen),
                              const SizedBox(width: 6),
                              Text('Active Image Template Uploaded', style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.edit_note, size: 18),
                                label: const Text('Edit Tag Positions & Layout'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accentGreen,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                onPressed: _openTemplateEditor,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.upload_file, size: 16),
                                label: const Text('Change Template Image'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                onPressed: _isProcessing ? null : _uploadNewTemplate,
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            'No certificate template uploaded yet. Upload a PNG or JPG background template image to get started.',
                            style: GoogleFonts.inter(fontSize: 13, color: Colors.amber[300]),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text('Upload PNG / JPG Template'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            ),
                            onPressed: _isProcessing ? null : _uploadNewTemplate,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Batch Generation Progress Bar
                  if (_isProcessing)
                    _buildDarkCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_progressMessage, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _attendees.isEmpty ? 0 : (_processedCount / (_attendees.length - _alreadyIssuedIds.length)).clamp(0.0, 1.0),
                              color: accentGreen,
                              backgroundColor: Colors.white12,
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_lastSuccessCount != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accentGreen.withOpacity(0.12),
                        border: Border.all(color: accentGreen.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.stars, color: accentGreen, size: 20),
                          const SizedBox(width: 10),
                          Text('Published $_lastSuccessCount certificates successfully!', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Big Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 22),
                      label: Text(
                        'Generate All Pending Certificates ($pendingCount)',
                        style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (pendingCount > 0 && _activeTemplateUrl != null && !_isProcessing) ? Colors.amber[700] : Colors.white12,
                        foregroundColor: (pendingCount > 0 && _activeTemplateUrl != null && !_isProcessing) ? Colors.black : Colors.white38,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: (pendingCount == 0 || _activeTemplateUrl == null || _isProcessing) ? null : _generateAllCertificates,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDarkCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: darkCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: child,
    );
  }
}
