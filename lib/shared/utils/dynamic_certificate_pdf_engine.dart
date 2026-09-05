import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dynamic_template_parser.dart';

/// Renders PDF certificates with automatic text fitting and natural-dimension mapping
class DynamicCertificatePdfEngine {
  /// Builds a PDF certificate from background image bytes and a list of field configs.
  static Future<Uint8List> renderImageCertificate({
    required List<int> imageBytes,
    required Map<String, String> fieldValues,
    required List<FieldConfig> fieldConfigs,
  }) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(Uint8List.fromList(imageBytes));

    // Natural dimension mapping
    final double imgW = image.width?.toDouble() ?? 2000.0;
    final double imgH = image.height?.toDouble() ?? 1414.0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(imgW, imgH),
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          final children = <pw.Widget>[
            pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(image, fit: pw.BoxFit.fill),
            ),
          ];

          // Detect dark vs light template from image bytes
          bool isDark = false;
          if (imageBytes.length > 100) {
            int darkSamples = 0;
            int totalSamples = 0;
            final start = (imageBytes.length * 0.25).toInt();
            final end = (imageBytes.length * 0.75).toInt();
            for (int i = start; i < end; i += 50) {
              if (imageBytes[i] < 60) darkSamples++;
              totalSamples++;
            }
            if (totalSamples > 0 && (darkSamples / totalSamples) > 0.45) {
              isDark = true;
            }
          }

          final eraseBg = isDark ? PdfColors.black : PdfColor.fromHex('#FDFBF4');
          final defaultTextColor = isDark ? '#FFFFFF' : '#0B1B3D';
          final defaultSubTextColor = isDark ? '#E2E8F0' : '#222222';

          // If no custom field configs exist (default Google Slides template), use standard tag replacement positions
          final activeConfigs = fieldConfigs.isNotEmpty
              ? fieldConfigs
              : [
                  FieldConfig(
                    id: 'student_name',
                    templateId: 'slides',
                    fieldKey: 'student_name',
                    tag: '{{Student_name}}',
                    x: imgW * 0.20,
                    y: imgH * 0.41,
                    width: imgW * 0.60,
                    height: imgH * 0.08,
                    fontSize: imgH * 0.055,
                    textColor: defaultTextColor,
                    fontWeight: 'bold',
                    alignment: 'center',
                  ),
                  FieldConfig(
                    id: 'chair_name',
                    templateId: 'slides',
                    fieldKey: 'chair_name',
                    tag: '{{chair_name}}',
                    x: imgW * 0.14,
                    y: imgH * 0.15,
                    width: imgW * 0.26,
                    height: imgH * 0.06,
                    fontSize: imgH * 0.035,
                    textColor: defaultSubTextColor,
                    fontWeight: 'bold',
                    alignment: 'center',
                  ),
                  FieldConfig(
                    id: 'coordinator_name',
                    templateId: 'slides',
                    fieldKey: 'coordinator_name',
                    tag: '{{coord_name}}',
                    x: imgW * 0.58,
                    y: imgH * 0.15,
                    width: imgW * 0.28,
                    height: imgH * 0.06,
                    fontSize: imgH * 0.035,
                    textColor: defaultSubTextColor,
                    fontWeight: 'bold',
                    alignment: 'center',
                  ),
                ];

          // 1. Cover/erase {{Student_name}}, {{chair_name}}, {{coord_name}} placeholder tags on the background template image
          if (fieldConfigs.isEmpty) {
            // Erase {{Student_name}}
            children.add(
              pw.Positioned(
                left: imgW * 0.20,
                bottom: imgH * 0.40,
                child: pw.Container(
                  width: imgW * 0.60,
                  height: imgH * 0.11,
                  color: eraseBg,
                ),
              ),
            );
            // Erase {{chair_name}}
            children.add(
              pw.Positioned(
                left: imgW * 0.14,
                bottom: imgH * 0.14,
                child: pw.Container(
                  width: imgW * 0.26,
                  height: imgH * 0.08,
                  color: eraseBg,
                ),
              ),
            );
            // Erase {{coord_name}}
            children.add(
              pw.Positioned(
                left: imgW * 0.58,
                bottom: imgH * 0.14,
                child: pw.Container(
                  width: imgW * 0.28,
                  height: imgH * 0.08,
                  color: eraseBg,
                ),
              ),
            );
          }

          // 2. Render replaced student name and Execom text
          for (final config in activeConfigs) {
            final val = fieldValues[config.fieldKey] ?? fieldValues[config.tag] ?? '';
            if (val.trim().isEmpty) continue;

            final double boxWidth = config.width > 0 ? config.width : (imgW * 0.7);
            final double boxHeight = config.height > 0 ? config.height : 100.0;

            // Auto text-fitting algorithm
            double fontSize = config.fontSize > 0 ? config.fontSize : 36.0;

            final double fontWidthRatio = 0.55;
            double estimatedTextWidth = val.length * (fontSize * fontWidthRatio);

            while (estimatedTextWidth > boxWidth && fontSize > 10.0) {
              fontSize -= 1.0;
              estimatedTextWidth = val.length * (fontSize * fontWidthRatio);
            }

            PdfColor pdfColor = PdfColors.black;
            if (config.textColor.startsWith('#') && config.textColor.length >= 7) {
              final r = int.parse(config.textColor.substring(1, 3), radix: 16);
              final g = int.parse(config.textColor.substring(3, 5), radix: 16);
              final b = int.parse(config.textColor.substring(5, 7), radix: 16);
              pdfColor = PdfColor.fromInt((0xFF << 24) | (r << 16) | (g << 8) | b);
            }

            children.add(
              pw.Positioned(
                left: config.x,
                bottom: config.y,
                child: pw.SizedBox(
                  width: boxWidth,
                  height: boxHeight,
                  child: pw.Center(
                    child: pw.Text(
                      val,
                      textAlign: pw.TextAlign.center,
                      maxLines: 1,
                      style: pw.TextStyle(
                        fontSize: fontSize,
                        fontWeight: pw.FontWeight.bold,
                        color: pdfColor,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return pw.Stack(children: children);
        },
      ),
    );

    return pdf.save();
  }

  /// Renders an elegant standard PDF certificate when background image template is invalid or unavailable
  static Future<Uint8List> renderStandardCertificate({
    required String studentName,
    required String eventName,
    required String eventDate,
    required String certificateId,
    String? coordinatorName,
    String? chairName,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(24),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.amber800, width: 4),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'ISTE STUDENT CHAPTER',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                ),
                pw.Text(
                  'CERTIFICATE OF PARTICIPATION',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900),
                ),
                pw.SizedBox(height: 10),
                pw.Text('This is proudly presented to', style: const pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 10),
                pw.Text(
                  studentName,
                  style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'for participating in "$eventName" on $eventDate',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 20),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    if (chairName != null && chairName.isNotEmpty)
                      pw.Column(
                        children: [
                          pw.Text(chairName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                          pw.Container(width: 120, height: 1, color: PdfColors.grey700),
                          pw.Text('Chapter Chair', style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    pw.Column(
                      children: [
                        pw.Text('ID: $certificateId', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                    if (coordinatorName != null && coordinatorName.isNotEmpty)
                      pw.Column(
                        children: [
                          pw.Text(coordinatorName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                          pw.Container(width: 120, height: 1, color: PdfColors.grey700),
                          pw.Text('Event Coordinator', style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }
}
