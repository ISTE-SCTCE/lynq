import 'dart:io';
import 'package:flutter/foundation.dart';
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

    double rawWidth = image.width?.toDouble() ?? 960.0;
    double rawHeight = image.height?.toDouble() ?? 540.0;
    double contentWidth = rawWidth;
    int bgR = 0, bgG = 0, bgB = 0;
    bool isDark = false;
    double tagCenterYFromTop = rawHeight * (278.0 / 540.0);
    double tagHeight = rawHeight * (35.0 / 540.0);

    // If it's a PNG image, inspect decompressed pixels to:
    // 1. Auto-crop right white canvas padding (from Google Slides exports)
    // 2. Sample exact background color so erase box is 100% invisible
    // 3. Find exact {{student_name}} tag vertical range
    if (imageBytes.length > 30 &&
        imageBytes[0] == 0x89 &&
        imageBytes[1] == 0x50 &&
        imageBytes[2] == 0x4E &&
        imageBytes[3] == 0x47) {
      try {
        final byteData = ByteData.sublistView(Uint8List.fromList(imageBytes));
        final w = byteData.getUint32(16);
        final h = byteData.getUint32(20);
        rawWidth = w.toDouble();
        rawHeight = h.toDouble();

        int pos = 8;
        final idatChunks = <Uint8List>[];
        while (pos + 8 <= imageBytes.length) {
          final len = byteData.getUint32(pos);
          final type = String.fromCharCodes(imageBytes.sublist(pos + 4, pos + 8));
          if (type == 'IDAT') {
            idatChunks.add(Uint8List.fromList(imageBytes.sublist(pos + 8, pos + 8 + len)));
          }
          pos += 8 + len + 4;
        }

        final totalLen = idatChunks.fold<int>(0, (sum, c) => sum + c.length);
        final merged = Uint8List(totalLen);
        int mOff = 0;
        for (final c in idatChunks) {
          merged.setAll(mOff, c);
          mOff += c.length;
        }

        final decompressed = Uint8List.fromList(zlib.decode(merged));
        final colorType = imageBytes[25];
        final bpp = colorType == 6 ? 4 : (colorType == 2 ? 3 : 1);
        final stride = 1 + w * bpp;

        // 1. Detect right white strip
        contentWidth = rawWidth;
        for (int x = w - 1; x >= 0; x--) {
          bool isAllWhite = true;
          for (int y in [(h * 0.25).toInt(), (h * 0.5).toInt(), (h * 0.75).toInt()]) {
            final pOff = y * stride + 1 + x * bpp;
            if (decompressed[pOff] < 240 || decompressed[pOff + 1] < 240 || decompressed[pOff + 2] < 240) {
              isAllWhite = false;
              break;
            }
          }
          if (!isAllWhite) {
            contentWidth = (x + 1).toDouble();
            break;
          }
        }

        // 2. Sample background color at certificate center
        final sY = (h * 0.48).toInt();
        final sX = (contentWidth * 0.15).toInt();
        final sOff = sY * stride + 1 + sX * bpp;
        bgR = decompressed[sOff];
        bgG = decompressed[sOff + 1];
        bgB = decompressed[sOff + 2];
        isDark = (bgR * 0.299 + bgG * 0.587 + bgB * 0.114) < 128;

        // 3. Scan for {{student_name}} text in central region (Y: 46% - 56%)
        int minY = h, maxY = 0;
        for (int y = (h * 0.46).toInt(); y < (h * 0.56).toInt(); y++) {
          for (int x = (contentWidth * 0.25).toInt(); x < (contentWidth * 0.75).toInt(); x++) {
            final pOff = y * stride + 1 + x * bpp;
            final r = decompressed[pOff];
            final g = decompressed[pOff + 1];
            final b = decompressed[pOff + 2];
            final diff = (r - bgR).abs() + (g - bgG).abs() + (b - bgB).abs();
            if (diff > 120) {
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
        }
        if (maxY > minY) {
          tagCenterYFromTop = (minY + maxY) / 2.0;
          tagHeight = (maxY - minY).toDouble();
        }
      } catch (e) {
        debugPrint('DynamicCertificatePdfEngine PNG inspection note: $e');
      }
    }

    final bgColor = PdfColor.fromInt((0xFF << 24) | (bgR << 16) | (bgG << 8) | bgB);
    final defaultTextColor = isDark ? PdfColors.white : PdfColor.fromHex('#0B1B3D');

    final studentName = fieldValues['student_name'] ?? fieldValues['{{student_name}}'] ?? fieldValues['{{Student_name}}'] ?? 'Member';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(contentWidth, rawHeight),
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          // Erase box precisely covers ONLY {{student_name}}
          // Leaving "THIS CERTIFICATE IS AWARDED TO" above and the green line below 100% intact!
          final eraseTop = tagCenterYFromTop - (tagHeight * 0.55);
          final eraseBottomTop = tagCenterYFromTop + (tagHeight * 0.55);
          final eraseHeight = eraseBottomTop - eraseTop;
          final eraseBottom = rawHeight - eraseBottomTop; // in PDF bottom-up coords
          final eraseWidth = contentWidth * 0.45;
          final eraseLeft = (contentWidth - eraseWidth) / 2;

          // Auto font-size matching tag
          double fontSize = tagHeight > 15 ? tagHeight * 0.95 : (rawHeight * 0.055);
          final double boxWidth = contentWidth * 0.70;
          final double fontWidthRatio = 0.55;
          double estimatedTextWidth = studentName.length * (fontSize * fontWidthRatio);
          while (estimatedTextWidth > boxWidth && fontSize > 12.0) {
            fontSize -= 1.0;
            estimatedTextWidth = studentName.length * (fontSize * fontWidthRatio);
          }

          final overlays = <pw.Widget>[
            // 1. Background image anchored at top-left
            pw.Positioned(
              left: 0,
              top: 0,
              child: pw.SizedBox(
                width: rawWidth,
                height: rawHeight,
                child: pw.Image(image, fit: pw.BoxFit.fill),
              ),
            ),

            // 2. Seamless erase box matching the exact background color (completely invisible)
            pw.Positioned(
              left: eraseLeft,
              bottom: eraseBottom,
              child: pw.Container(
                width: eraseWidth,
                height: eraseHeight,
                color: bgColor,
              ),
            ),

            // 3. Attendee name centered at the exact position in crisp white/theme color
            pw.Positioned(
              left: (contentWidth - boxWidth) / 2,
              bottom: eraseBottom,
              child: pw.SizedBox(
                width: boxWidth,
                height: eraseHeight,
                child: pw.Center(
                  child: pw.Text(
                    studentName,
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: fontSize,
                      fontWeight: pw.FontWeight.bold,
                      color: defaultTextColor,
                    ),
                  ),
                ),
              ),
            ),
          ];

          return pw.ClipRect(
            child: pw.SizedBox(
              width: contentWidth,
              height: rawHeight,
              child: pw.Stack(children: overlays),
            ),
          );
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
