import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class DocumentPreviewScreen extends StatelessWidget {
  final String title;
  final String fileUrl;

  const DocumentPreviewScreen({
    super.key,
    required this.title,
    required this.fileUrl,
  });

  bool get _isImage {
    final lowerUrl = fileUrl.toLowerCase();
    return lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.gif') ||
        lowerUrl.endsWith('.webp');
  }

  bool get _isPdf {
    return fileUrl.toLowerCase().endsWith('.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: _buildPreview(),
      ),
    );
  }

  Widget _buildPreview() {
    if (_isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: CachedNetworkImage(
          imageUrl: fileUrl,
          placeholder: (context, url) => const CircularProgressIndicator(),
          errorWidget: (context, url, error) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              SizedBox(height: 16),
              Text('Error loading image'),
            ],
          ),
        ),
      );
    } else if (_isPdf) {
      return SfPdfViewer.network(
        fileUrl,
        canShowScrollHead: false,
        canShowScrollStatus: false,
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Preview not supported for this file type.',
            style: GoogleFonts.inter(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Please download to view.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      );
    }
  }
}
