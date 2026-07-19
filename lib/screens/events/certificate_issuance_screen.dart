import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../models/app_models.dart';
import '../../shared/widgets/glass_card.dart';

class CertificateIssuanceScreen extends StatefulWidget {
  final EventModel event;
  const CertificateIssuanceScreen({super.key, required this.event});

  @override
  State<CertificateIssuanceScreen> createState() => _CertificateIssuanceScreenState();
}

class _CertificateIssuanceScreenState extends State<CertificateIssuanceScreen> {
  final _supabase = Supabase.instance.client;

  // State
  bool _isLoading = true;
  bool _isProcessing = false;
  int _attendeeCount = 0;
  int _alreadyIssued = 0;
  List<Map<String, dynamic>> _attendees = [];

  // Template config
  String? _templateLocalPath;
  Uint8List? _templateBytes;
  String? _uploadedTemplateUrl;
  double _nameX = 0.5; // Relative X (0.0–1.0)
  double _nameY = 0.5; // Relative Y (0.0–1.0)
  int _fontSize = 42;
  Color _textColor = const Color(0xFF1A1A1A);

  // Progress
  int _processedCount = 0;
  String _progressMessage = '';

  @override
  void initState() {
    super.initState();
    _loadEventStats();
  }

  Future<void> _loadEventStats() async {
    try {
      // Fetch attendees with their user info
      final attendanceRows = await _supabase
          .from('attendance')
          .select('user_id, users(id, name, roll_number, branch)')
          .eq('event_id', widget.event.id);

      final rows = (attendanceRows as List).cast<Map<String, dynamic>>();

      // Check already issued
      final issued = await _supabase
          .from('certificates')
          .select('user_id')
          .eq('event_id', widget.event.id);

      // Check if a template config already exists
      final configRows = await _supabase
          .from('event_certificate_config')
          .select()
          .eq('event_id', widget.event.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _attendees = rows;
          _attendeeCount = rows.length;
          _alreadyIssued = (issued as List).length;
          if (configRows != null) {
            _uploadedTemplateUrl = configRows['template_url'] as String?;
            _nameX = (configRows['name_x'] as num?)?.toDouble() ?? 0.5;
            _nameY = (configRows['name_y'] as num?)?.toDouble() ?? 0.5;
            _fontSize = configRows['font_size'] as int? ?? 42;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error loading event stats: $e');
    }
  }

  Future<void> _pickTemplate() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _templateBytes = result.files.single.bytes;
        _templateLocalPath = result.files.single.name;
        _uploadedTemplateUrl = null; // reset uploaded url since we have a new file
      });
    }
  }

  Future<void> _uploadTemplateAndSaveConfig() async {
    if (_templateBytes == null) {
      _showSnack('Please pick a certificate template image first.', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressMessage = 'Uploading template...';
    });

    try {
      final fileName = 'template_event_${widget.event.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      await _supabase.storage
          .from('certificate-templates')
          .uploadBinary(fileName, _templateBytes!, fileOptions: const FileOptions(upsert: true, contentType: 'image/png'));

      final url = _supabase.storage.from('certificate-templates').getPublicUrl(fileName);

      // Save config
      await _supabase.from('event_certificate_config').upsert({
        'event_id': widget.event.id,
        'template_url': url,
        'name_x': _nameX,
        'name_y': _nameY,
        'font_size': _fontSize,
        'text_color': '#${_textColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
        'created_by': _supabase.auth.currentUser?.id,
      }, onConflict: 'event_id');

      setState(() {
        _uploadedTemplateUrl = url;
        _isProcessing = false;
        _progressMessage = '';
      });
      _showSnack('Template saved!');
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _progressMessage = '';
      });
      _showSnack('Upload failed: $e', isError: true);
    }
  }

  Future<void> _issueCertificates() async {
    if (_uploadedTemplateUrl == null) {
      _showSnack('Please upload a template first.', isError: true);
      return;
    }
    if (_attendees.isEmpty) {
      _showSnack('No attendees found for this event.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Issue Certificates?', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
        content: Text(
          'This will generate personalized certificates for $_attendeeCount attendees of "${widget.event.title}". This may take a moment.',
          style: GoogleFonts.inter(color: Colors.white60),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Issue All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _progressMessage = 'Starting certificate generation...';
    });

    int successCount = 0;
    int skipCount = 0;

    for (int i = 0; i < _attendees.length; i++) {
      final row = _attendees[i];
      final userMap = row['users'] as Map<String, dynamic>?;
      final userId = row['user_id'] as String?;
      final userName = userMap?['name'] as String? ?? 'Member';

      if (userId == null) continue;

      if (mounted) {
        setState(() {
          _processedCount = i + 1;
          _progressMessage = 'Generating for $userName (${i + 1}/$_attendeeCount)...';
        });
      }

      try {
        // Check if already issued
        final existing = await _supabase
            .from('certificates')
            .select('id')
            .eq('event_id', widget.event.id)
            .eq('user_id', userId)
            .limit(1);

        if ((existing as List).isNotEmpty) {
          skipCount++;
          continue;
        }

        // Generate personalized certificate image
        final certBytes = await _generateCertificate(
          templateUrl: _uploadedTemplateUrl!,
          studentName: userName,
        );

        if (certBytes == null) continue;

        // Upload to issued-certificates bucket
        final certFileName = 'event_${widget.event.id}/user_$userId.png';
        await _supabase.storage.from('issued-certificates').uploadBinary(
              certFileName,
              certBytes,
              fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
            );

        final certUrl = _supabase.storage.from('issued-certificates').getPublicUrl(certFileName);

        // Insert into certificates table
        await _supabase.from('certificates').upsert({
          'user_id': userId,
          'event_id': widget.event.id,
          'title': 'Certificate of Participation - ${widget.event.title}',
          'description': 'Awarded for attending ${widget.event.title} on ${_formatDate(widget.event.date)}',
          'file_url': certUrl,
          'issued_by': _supabase.auth.currentUser?.id,
          'issued_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,event_id');

        successCount++;
      } catch (e) {
        debugPrint('Error issuing cert for $userId: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _progressMessage = '';
        _alreadyIssued = _alreadyIssued + successCount;
      });
      _showSnack('Done! Issued: $successCount, Skipped (already issued): $skipCount');
    }
  }

  // Generates a personalized certificate by overlaying the student's name on the template.
  Future<Uint8List?> _generateCertificate({
    required String templateUrl,
    required String studentName,
  }) async {
    try {
      // Fetch template image bytes from URL
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(templateUrl));
      final response = await request.close();
      final templateBytes = await response.fold<List<int>>([], (prev, element) => prev..addAll(element));
      client.close();

      // Decode the template image
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(templateBytes));
      final frame = await codec.getNextFrame();
      final templateImage = frame.image;
      final imgWidth = templateImage.width.toDouble();
      final imgHeight = templateImage.height.toDouble();

      // Draw onto canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, imgWidth, imgHeight));

      // Draw template
      canvas.drawImage(templateImage, Offset.zero, Paint());

      // Draw student name
      final nameX = _nameX * imgWidth;
      final nameY = _nameY * imgHeight;

      final textPainter = TextPainter(
        text: TextSpan(
          text: studentName,
          style: TextStyle(
            fontSize: _fontSize.toDouble(),
            fontWeight: FontWeight.bold,
            color: _textColor,
            letterSpacing: 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(nameX - textPainter.width / 2, nameY - textPainter.height / 2),
      );

      // Convert to image bytes
      final picture = recorder.endRecording();
      final img = await picture.toImage(imgWidth.toInt(), imgHeight.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error generating certificate: $e');
      return null;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter()),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Issue Certificates', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
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
                      // Event info card
                      _buildEventInfoCard(isDark),
                      const SizedBox(height: 24),

                      // Stats row
                      _buildStatsRow(isDark),
                      const SizedBox(height: 24),

                      // Step 1: Template Upload
                      _buildSectionTitle('Step 1: Upload Certificate Template', isDark),
                      const SizedBox(height: 8),
                      Text(
                        'Upload a PNG/JPG image of your blank certificate. The student\'s name will be printed on it.',
                        style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      _buildTemplatePickerCard(isDark),
                      const SizedBox(height: 24),

                      // Step 2: Name Position
                      _buildSectionTitle('Step 2: Name Position', isDark),
                      const SizedBox(height: 8),
                      Text(
                        'Set where the student\'s name should appear (relative position on the certificate).',
                        style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      _buildPositionConfig(isDark),
                      const SizedBox(height: 24),

                      // Save template config button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _uploadTemplateAndSaveConfig,
                          icon: const Icon(Icons.cloud_upload_rounded),
                          label: Text('Save Template Config', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: AppTheme.primary,
                            side: BorderSide(color: AppTheme.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Step 3: Issue Certificates
                      _buildSectionTitle('Step 3: Issue to All Attendees', isDark),
                      const SizedBox(height: 8),
                      if (_uploadedTemplateUrl != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                              const SizedBox(width: 8),
                              Text('Template ready', style: GoogleFonts.inter(color: Colors.green, fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_isProcessing || _uploadedTemplateUrl == null || _attendeeCount == 0)
                              ? null
                              : _issueCertificates,
                          icon: const Icon(Icons.workspace_premium_rounded),
                          label: Text(
                            'Issue Certificates to $_attendeeCount Attendees',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),

                // Processing overlay
                if (_isProcessing)
                  Container(
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
                              if (_attendeeCount > 0) ...[
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: _attendeeCount > 0 ? _processedCount / _attendeeCount : 0,
                                  backgroundColor: Colors.white12,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$_processedCount / $_attendeeCount',
                                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.white38),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

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
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (widget.event.date != null)
                    Text(_formatDate(widget.event.date),
                        style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(child: _buildStatChip('Attendees', _attendeeCount, Icons.people_rounded, Colors.blueAccent, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatChip('Issued', _alreadyIssued, Icons.workspace_premium_rounded, Colors.amber, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatChip('Pending', _attendeeCount - _alreadyIssued, Icons.pending_rounded, Colors.orangeAccent, isDark)),
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
            Text('$value', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white38 : Colors.black45)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTemplatePickerCard(bool isDark) {
    return GestureDetector(
      onTap: _isProcessing ? null : _pickTemplate,
      child: GlassCard(
        child: Container(
          height: 160,
          padding: const EdgeInsets.all(16),
          child: _templateBytes != null
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_templateBytes!, fit: BoxFit.contain, width: double.infinity),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('Change', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ],
                )
              : _uploadedTemplateUrl != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 36),
                        const SizedBox(height: 8),
                        Text('Template already saved', style: GoogleFonts.inter(color: Colors.green, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('Tap to replace', style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded,
                            size: 42, color: isDark ? Colors.white24 : Colors.black26),
                        const SizedBox(height: 10),
                        Text('Tap to pick certificate template image',
                            style: GoogleFonts.inter(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13)),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildPositionConfig(bool isDark) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSliderRow('Horizontal Position (X)', _nameX, (v) => setState(() => _nameX = v), isDark),
            const SizedBox(height: 12),
            _buildSliderRow('Vertical Position (Y)', _nameY, (v) => setState(() => _nameY = v), isDark),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Font Size', style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54)),
                      Slider(
                        value: _fontSize.toDouble(),
                        min: 20,
                        max: 100,
                        divisions: 80,
                        label: '$_fontSize px',
                        activeColor: AppTheme.primary,
                        onChanged: (v) => setState(() => _fontSize = v.toInt()),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$_fontSize px', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, ValueChanged<double> onChanged, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54)),
            Text('${(value * 100).toInt()}%', style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value,
          min: 0.0,
          max: 1.0,
          activeColor: AppTheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
