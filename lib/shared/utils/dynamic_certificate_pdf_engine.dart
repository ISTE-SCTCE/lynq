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

          for (final config in fieldConfigs) {
            final val = fieldValues[config.fieldKey] ?? fieldValues[config.tag] ?? '';
            if (val.trim().isEmpty) continue;

            final double boxWidth = config.width > 0 ? config.width : (imgW * 0.7);
            final double boxHeight = config.height > 0 ? config.height : 100.0;

            // Auto text-fitting algorithm
            double fontSize = config.fontSize > 0 ? config.fontSize : 36.0;

            // Calculate approximate text width ratio to scale down font if text overflows bounding box
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

            pw.TextAlign textAlign = pw.TextAlign.center;
            if (config.alignment == 'left') textAlign = pw.TextAlign.left;
            if (config.alignment == 'right') textAlign = pw.TextAlign.right;

            // Align position calculation relative to bounding box
            double leftPos = config.x;
            if (config.alignment == 'center') {
              leftPos = config.x - (boxWidth / 2);
            } else if (config.alignment == 'right') {
              leftPos = config.x - boxWidth;
            }

            children.add(
              pw.Positioned(
                left: leftPos,
                bottom: config.y,
                child: pw.SizedBox(
                  width: boxWidth,
                  height: boxHeight,
                  child: pw.Align(
                    alignment: config.alignment == 'left'
                        ? pw.Alignment.bottomLeft
                        : (config.alignment == 'right' ? pw.Alignment.bottomRight : pw.Alignment.bottomCenter),
                    child: pw.Text(
                      val,
                      textAlign: textAlign,
                      maxLines: 2,
                      style: pw.TextStyle(
                        fontSize: fontSize,
                        fontWeight: config.fontWeight == 'bold' ? pw.FontWeight.bold : pw.FontWeight.normal,
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
}
