import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../models/app_models.dart';
import '../../shared/widgets/glass_card.dart';
import 'package:m_lynq/shared/utils/dynamic_template_parser.dart';

class TemplateEditorScreen extends StatefulWidget {
  final EventModel event;
  final String templateId;
  final String templateUrl;
  final double naturalWidth;
  final double naturalHeight;

  const TemplateEditorScreen({
    super.key,
    required this.event,
    required this.templateId,
    required this.templateUrl,
    this.naturalWidth = 2000,
    this.naturalHeight = 1414,
  });

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _showLiveSampleData = true; // Toggle between {{TAG}} and Real Sample Data

  List<FieldConfig> _fields = [];
  int _selectedFieldIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadFieldConfigurations();
  }

  Future<void> _loadFieldConfigurations() async {
    setState(() => _isLoading = true);
    try {
      final res = await _supabase
          .from('certificate_template_fields')
          .select()
          .eq('template_id', widget.templateId);

      final List rows = res as List? ?? [];
      if (rows.isNotEmpty) {
        _fields = rows.map((r) => FieldConfig.fromMap(r as Map<String, dynamic>)).toList();
      } else {
        // Initialize default core fields if none exist
        _fields = [
          FieldConfig(
            id: '',
            templateId: widget.templateId,
            fieldKey: 'student_name',
            tag: '{{STUDENT_NAME}}',
            x: widget.naturalWidth / 2,
            y: widget.naturalHeight * 0.45,
            width: widget.naturalWidth * 0.75,
            height: 120,
            fontSize: 42,
            alignment: 'center',
            textColor: '#1B2A4A',
          ),
          FieldConfig(
            id: '',
            templateId: widget.templateId,
            fieldKey: 'event_name',
            tag: '{{EVENT_NAME}}',
            x: widget.naturalWidth / 2,
            y: widget.naturalHeight * 0.32,
            width: widget.naturalWidth * 0.75,
            height: 90,
            fontSize: 26,
            alignment: 'center',
            textColor: '#1B2A4A',
          ),
          FieldConfig(
            id: '',
            templateId: widget.templateId,
            fieldKey: 'event_date',
            tag: '{{EVENT_DATE}}',
            x: widget.naturalWidth / 2,
            y: widget.naturalHeight * 0.22,
            width: widget.naturalWidth * 0.5,
            height: 60,
            fontSize: 18,
            alignment: 'center',
            textColor: '#1B2A4A',
          ),
          FieldConfig(
            id: '',
            templateId: widget.templateId,
            fieldKey: 'certificate_id',
            tag: '{{CERTIFICATE_ID}}',
            x: widget.naturalWidth / 2,
            y: widget.naturalHeight * 0.08,
            width: widget.naturalWidth * 0.5,
            height: 50,
            fontSize: 14,
            alignment: 'center',
            textColor: '#666666',
          ),
        ];
      }
      if (_fields.isNotEmpty) _selectedFieldIndex = 0;
    } catch (e) {
      debugPrint('Error loading template fields: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfigurations() async {
    setState(() => _isSaving = true);
    try {
      // Upsert field configurations
      for (final f in _fields) {
        final payload = f.toMap();
        payload['template_id'] = widget.templateId;
        if (f.id.isNotEmpty) {
          await _supabase.from('certificate_template_fields').update(payload).eq('id', f.id);
        } else {
          await _supabase.from('certificate_template_fields').insert(payload);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template field configuration saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save configuration: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addNewField(TemplateTagInfo tagInfo) {
    setState(() {
      _fields.add(FieldConfig(
        id: '',
        templateId: widget.templateId,
        fieldKey: tagInfo.fieldKey,
        tag: tagInfo.tag,
        x: widget.naturalWidth / 2,
        y: widget.naturalHeight / 2,
        width: widget.naturalWidth * 0.5,
        height: 80,
        fontSize: 24,
        alignment: 'center',
      ));
      _selectedFieldIndex = _fields.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.cardBg,
        elevation: 0,
        title: Text(
          'Certificate Template Editor',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          Row(
            children: [
              Text('Real Preview', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
              Switch(
                value: _showLiveSampleData,
                onChanged: (val) => setState(() => _showLiveSampleData = val),
                activeColor: AppTheme.accentGreen,
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save, color: AppTheme.accentGreen),
            onPressed: _isSaving ? null : _saveConfigurations,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top controls & tag chip selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppTheme.cardBg,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text('Add Tag: ', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
                        ...DynamicTemplateParser.knownFields.values.map((tagInfo) {
                          final isAlreadyAdded = _fields.any((f) => f.fieldKey == tagInfo.fieldKey);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              backgroundColor: isAlreadyAdded ? Colors.white10 : AppTheme.accentBlue.withOpacity(0.2),
                              label: Text(tagInfo.tag, style: GoogleFonts.inter(fontSize: 12, color: isAlreadyAdded ? Colors.white38 : AppTheme.accentBlue)),
                              onPressed: isAlreadyAdded ? null : () => _addNewField(tagInfo),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                // Main Canvas + Properties split view
                Expanded(
                  child: Row(
                    children: [
                      // Interactive Canvas Preview
                      Expanded(
                        flex: 3,
                        child: Container(
                          color: Colors.black26,
                          margin: const EdgeInsets.all(16),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double scaleX = constraints.maxWidth / widget.naturalWidth;
                              final double scaleY = constraints.maxHeight / widget.naturalHeight;
                              final double scale = scaleX < scaleY ? scaleX : scaleY;

                              final double displayW = widget.naturalWidth * scale;
                              final double displayH = widget.naturalHeight * scale;

                              return Center(
                                child: SizedBox(
                                  width: displayW,
                                  height: displayH,
                                  child: Stack(
                                    children: [
                                      // Background Image Template
                                      Positioned.fill(
                                        child: Image.network(
                                          widget.templateUrl,
                                          fit: BoxFit.fill,
                                          errorBuilder: (_, __, ___) => Container(color: Colors.white10, child: const Center(child: Text('Template Image'))),
                                        ),
                                      ),
                                      // Field Markers Layer
                                      ..._fields.asMap().entries.map((entry) {
                                        final idx = entry.key;
                                        final config = entry.value;
                                        final isSelected = idx == _selectedFieldIndex;

                                        // Convert natural coordinates -> display pixel space
                                        final double dispBoxW = config.width * scale;
                                        final double dispBoxH = config.height * scale;
                                        final double dispX = config.x * scale;
                                        // Natural Y origin is bottom
                                        final double dispYFromTop = displayH - (config.y * scale) - dispBoxH;

                                        double dispLeft = dispX;
                                        if (config.alignment == 'center') {
                                          dispLeft = dispX - (dispBoxW / 2);
                                        } else if (config.alignment == 'right') {
                                          dispLeft = dispX - dispBoxW;
                                        }

                                        final sampleVal = DynamicTemplateParser.knownFields[config.fieldKey.toUpperCase()]?.sampleValue ?? config.tag;
                                        final displayText = _showLiveSampleData ? sampleVal : config.tag;

                                        return Positioned(
                                          left: dispLeft,
                                          top: dispYFromTop,
                                          child: GestureDetector(
                                            onTap: () => setState(() => _selectedFieldIndex = idx),
                                            onPanUpdate: (details) {
                                              setState(() {
                                                // Convert drag back to natural coordinate space
                                                final double deltaX = details.delta.dx / scale;
                                                final double deltaY = -details.delta.dy / scale;
                                                _fields[idx] = config.copyWith(
                                                  x: (config.x + deltaX).clamp(0, widget.naturalWidth),
                                                  y: (config.y + deltaY).clamp(0, widget.naturalHeight),
                                                );
                                              });
                                            },
                                            child: Container(
                                              width: dispBoxW,
                                              height: dispBoxH,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: isSelected ? AppTheme.accentGreen : Colors.amber.withOpacity(0.6),
                                                  width: isSelected ? 2 : 1,
                                                ),
                                                color: isSelected ? AppTheme.accentGreen.withOpacity(0.1) : Colors.amber.withOpacity(0.05),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                displayText,
                                                textAlign: config.alignment == 'left' ? TextAlign.left : (config.alignment == 'right' ? TextAlign.right : TextAlign.center),
                                                style: GoogleFonts.inter(
                                                  fontSize: (config.fontSize * scale).clamp(10, 80),
                                                  fontWeight: config.fontWeight == 'bold' ? FontWeight.bold : FontWeight.normal,
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
                              );
                            },
                          ),
                        ),
                      ),
                      // Property Inspector Panel
                      if (_selectedFieldIndex >= 0 && _selectedFieldIndex < _fields.length)
                        Container(
                          width: 320,
                          color: AppTheme.cardBg,
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainState.spaceBetween,
                                  children: [
                                    Text(
                                      _fields[_selectedFieldIndex].tag,
                                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentGreen),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () {
                                        setState(() {
                                          _fields.removeAt(_selectedFieldIndex);
                                          _selectedFieldIndex = _fields.isNotEmpty ? 0 : -1;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white10),
                                const SizedBox(height: 12),
                                _buildSliderRow('Font Size', _fields[_selectedFieldIndex].fontSize, 12, 100, (val) {
                                  setState(() {
                                    _fields[_selectedFieldIndex] = _fields[_selectedFieldIndex].copyWith(fontSize: val);
                                  });
                                }),
                                _buildSliderRow('Box Width', _fields[_selectedFieldIndex].width, 100, widget.naturalWidth, (val) {
                                  setState(() {
                                    _fields[_selectedFieldIndex] = _fields[_selectedFieldIndex].copyWith(width: val);
                                  });
                                }),
                                const SizedBox(height: 16),
                                Text('Alignment', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                                const SizedBox(height: 8),
                                ToggleButtons(
                                  isSelected: [
                                    _fields[_selectedFieldIndex].alignment == 'left',
                                    _fields[_selectedFieldIndex].alignment == 'center',
                                    _fields[_selectedFieldIndex].alignment == 'right',
                                  ],
                                  onPressed: (index) {
                                    final align = index == 0 ? 'left' : (index == 1 ? 'center' : 'right');
                                    setState(() {
                                      _fields[_selectedFieldIndex] = _fields[_selectedFieldIndex].copyWith(alignment: align);
                                    });
                                  },
                                  children: const [
                                    Icon(Icons.format_align_left),
                                    Icon(Icons.format_align_center),
                                    Icon(Icons.format_align_right),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainState.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
            Text(value.toStringAsFixed(0), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: AppTheme.accentGreen,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
