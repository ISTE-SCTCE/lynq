import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_models.dart';
import '../../shared/utils/dynamic_template_parser.dart';
import '../../shared/utils/dynamic_certificate_pdf_engine.dart';

class CertFileItem {
  final String name;
  final List<int> bytes;
  final String extension;
  CertFileItem({required this.name, required this.bytes, required this.extension});
}

class AttendeeCertMatch {
  final Map<String, dynamic> attendee;
  CertFileItem? matchedFile;
  String matchType; // 'exact', 'contains', 'token', 'manual', 'none'
  int score;

  AttendeeCertMatch({
    required this.attendee,
    this.matchedFile,
    this.matchType = 'none',
    this.score = 0,
  });
}

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
  bool _isExtracting = false;

  // Segmented Mode: 0 = Automated (Google Slides), 1 = Manual (Google Drive / Files)
  int _selectedTab = 0;

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

  // Manual Mode State
  final _driveUrlCtrl = TextEditingController();
  final List<CertFileItem> _manualFiles = [];
  final Map<String, String> _manualOverrides = {}; // userId -> fileName

  final _slidesUrlCtrl = TextEditingController();
  final _chairNameCtrl = TextEditingController();
  final _coordinatorNameCtrl = TextEditingController();

  static const Color accentGreen = Color(0xFF16C07A);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color darkCardBg = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _loadStatsAndTemplate();
  }

  @override
  void dispose() {
    _slidesUrlCtrl.dispose();
    _chairNameCtrl.dispose();
    _coordinatorNameCtrl.dispose();
    _driveUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatsAndTemplate() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Event Status
      final evRow = await _supabase
          .from('events')
          .select('attendance_finalized, certificate_image_url, template_url, chair_name, coordinator_name')
          .eq('id', widget.event.id)
          .maybeSingle();

      if (evRow != null) {
        _isCompleted = evRow['attendance_finalized'] ?? widget.event.isCompleted;
        _activeTemplateUrl = (evRow['template_url'] as String?) ?? (evRow['certificate_image_url'] as String?);
        if (_activeTemplateUrl != null && _activeTemplateUrl!.isNotEmpty) {
          _slidesUrlCtrl.text = _activeTemplateUrl!;
        }
        if (evRow['chair_name'] != null) {
          _chairNameCtrl.text = evRow['chair_name'] as String;
        }
        if (evRow['coordinator_name'] != null) {
          _coordinatorNameCtrl.text = evRow['coordinator_name'] as String;
        }
      } else {
        _isCompleted = widget.event.isCompleted;
      }

      // 2. Fetch Active Template & Fields
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
        debugPrint('certificate_templates check: $e');
      }

      _activeTemplateId ??= 'event_${widget.event.id}';

      if (_activeTemplateId != null && RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(_activeTemplateId!)) {
        try {
          final fieldsRes = await _supabase
              .from('certificate_template_fields')
              .select()
              .eq('template_id', _activeTemplateId!);
          final List rows = fieldsRes as List? ?? [];
          _fieldConfigs = rows.map((r) => FieldConfig.fromMap(r as Map<String, dynamic>)).toList();
        } catch (_) {}
      }

      // 3. Fetch Attendees from BOTH attendance and registrations tables
      final Set<String> allUserIds = {};

      try {
        final attRes = await _supabase
            .from('attendance')
            .select('user_id')
            .eq('event_id', widget.event.id);
        for (final r in (attRes as List? ?? [])) {
          if (r['user_id'] != null) allUserIds.add(r['user_id'] as String);
        }
      } catch (_) {}

      try {
        final regRes = await _supabase
            .from('registrations')
            .select('user_id')
            .eq('event_id', widget.event.id);
        for (final r in (regRes as List? ?? [])) {
          if (r['user_id'] != null) allUserIds.add(r['user_id'] as String);
        }
      } catch (_) {}

      final userIdsList = allUserIds.toList();
      if (userIdsList.isNotEmpty) {
        final profilesRes = await _supabase
            .from('profiles')
            .select('id, name, email, membership_id')
            .inFilter('id', userIdsList);
        final List profiles = profilesRes as List? ?? [];
        final profileMap = Map.fromEntries(profiles.map((p) => MapEntry(p['id'] as String, p as Map<String, dynamic>)));

        _attendees = userIdsList.map((uid) {
          final prof = profileMap[uid];
          return {
            'user_id': uid,
            'name': (prof?['name'] as String?) ?? 'Member',
            'email': (prof?['email'] as String?) ?? '',
            'membership_id': (prof?['membership_id'] as String?) ?? '',
          };
        }).toList();
      } else {
        _attendees = [];
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

  // Normalization for matching
  String _normalizeText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\.(pdf|png|jpg|jpeg)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Multi-tier matching engine
  List<AttendeeCertMatch> _calculateMatches() {
    return _attendees.map((att) {
      final uid = att['user_id'] as String;

      // 0. Manual Override
      if (_manualOverrides.containsKey(uid)) {
        final overrideName = _manualOverrides[uid];
        final matched = _manualFiles.cast<CertFileItem?>().firstWhere(
              (f) => f?.name == overrideName,
              orElse: () => null,
            );
        return AttendeeCertMatch(
          attendee: att,
          matchedFile: matched,
          matchType: 'manual',
          score: 100,
        );
      }

      final cleanStudent = _normalizeText(att['name'] as String? ?? '');
      final studentTokens = cleanStudent.split(' ').where((t) => t.length > 1).toList();
      final cleanEmail = att['email'] != null && (att['email'] as String).isNotEmpty
          ? _normalizeText((att['email'] as String).split('@').first)
          : '';
      final cleanMemberId = att['membership_id'] != null
          ? _normalizeText(att['membership_id'] as String)
          : '';

      CertFileItem? bestFile;
      String bestType = 'none';
      int bestScore = 0;

      for (final f in _manualFiles) {
        final cleanFile = _normalizeText(f.name);
        final fileTokens = cleanFile.split(' ').where((t) => t.length > 1).toList();

        // 1. Exact match
        if (cleanFile == cleanStudent) {
          bestFile = f;
          bestType = 'exact';
          bestScore = 100;
          break;
        }

        // 2. Contains match
        if (cleanStudent.length >= 3 && cleanFile.contains(cleanStudent)) {
          if (bestScore < 90) {
            bestFile = f;
            bestType = 'contains';
            bestScore = 90;
          }
        } else if (cleanFile.length >= 3 && cleanStudent.contains(cleanFile)) {
          if (bestScore < 85) {
            bestFile = f;
            bestType = 'contains';
            bestScore = 85;
          }
        }

        // 3. Token match
        if (studentTokens.isNotEmpty) {
          final matchedCount = studentTokens.where((st) => fileTokens.contains(st)).length;
          final ratio = matchedCount / studentTokens.length;
          if (ratio == 1.0 && bestScore < 88) {
            bestFile = f;
            bestType = 'token';
            bestScore = 88;
          } else if (ratio >= 0.6 && bestScore < 70) {
            bestFile = f;
            bestType = 'token';
            bestScore = (ratio * 70).round();
          }
        }

        // 4. Identifier match
        if (cleanEmail.isNotEmpty && cleanFile.contains(cleanEmail) && bestScore < 80) {
          bestFile = f;
          bestType = 'contains';
          bestScore = 80;
        }
        if (cleanMemberId.isNotEmpty && cleanFile.contains(cleanMemberId) && bestScore < 80) {
          bestFile = f;
          bestType = 'contains';
          bestScore = 80;
        }
      }

      return AttendeeCertMatch(
        attendee: att,
        matchedFile: bestFile,
        matchType: bestType,
        score: bestScore,
      );
    }).toList();
  }

  Future<void> _pickCertificateFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'zip'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isExtracting = true);

      final List<CertFileItem> extracted = [];

      for (final platformFile in result.files) {
        final ext = (platformFile.extension ?? '').toLowerCase();
        final bytes = platformFile.bytes;
        if (bytes == null) continue;

        if (ext == 'zip') {
          // Unpack ZIP archive in memory
          final archive = ZipDecoder().decodeBytes(bytes);
          for (final file in archive) {
            if (file.isFile) {
              final fname = file.name.split('/').last;
              if (fname.startsWith('.') || fname.startsWith('__MACOSX')) continue;
              final fext = fname.split('.').last.toLowerCase();
              if (['pdf', 'png', 'jpg', 'jpeg'].contains(fext)) {
                extracted.add(CertFileItem(
                  name: fname,
                  bytes: file.content as List<int>,
                  extension: fext,
                ));
              }
            }
          }
        } else if (['pdf', 'png', 'jpg', 'jpeg'].contains(ext)) {
          extracted.add(CertFileItem(
            name: platformFile.name,
            bytes: bytes,
            extension: ext,
          ));
        }
      }

      setState(() {
        final existingNames = _manualFiles.map((f) => f.name).toSet();
        for (final item in extracted) {
          if (!existingNames.contains(item.name)) {
            _manualFiles.add(item);
          }
        }
        _isExtracting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded ${extracted.length} certificate file(s)!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isExtracting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading files: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _publishManualCertificates() async {
    final matches = _calculateMatches();
    final toPublish = matches.where((m) => m.matchedFile != null && !_alreadyIssuedIds.contains(m.attendee['user_id'])).toList();

    if (toPublish.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending matched certificates to publish.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: darkCardBg,
        title: Text('Publish Manual Certificates', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Upload and distribute certificates for ${toPublish.length} matched participant(s)?', style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentGreen),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Publish Now', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _failedCount = 0;
      _progressMessage = 'Distributing matched certificates...';
    });

    int successCount = 0;
    final total = toPublish.length;

    for (int i = 0; i < toPublish.length; i++) {
      final item = toPublish[i];
      final uid = item.attendee['user_id'] as String;
      final sname = item.attendee['name'] as String;
      final file = item.matchedFile!;

      setState(() {
        _progressMessage = 'Publishing for $sname (${i + 1}/$total)...';
        _processedCount = i + 1;
      });

      try {
        final storagePath = '${widget.event.id}/$uid.${file.extension}';
        final mimeType = file.extension == 'pdf' ? 'application/pdf' : 'image/${file.extension}';

        await _supabase.storage.from('certificates').uploadBinary(
          storagePath,
          Uint8List.fromList(file.bytes),
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );

        final publicUrl = _supabase.storage.from('certificates').getPublicUrl(storagePath);

        await _supabase.from('certificates').upsert({
          'event_id': widget.event.id,
          'user_id': uid,
          'student_name': sname,
          'certificate_url': publicUrl,
          'file_url': publicUrl,
          'storage_path': storagePath,
          'issued_at': DateTime.now().toIso8601String(),
          'title': 'Certificate of Participation — ${widget.event.title}',
          'description': 'Awarded for attending ${widget.event.title}',
        }, onConflict: 'event_id,user_id');

        successCount++;
      } catch (err) {
        debugPrint('Manual publish error for $sname: $err');
        _failedCount++;
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _progressMessage = '';
        _lastSuccessCount = successCount;
      });
      _loadStatsAndTemplate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully published $successCount certificate(s)!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _finalizeEventAttendance() async {
    setState(() {
      _isProcessing = true;
      _progressMessage = 'Finalizing event attendance...';
    });
    try {
      await _supabase.from('events').update({
        'attendance_finalized': true,
      }).eq('id', widget.event.id);

      setState(() => _isCompleted = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event marked as Completed! Attendance finalized.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to finalize event: $e')),
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

  Future<void> _saveTemplateAndExecom() async {
    setState(() {
      _isProcessing = true;
      _progressMessage = 'Saving template & Execom details...';
    });
    try {
      await _supabase.from('events').update({
        'template_url': _slidesUrlCtrl.text.trim(),
        'certificate_image_url': _slidesUrlCtrl.text.trim(),
        'certificate_template_type': 'slides',
        'chair_name': _chairNameCtrl.text.trim().isEmpty ? null : _chairNameCtrl.text.trim(),
        'coordinator_name': _coordinatorNameCtrl.text.trim().isEmpty ? null : _coordinatorNameCtrl.text.trim(),
      }).eq('id', widget.event.id);

      _activeTemplateUrl = _slidesUrlCtrl.text.trim();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template & Execom details updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save details: $e'), backgroundColor: Colors.red),
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: darkCardBg,
        title: Text('Publish Certificates', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('This will generate and publish certificates for ${eligible.length} attendee(s). Proceed?', style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentGreen),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Publish Now', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _failedCount = 0;
      _progressMessage = 'Downloading template image...';
    });

    int successCount = 0;
    final total = eligible.length;
    List<String> innerErrors = [];

    try {
      List<int> imageBytes = [];
      String urlStr = (_activeTemplateUrl ?? _slidesUrlCtrl.text).trim();

      final slideMatch = RegExp(r'docs\.google\.com/presentation/d/([a-zA-Z0-9_-]+)').firstMatch(urlStr);
      if (slideMatch != null) {
        final slideId = slideMatch.group(1);
        urlStr = 'https://docs.google.com/presentation/d/$slideId/export/png';
      }

      final cleanPath = urlStr.replaceFirst('template:', '');

      if (cleanPath.startsWith('http')) {
        try {
          final client = HttpClient();
          final req = await client.getUrl(Uri.parse(cleanPath));
          final res = await req.close();
          if (res.statusCode == 200) {
            imageBytes = await res.fold<List<int>>(<int>[], (acc, data) => acc..addAll(data));
          }
        } catch (_) {}
      }

      if (imageBytes.isEmpty && !cleanPath.startsWith('http')) {
        final buckets = ['certificate_templates', 'event_posters', 'certificates'];
        for (final b in buckets) {
          try {
            final downloaded = await _supabase.storage.from(b).download(cleanPath);
            if (downloaded.isNotEmpty) {
              imageBytes = downloaded;
              break;
            }
          } catch (_) {}
        }
      }

      bool isValidImage(List<int> bytes) {
        if (bytes.length < 4) return false;
        if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
        if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
        return false;
      }


      final dateStr = widget.event.date != null
          ? '${widget.event.date!.day}/${widget.event.date!.month}/${widget.event.date!.year}'
          : '';

      for (int i = 0; i < eligible.length; i++) {
        final attendee = eligible[i];
        final userId = attendee['user_id'] as String;
        final name = attendee['name'] as String;

        setState(() {
          _progressMessage = 'Publishing for $name (${i + 1}/$total)...';
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
            customOverrides: {
              'chair_name': _chairNameCtrl.text.trim().isNotEmpty ? _chairNameCtrl.text.trim() : 'Chapter Chair',
              'coord_name': _coordinatorNameCtrl.text.trim().isNotEmpty ? _coordinatorNameCtrl.text.trim() : 'Event Coordinator',
            },
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

          final certUrl = _supabase.storage.from('certificates').getPublicUrl(storagePath);

          final certPayload = {
            'event_id': widget.event.id,
            'user_id': userId,
            'student_name': name,
            'certificate_url': certUrl,
            'file_url': certUrl,
            'storage_path': storagePath,
            'issued_at': DateTime.now().toIso8601String(),
            'title': 'Certificate of Participation — ${widget.event.title}',
            'description': 'Awarded for attending ${widget.event.title}',
          };

          await _supabase.from('certificates').upsert(certPayload, onConflict: 'event_id,user_id');
          successCount++;
        } catch (err) {
          debugPrint('Error generating cert for $userId: $err');
          innerErrors.add('User $userId: $err');
          _failedCount++;
        }
      }

      if (innerErrors.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: darkCardBg,
            title: const Text('Some Certificates Failed', style: TextStyle(color: Colors.orangeAccent)),
            content: SingleChildScrollView(
              child: Text('Failed to publish $_failedCount certificates.\n\nErrors:\n${innerErrors.take(5).join('\n')}${innerErrors.length > 5 ? '\n...and more' : ''}', style: const TextStyle(color: Colors.white70)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Batch generation error: $e\n$st');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: darkCardBg,
            title: const Text('Publish Error', style: TextStyle(color: Colors.redAccent)),
            content: Text('Failed to download template or publish certificates:\n\n$e', style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
            ],
          ),
        );
      }
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
    final matches = _calculateMatches();
    final pendingMatchedCount = matches.where((m) => m.matchedFile != null && !_alreadyIssuedIds.contains(m.attendee['user_id'])).length;
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
                            Text('Total Attendees: ${_attendees.length}', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Event Finalization Banner (Informational / Non-blocking)
                  if (!_isCompleted)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.08),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Attendance Not Yet Finalized', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('Certificates can be published anytime. Finalize when ready.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                            onPressed: _isProcessing ? null : _finalizeEventAttendance,
                            child: const Text('Finalize', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accentGreen.withOpacity(0.08),
                        border: Border.all(color: accentGreen.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: accentGreen, size: 18),
                          const SizedBox(width: 10),
                          Text('Event Marked as Completed & Attendance Finalized', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Mode Selector Tabs (Automated vs Manual)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedTab = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTab == 0 ? accentBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text('⚡ Automated (Slides)', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedTab = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1 ? accentBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.folder_shared, size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text('📁 Manual (Drive / Files)', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tab 0: Automated (Google Slides)
                  if (_selectedTab == 0)
                    _buildDarkCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Google Slides Certificate Template', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: accentGreen)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _slidesUrlCtrl,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Presentation Template URL',
                              labelStyle: GoogleFonts.inter(color: Colors.white70),
                              prefixIcon: const Icon(Icons.slideshow_rounded, color: accentGreen),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _chairNameCtrl,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: r'Chairperson ({{chair_name}})',
                                    labelStyle: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _coordinatorNameCtrl,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: r'Coordinator ({{coord_name}})',
                                    labelStyle: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Save Template & Execom Details'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentGreen,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isProcessing ? null : _saveTemplateAndExecom,
                          ),
                        ],
                      ),
                    ),

                  // Tab 1: Manual (Google Drive Link / Files)
                  if (_selectedTab == 1)
                    _buildDarkCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Google Drive & Direct File Distribution', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _driveUrlCtrl,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'Google Drive Folder Link',
                                    labelStyle: GoogleFonts.inter(color: Colors.white70),
                                    prefixIcon: const Icon(Icons.link, color: Colors.amber),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.open_in_browser, color: Colors.white70),
                                onPressed: () async {
                                  final url = _driveUrlCtrl.text.trim();
                                  if (url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
                                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          InkWell(
                            onTap: _isExtracting ? null : _pickCertificateFiles,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24, width: 1.5, strokeAlign: BorderSide.strokeAlignInside),
                              ),
                              child: Column(
                                children: [
                                  if (_isExtracting)
                                    const CircularProgressIndicator(color: accentGreen)
                                  else
                                    const Icon(Icons.cloud_upload_outlined, size: 36, color: Colors.amber),
                                  const SizedBox(height: 8),
                                  Text(
                                    _isExtracting ? 'Extracting Archive...' : 'Select PDFs, Images, or a .ZIP Archive',
                                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Supports offline ZIP extraction & instant name matching', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                          if (_manualFiles.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('📁 ${_manualFiles.length} files loaded', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                                Text(
                                  'Matched: ${matches.where((m) => m.matchedFile != null).length} / ${_attendees.length}',
                                  style: GoogleFonts.inter(color: accentGreen, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Mapping preview list
                            Container(
                              constraints: const BoxConstraints(maxHeight: 250),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: matches.length,
                                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                                itemBuilder: (ctx, i) {
                                  final m = matches[i];
                                  final isIssued = _alreadyIssuedIds.contains(m.attendee['user_id']);
                                  return ListTile(
                                    dense: true,
                                    title: Text(m.attendee['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                    subtitle: Text(
                                      m.matchedFile != null ? m.matchedFile!.name : 'No file matched',
                                      style: TextStyle(color: m.matchedFile != null ? Colors.white60 : Colors.redAccent, fontSize: 11),
                                    ),
                                    trailing: isIssued
                                        ? const Text('Issued', style: TextStyle(color: accentGreen, fontWeight: FontWeight.bold, fontSize: 11))
                                        : m.matchedFile != null
                                            ? Text('Matched (${m.matchType})', style: const TextStyle(color: accentBlue, fontSize: 11))
                                            : const Text('Unmatched', style: TextStyle(color: Colors.amber, fontSize: 11)),
                                  );
                                },
                              ),
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

                  // Big Action Button (Unblocked from _isCompleted)
                  if (_selectedTab == 0)
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 22),
                        label: Text(
                          'Publish to $pendingCount Pending Participants',
                          style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (pendingCount > 0 && _activeTemplateUrl != null && !_isProcessing) ? Colors.amber[700] : Colors.white12,
                          foregroundColor: (pendingCount > 0 && _activeTemplateUrl != null && !_isProcessing) ? Colors.black : Colors.white38,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: (pendingCount == 0 || _activeTemplateUrl == null || _isProcessing) ? null : _generateAllCertificates,
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 22),
                        label: Text(
                          'Publish $pendingMatchedCount Matched Certificates',
                          style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (pendingMatchedCount > 0 && !_isProcessing) ? accentGreen : Colors.white12,
                          foregroundColor: (pendingMatchedCount > 0 && !_isProcessing) ? Colors.black : Colors.white38,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: (pendingMatchedCount == 0 || _isProcessing) ? null : _publishManualCertificates,
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
