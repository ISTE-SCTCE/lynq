import 'dart:convert';

/// Representation of a detected template tag
class TemplateTagInfo {
  final String tag;          // e.g. '{{STUDENT_NAME}}'
  final String fieldKey;     // e.g. 'student_name'
  final String label;        // e.g. 'Student Name'
  final String sampleValue;  // e.g. 'Sarvesh R'

  const TemplateTagInfo({
    required this.tag,
    required this.fieldKey,
    required this.label,
    required this.sampleValue,
  });
}

/// Dynamic Field Config stored in database (in natural image pixel space)
class FieldConfig {
  final String id;
  final String templateId;
  final String fieldKey;
  final String tag;
  final double x;
  final double y;
  final double width;
  final double height;
  final String fontFamily;
  final double fontSize;
  final String fontWeight;
  final String textColor;
  final String alignment;
  final String verticalAlignment;

  FieldConfig({
    required this.id,
    required this.templateId,
    required this.fieldKey,
    required this.tag,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.fontFamily = 'HelveticaBold',
    this.fontSize = 36.0,
    this.fontWeight = 'bold',
    this.textColor = '#1B2A4A',
    this.alignment = 'center',
    this.verticalAlignment = 'middle',
  });

  factory FieldConfig.fromMap(Map<String, dynamic> map) {
    return FieldConfig(
      id: map['id']?.toString() ?? '',
      templateId: map['template_id']?.toString() ?? '',
      fieldKey: map['field_key']?.toString() ?? 'student_name',
      tag: map['tag']?.toString() ?? '{{STUDENT_NAME}}',
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      width: (map['width'] as num?)?.toDouble() ?? 600.0,
      height: (map['height'] as num?)?.toDouble() ?? 100.0,
      fontFamily: map['font_family']?.toString() ?? 'HelveticaBold',
      fontSize: (map['font_size'] as num?)?.toDouble() ?? 36.0,
      fontWeight: map['font_weight']?.toString() ?? 'bold',
      textColor: map['text_color']?.toString() ?? '#1B2A4A',
      alignment: map['alignment']?.toString() ?? 'center',
      verticalAlignment: map['vertical_alignment']?.toString() ?? 'middle',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'template_id': templateId,
      'field_key': fieldKey,
      'tag': tag,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'font_family': fontFamily,
      'font_size': fontSize,
      'font_weight': fontWeight,
      'text_color': textColor,
      'alignment': alignment,
      'vertical_alignment': verticalAlignment,
    };
  }

  FieldConfig copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? fontSize,
    String? fontFamily,
    String? fontWeight,
    String? textColor,
    String? alignment,
  }) {
    return FieldConfig(
      id: id,
      templateId: templateId,
      fieldKey: fieldKey,
      tag: tag,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      textColor: textColor ?? this.textColor,
      alignment: alignment ?? this.alignment,
      verticalAlignment: verticalAlignment,
    );
  }
}

class DynamicTemplateParser {
  static final RegExp _tagRegex = RegExp(r'\{\{([A-Z0-9_]+)\}\}');

  /// Known system fields mapping tag -> metadata
  static const Map<String, TemplateTagInfo> knownFields = {
    'STUDENT_NAME': TemplateTagInfo(
      tag: '{{STUDENT_NAME}}',
      fieldKey: 'student_name',
      label: 'Student Name',
      sampleValue: 'Sarvesh R',
    ),
    'EVENT_NAME': TemplateTagInfo(
      tag: '{{EVENT_NAME}}',
      fieldKey: 'event_name',
      label: 'Event Name',
      sampleValue: 'Web Development Workshop',
    ),
    'EVENT_DATE': TemplateTagInfo(
      tag: '{{EVENT_DATE}}',
      fieldKey: 'event_date',
      label: 'Event Date',
      sampleValue: '20 August 2026',
    ),
    'CERTIFICATE_ID': TemplateTagInfo(
      tag: '{{CERTIFICATE_ID}}',
      fieldKey: 'certificate_id',
      label: 'Certificate ID',
      sampleValue: 'ISTE-2026-WDW-0001',
    ),
    'ORGANIZER_NAME': TemplateTagInfo(
      tag: '{{ORGANIZER_NAME}}',
      fieldKey: 'organizer_name',
      label: 'Organizer Name',
      sampleValue: 'ISTE Student Chapter',
    ),
    'VENUE': TemplateTagInfo(
      tag: '{{VENUE}}',
      fieldKey: 'venue',
      label: 'Venue',
      sampleValue: 'Main Auditorium, SCTCE',
    ),
    'DEPARTMENT': TemplateTagInfo(
      tag: '{{DEPARTMENT}}',
      fieldKey: 'department',
      label: 'Department',
      sampleValue: 'Computer Science & Engg.',
    ),
    'COLLEGE_NAME': TemplateTagInfo(
      tag: '{{COLLEGE_NAME}}',
      fieldKey: 'college_name',
      label: 'College Name',
      sampleValue: 'Sree Chitra Thirunal College of Engineering',
    ),
    'EVENT_DESCRIPTION': TemplateTagInfo(
      tag: '{{EVENT_DESCRIPTION}}',
      fieldKey: 'event_description',
      label: 'Event Description',
      sampleValue: 'A comprehensive 3-day hands-on workshop on modern web technologies.',
    ),
  };

  /// Parses text or HTML template content and extracts all dynamic tags
  static List<TemplateTagInfo> parseTags(String templateContent) {
    final matches = _tagRegex.allMatches(templateContent);
    final Set<String> tagKeys = {};
    final List<TemplateTagInfo> result = [];

    for (final m in matches) {
      final key = m.group(1);
      if (key != null && !tagKeys.contains(key)) {
        tagKeys.add(key);
        if (knownFields.containsKey(key)) {
          result.add(knownFields[key]!);
        } else {
          final lower = key.toLowerCase();
          final labelParts = lower.split('_').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}');
          result.add(TemplateTagInfo(
            tag: '{{$key}}',
            fieldKey: lower,
            label: labelParts.join(' '),
            sampleValue: '[${labelParts.join(' ')}]',
          ));
        }
      }
    }
    return result;
  }

  /// Resolves dynamic values from event data, attendee profile, and certificate ID
  static Map<String, String> resolveValues({
    required Map<String, dynamic> event,
    required String studentName,
    required String certificateId,
    Map<String, String>? customOverrides,
  }) {
    final title = event['title'] as String? ?? 'Event';
    final dateStr = event['date'] as String? ?? '';
    final venue = event['location'] as String? ?? 'Campus';
    final organizer = event['coordinator_name'] as String? ?? 'ISTE SCTCE';
    final department = event['department'] as String? ?? 'SCTCE';

    final Map<String, String> values = {
      'student_name': studentName.isNotEmpty ? studentName : 'Member',
      'event_name': title,
      'event_date': dateStr,
      'certificate_id': certificateId,
      'organizer_name': organizer,
      'venue': venue,
      'department': department,
      'college_name': 'Sree Chitra Thirunal College of Engineering',
      'event_description': event['description'] as String? ?? '',
    };

    if (customOverrides != null) {
      values.addAll(customOverrides);
    }
    return values;
  }
}
