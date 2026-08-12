import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';

class CertificateTemplateCalibratorScreen extends StatefulWidget {
  final int eventId;
  final String? eventTitle;

  const CertificateTemplateCalibratorScreen({
    super.key,
    required this.eventId,
    this.eventTitle,
  });

  @override
  State<CertificateTemplateCalibratorScreen> createState() => _CertificateTemplateCalibratorScreenState();
}

class _CertificateTemplateCalibratorScreenState extends State<CertificateTemplateCalibratorScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  String _title = '';

  String? _imageUrl;
  Size _naturalSize = Size.zero;

  // Field keys
  static const List<String> _fieldKeys = [
    'student_name',
    'event_name',
    'event_date',
    'certificate_id',
    'coordinator_name',
    'chair_name',
  ];

  static const Map<String, String> _fieldLabels = {
    'student_name': 'Student Name',
    'event_name': 'Event Name',
    'event_date': 'Event Date',
    'certificate_id': 'Certificate ID',
    'coordinator_name': 'Coordinator Name',
    'chair_name': 'Chair Name',
  };

  String _activeField = 'student_name';

  // Map of field key -> config map
  Map<String, Map<String, dynamic>> _fields = {};

  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _title = widget.eventTitle ?? 'Event #${widget.eventId}';
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _supabase
          .from('events')
          .select('title, certificate_image_url, certificate_field_positions')
          .eq('id', widget.eventId)
          .maybeSingle();

      if (res != null) {
        if (res['title'] != null) _title = res['title'];
        if (res['certificate_image_url'] != null) {
          _imageUrl = res['certificate_image_url'];
        }
        if (res['certificate_field_positions'] != null) {
          final raw = res['certificate_field_positions'] as Map<String, dynamic>;
          _fields = raw.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
        }
      }
    } catch (e) {
      debugPrint('Error loading calibrator data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;
      final bytes = result.files.single.bytes!;
      final ext = result.files.single.name.split('.').last;

      setState(() => _isSaving = true);
      final fileName = '${widget.eventId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = 'templates/$fileName';

      String publicUrl = '';
      try {
        await _supabase.storage.from('certificate_templates').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: 'image/$ext'));
        publicUrl = _supabase.storage.from('certificate_templates').getPublicUrl(path);
      } catch (_) {
        await _supabase.storage.from('event_posters').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: 'image/$ext'));
        publicUrl = _supabase.storage.from('event_posters').getPublicUrl(path);
      }

      await _supabase.from('events').update({
        'certificate_image_url': publicUrl,
        'template_url': publicUrl,
        'certificate_template_type': 'image',
      }).eq('id', widget.eventId);

      setState(() {
        _imageUrl = publicUrl;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template image uploaded! Now tap on image to place fields.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onImageTap(TapUpDetails details) {
    if (_imageUrl == null) return;
    final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final localOffset = box.globalToLocal(details.globalPosition);
    final displayedWidth = box.size.width;
    final displayedHeight = box.size.height;

    // Convert to percentage coordinates (0.0 to 100.0)
    final px = (localOffset.dx / displayedWidth * 100.0).clamp(0.0, 100.0);
    final py = (localOffset.dy / displayedHeight * 100.0).clamp(0.0, 100.0);

    final currentConfig = _fields[_activeField] ?? {};

    setState(() {
      _fields[_activeField] = {
        'x': double.parse(px.toStringAsFixed(2)),
        'y': double.parse(py.toStringAsFixed(2)),
        'size': currentConfig['size'] ?? 20,
        'align': currentConfig['align'] ?? 'center',
        'font': currentConfig['font'] ?? 'HelveticaBold',
        'color': currentConfig['color'] ?? '#1B2A4A',
      };
    });
  }

  Future<void> _savePositions() async {
    if (_imageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a template image first.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _supabase.from('events').update({
        'certificate_field_positions': _fields,
        'certificate_image_url': _imageUrl,
        'certificate_template_type': 'image',
      }).eq('id', widget.eventId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template field positions saved successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Calibrate Certificate', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, color: Colors.green),
            onPressed: _isSaving ? null : _savePositions,
            tooltip: 'Save Field Positions',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Event Header Card
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_title, style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            'Upload certificate image and tap on the image to position student name, event date, etc.',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Image Upload / Preview Area
                  if (_imageUrl == null) ...[
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(Icons.image_outlined, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text('No Certificate Background Uploaded', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _pickAndUploadImage,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Upload Background Image'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Active Field Selector Bar
                    Text('1. Select Field to Position:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _fieldKeys.map((key) {
                          final isSelected = _activeField == key;
                          final isSet = _fields.containsKey(key);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${_fieldLabels[key]} ${isSet ? '✓' : ''}'),
                              selected: isSelected,
                              selectedColor: Colors.blueAccent.withValues(alpha: 0.2),
                              onSelected: (_) => setState(() => _activeField = key),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Interactive Image Preview Canvas
                    Text('2. Tap Image to Place "${_fieldLabels[_activeField]}":', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: GestureDetector(
                          key: _imageKey,
                          onTapUp: _onImageTap,
                          child: Stack(
                            children: [
                              Image.network(
                                _imageUrl!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 200,
                                  color: Colors.grey.shade900,
                                  child: const Center(child: Text('Failed to load image')),
                                ),
                              ),
                              // Render configured field overlays
                              ..._fields.entries.map((entry) {
                                final key = entry.key;
                                final cfg = entry.value;
                                final double px = (cfg['x'] as num).toDouble();
                                final double py = (cfg['y'] as num).toDouble();
                                final bool isCurrent = key == _activeField;

                                return Positioned.fill(
                                  child: Align(
                                    alignment: Alignment(
                                      (px / 50.0) - 1.0,
                                      (py / 50.0) - 1.0,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isCurrent ? Colors.blue.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isCurrent ? Colors.white : Colors.transparent, width: 1.5),
                                      ),
                                      child: Text(
                                        _fieldLabels[key] ?? key,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Controls for Selected Field
                    if (_fields.containsKey(_activeField)) ...[
                      GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Formatting: ${_fieldLabels[_activeField]}',
                                    style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _fields.remove(_activeField);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('Font Size: ', style: GoogleFonts.inter(fontSize: 12)),
                                  Expanded(
                                    child: Slider(
                                      value: ((_fields[_activeField]!['size'] as num?) ?? 20).toDouble(),
                                      min: 10,
                                      max: 48,
                                      onChanged: (val) {
                                        setState(() {
                                          _fields[_activeField]!['size'] = val.round();
                                        });
                                      },
                                    ),
                                  ),
                                  Text('${_fields[_activeField]!['size'] ?? 20}pt', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _savePositions,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(_isSaving ? 'Saving...' : 'Save Certificate Layout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickAndUploadImage,
                      icon: const Icon(Icons.image),
                      label: const Text('Replace Background Image'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
