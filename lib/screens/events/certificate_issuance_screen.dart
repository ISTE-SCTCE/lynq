import 'dart:io';
import 'dart:convert';
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

class CertFileMatch {
  final CertFileItem file;
  Map<String, dynamic>? matchedUser;
  String matchType; // 'exact', 'contains', 'token', 'manual', 'email', 'none'
  int score;

  CertFileMatch({
    required this.file,
    this.matchedUser,
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

  // Non-Attendance List Mode State
  bool _publishWithoutAttendance = false;
  List<Map<String, dynamic>> _allMlynqUsers = [];
  bool _isLoadingMlynqUsers = false;
  bool _isFetchingDrive = false;
  final Map<String, String> _fileToUserManualOverrides = {}; // fileName -> userId

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
          final uid = r['user_id']?.toString();
          if (uid != null && uid.isNotEmpty) allUserIds.add(uid);
        }
      } catch (e) {
        debugPrint('Attendance fetch error: $e');
      }

      try {
        final regRes = await _supabase
            .from('registrations')
            .select('user_id')
            .eq('event_id', widget.event.id);
        for (final r in (regRes as List? ?? [])) {
          final uid = r['user_id']?.toString();
          if (uid != null && uid.isNotEmpty) allUserIds.add(uid);
        }
      } catch (e) {
        debugPrint('Registrations fetch error: $e');
      }

      final userIdsList = allUserIds.toList();
      if (userIdsList.isNotEmpty) {
        Map<String, Map<String, dynamic>> profileMap = {};
        try {
          // Use iste_membership_id (the actual column in profiles table)
          final profilesRes = await _supabase
              .from('profiles')
              .select('id, name, email, iste_membership_id')
              .inFilter('id', userIdsList);
          final List profiles = profilesRes as List? ?? [];
          for (final p in profiles) {
            if (p is Map<String, dynamic> && p['id'] != null) {
              profileMap[p['id'].toString()] = p;
            }
          }
        } catch (e) {
          debugPrint('Profiles fetch error in certificate issuance: $e');
        }

        _attendees = userIdsList.map((uid) {
          final prof = profileMap[uid];
          return {
            'user_id': uid,
            'name': (prof?['name'] as String?)?.trim().isNotEmpty == true
                ? (prof!['name'] as String).trim()
                : 'Member',
            'email': (prof?['email'] as String?) ?? '',
            'membership_id': (prof?['iste_membership_id'] as String?) ??
                (prof?['membership_id'] as String?) ??
                '',
          };
        }).toList();
      } else {
        _attendees = [];
      }

      // 4. Fetch Already Issued Certificates (isolated so profile or cert issues do not block each other)
      try {
        final certsRes = await _supabase
            .from('certificates')
            .select('user_id')
            .eq('event_id', widget.event.id);
        final List certRows = certsRes as List? ?? [];
        _alreadyIssuedIds = certRows
            .map((r) => r['user_id']?.toString())
            .whereType<String>()
            .toSet();
      } catch (e) {
        debugPrint('Certificates fetch error: $e');
        _alreadyIssuedIds = {};
      }

      // 5. Fetch all m-Lynq profiles for 'Publish without Attendance List' mode
      await _loadAllMlynqProfiles(silent: true);

    } catch (e) {
      debugPrint('Error loading stats: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAllMlynqProfiles({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingMlynqUsers = true);
    try {
      final profilesRes = await _supabase
          .from('profiles')
          .select('id, name, email, iste_membership_id')
          .order('name');
      final List profiles = profilesRes as List? ?? [];
      _allMlynqUsers = profiles.map((p) {
        return {
          'user_id': p['id']?.toString() ?? '',
          'name': (p['name'] as String?)?.trim().isNotEmpty == true
              ? (p['name'] as String).trim()
              : 'Member',
          'email': (p['email'] as String?) ?? '',
          'membership_id': (p['iste_membership_id'] as String?) ??
              (p['membership_id'] as String?) ??
              '',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error loading all mlynq profiles: $e');
    } finally {
      if (!silent && mounted) setState(() => _isLoadingMlynqUsers = false);
    }
  }

  // Normalization for matching
  String _normalizeText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\.(pdf|png|jpg|jpeg)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'^(certificate|cert|participation|attendance)[_\-\s]+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Multi-tier matching engine for Non-Attendance List mode (File -> m-Lynq User)
  List<CertFileMatch> _calculateMatchesForFiles() {
    return _manualFiles.map((file) {
      // 0. Manual Override
      if (_fileToUserManualOverrides.containsKey(file.name)) {
        final overrideUserId = _fileToUserManualOverrides[file.name];
        final matched = _allMlynqUsers.cast<Map<String, dynamic>?>().firstWhere(
              (u) => u?['user_id'] == overrideUserId,
              orElse: () => null,
            );
        return CertFileMatch(
          file: file,
          matchedUser: matched,
          matchType: 'manual',
          score: 100,
        );
      }

      final cleanFile = _normalizeText(file.name);
      final fileTokens = cleanFile.split(' ').where((t) => t.length > 1).toList();

      Map<String, dynamic>? bestUser;
      String bestType = 'none';
      int bestScore = 0;

      for (final user in _allMlynqUsers) {
        final cleanStudent = _normalizeText(user['name'] as String? ?? '');
        final studentTokens = cleanStudent.split(' ').where((t) => t.length > 1).toList();
        final cleanEmail = user['email'] != null && (user['email'] as String).isNotEmpty
            ? _normalizeText((user['email'] as String).split('@').first)
            : '';
        final cleanMemberId = user['membership_id'] != null
            ? _normalizeText(user['membership_id'] as String)
            : '';

        // 1. Exact match
        if (cleanFile == cleanStudent && cleanFile.isNotEmpty) {
          bestUser = user;
          bestType = 'exact';
          bestScore = 100;
          break; // Perfect match
        }

        // 2. Contains match
        if (cleanStudent.length >= 3 && cleanFile.contains(cleanStudent)) {
          if (bestScore < 90) {
            bestUser = user;
            bestType = 'contains';
            bestScore = 90;
          }
        } else if (cleanFile.length >= 3 && cleanStudent.contains(cleanFile)) {
          if (bestScore < 85) {
            bestUser = user;
            bestType = 'contains';
            bestScore = 85;
          }
        }

        // 3. Token match
        if (studentTokens.isNotEmpty) {
          final matchedCount = studentTokens.where((st) => fileTokens.contains(st)).length;
          final ratio = matchedCount / studentTokens.length;
          if (ratio == 1.0 && bestScore < 88) {
            bestUser = user;
            bestType = 'token';
            bestScore = 88;
          } else if (ratio >= 0.6 && bestScore < 70) {
            final calculated = (ratio * 70).round();
            if (calculated > bestScore) {
              bestUser = user;
              bestType = 'token';
              bestScore = calculated;
            }
          }
        }

        // 4. Identifier match
        if (cleanEmail.isNotEmpty && cleanFile.contains(cleanEmail) && bestScore < 80) {
          bestUser = user;
          bestType = 'email';
          bestScore = 80;
        }
        if (cleanMemberId.isNotEmpty && cleanFile.contains(cleanMemberId) && bestScore < 80) {
          bestUser = user;
          bestType = 'membership_id';
          bestScore = 80;
        }
      }

      return CertFileMatch(
        file: file,
        matchedUser: bestScore >= 60 ? bestUser : null,
        matchType: bestScore >= 60 ? bestType : 'none',
        score: bestScore,
      );
    }).toList();
  }

  // Dialog to manually assign an m-Lynq user to a file
  Future<void> _showUserSelectDialog(String fileName) async {
    String search = '';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final filtered = _allMlynqUsers.where((u) {
            final name = (u['name'] as String? ?? '').toLowerCase();
            final email = (u['email'] as String? ?? '').toLowerCase();
            final q = search.toLowerCase();
            return name.contains(q) || email.contains(q);
          }).toList();

          return AlertDialog(
            backgroundColor: darkCardBg,
            title: Text('Assign m-Lynq User', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Certificate file: $fileName', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 12),
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search by student name or email...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white60),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                    ),
                    onChanged: (val) => setDlgState(() => search = val),
                  ),
                  const SizedBox(height: 10),
                  Text('Showing ${filtered.length} m-Lynq user(s):', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, idx) {
                        final u = filtered[idx];
                        final isSelected = _fileToUserManualOverrides[fileName] == u['user_id'];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          title: Text(u['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text('${u['email']}${u['membership_id'] != '' ? ' • ID: ${u['membership_id']}' : ''}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: accentGreen, size: 18)
                              : const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
                          onTap: () {
                            setState(() {
                              _fileToUserManualOverrides[fileName] = u['user_id'] as String;
                            });
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _fileToUserManualOverrides.remove(fileName);
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Clear Assignment', style: TextStyle(color: Colors.redAccent)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
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

  Future<void> _fetchCertificatesFromDrive() async {
    final rawUrl = _driveUrlCtrl.text.trim();
    if (rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Google Drive link first.')),
      );
      return;
    }

    setState(() => _isFetchingDrive = true);

    try {
      // 1. Check if it is a Drive file or ZIP download link
      final fileIdMatch = RegExp(r'(?:file\/d\/|open\?id=|uc\?id=|drive\.google\.com\/uc\?export=download&id=)([a-zA-Z0-9_-]+)').firstMatch(rawUrl);
      final folderIdMatch = RegExp(r'drive\.google\.com\/(?:drive\/(?:u\/\d+\/)?folders\/)([a-zA-Z0-9_-]+)').firstMatch(rawUrl);

      if (fileIdMatch != null) {
        final fileId = fileIdMatch.group(1)!;
        final downloadUrl = 'https://drive.google.com/uc?export=download&id=$fileId';

        final client = HttpClient();
        client.autoUncompress = true;
        final req = await client.getUrl(Uri.parse(downloadUrl));
        req.followRedirects = true;
        req.maxRedirects = 5;
        final res = await req.close();

        List<int> bytes = await res.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));

        // Check if there is a Google large file confirmation page
        if (bytes.length < 60000) {
          try {
            final htmlStr = utf8.decode(bytes);
            final confirmToken = RegExp(r'confirm=([0-9a-zA-Z_-]+)').firstMatch(htmlStr)?.group(1);
            if (confirmToken != null) {
              final confirmUrl = 'https://drive.google.com/uc?export=download&confirm=$confirmToken&id=$fileId';
              final confirmReq = await client.getUrl(Uri.parse(confirmUrl));
              confirmReq.followRedirects = true;
              final confirmRes = await confirmReq.close();
              bytes = await confirmRes.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
            }
          } catch (_) {}
        }

        if (bytes.isEmpty) {
          throw Exception('Downloaded file is empty or link is not public.');
        }

        final List<CertFileItem> extracted = [];

        // Check if it's a ZIP archive (magic bytes PK = 0x50, 0x4B)
        if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
          final archive = ZipDecoder().decodeBytes(bytes);
          for (final f in archive) {
            if (f.isFile) {
              final fname = f.name.split('/').last;
              if (fname.startsWith('.') || fname.startsWith('__MACOSX')) continue;
              final fext = fname.split('.').last.toLowerCase();
              if (['pdf', 'png', 'jpg', 'jpeg'].contains(fext)) {
                extracted.add(CertFileItem(
                  name: fname,
                  bytes: f.content as List<int>,
                  extension: fext,
                ));
              }
            }
          }
        } else if (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
          // Direct PDF
          extracted.add(CertFileItem(
            name: 'drive_certificate.pdf',
            bytes: bytes,
            extension: 'pdf',
          ));
        } else if (bytes.length > 4 && ((bytes[0] == 0x89 && bytes[1] == 0x50) || (bytes[0] == 0xFF && bytes[1] == 0xD8))) {
          // Direct Image
          final ext = bytes[0] == 0x89 ? 'png' : 'jpg';
          extracted.add(CertFileItem(
            name: 'drive_certificate.$ext',
            bytes: bytes,
            extension: ext,
          ));
        } else {
          throw Exception('The link did not return a valid ZIP, PDF, or image file. Please ensure it is publicly shared.');
        }

        if (extracted.isEmpty) {
          throw Exception('No valid certificate files (.pdf, .png, .jpg) found inside the archive.');
        }

        setState(() {
          final existingNames = _manualFiles.map((f) => f.name).toSet();
          for (final item in extracted) {
            if (!existingNames.contains(item.name)) {
              _manualFiles.add(item);
            }
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully imported ${extracted.length} certificate(s) from Drive!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (folderIdMatch != null) {
        // Google Drive Folder link
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: darkCardBg,
              title: Text('Google Drive Folder Link', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text(
                'Google requires a browser session to package entire folders into a ZIP archive.\n\n'
                'To load certificates from this folder:\n'
                '1. Tap "Open Drive" to view the folder in browser\n'
                '2. Click "Download All" to save the folder as a .ZIP\n'
                '3. Tap "Select PDFs, Images, or a .ZIP Archive" below to import all certificates instantly!\n\n'
                'Or, upload the ZIP file directly to Google Drive and paste the file link here.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('Open Drive'),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    if (await canLaunchUrl(Uri.parse(rawUrl))) {
                      await launchUrl(Uri.parse(rawUrl), mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception('Unrecognized Google Drive URL format. Please paste a valid Google Drive file or folder link.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import from Drive: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingDrive = false);
    }
  }

  Future<void> _publishCertificatesWithoutAttendance() async {
    final fileMatches = _calculateMatchesForFiles();
    final toPublish = fileMatches.where((m) => m.matchedUser != null && !_alreadyIssuedIds.contains(m.matchedUser!['user_id'])).toList();

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
        title: Text(
          'Publish without Attendance List',
          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Upload and issue certificates for ${toPublish.length} matched participant(s) directly to their m-Lynq accounts? (No prior attendance list required)',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
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
      _progressMessage = 'Distributing certificates to m-Lynq users...';
    });

    int successCount = 0;
    final total = toPublish.length;

    for (int i = 0; i < toPublish.length; i++) {
      final item = toPublish[i];
      final uid = item.matchedUser!['user_id'] as String;
      final sname = item.matchedUser!['name'] as String;
      final file = item.file;

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

        // Optional attendance sync so they also appear as present for this event
        try {
          await _supabase.from('attendance').upsert({
            'event_id': widget.event.id,
            'user_id': uid,
          }, onConflict: 'event_id,user_id');
        } catch (_) {}

        successCount++;
      } catch (err) {
        debugPrint('Publish without attendance error for $sname: $err');
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
        SnackBar(
          content: Text('Successfully published $successCount certificate(s) to m-Lynq users!'),
          backgroundColor: Colors.green,
        ),
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

    List<Map<String, dynamic>> eligible = _attendees.where((a) => !_alreadyIssuedIds.contains(a['user_id'])).toList();
    bool isRegenerate = false;

    if (eligible.isEmpty) {
      if (_attendees.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No attendees found for this event.')),
        );
        return;
      }
      eligible = List.from(_attendees);
      isRegenerate = true;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: darkCardBg,
        title: Text(isRegenerate ? 'Re-publish Certificates' : 'Publish Certificates', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          isRegenerate
              ? 'All ${eligible.length} attendee(s) already have certificates. Do you want to re-generate and overwrite them with the current template?'
              : 'This will generate and publish certificates for ${eligible.length} attendee(s). Proceed?',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentGreen),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isRegenerate ? 'Overwrite & Re-publish' : 'Publish Now', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
            // No customOverrides — chair/coord names are baked into the template image
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

    final fileMatches = _calculateMatchesForFiles();
    final pendingFileMatchedCount = fileMatches.where((m) => m.matchedUser != null && !_alreadyIssuedIds.contains(m.matchedUser!['user_id'])).length;

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
          : RefreshIndicator(
              color: accentGreen,
              onRefresh: _loadStatsAndTemplate,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Google Drive & File Distribution',
                                style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
                              ),
                              if (_isLoadingMlynqUsers)
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen)),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Option: Publish without Attendance List (Toggle Card)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: _publishWithoutAttendance ? accentGreen.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _publishWithoutAttendance ? accentGreen.withOpacity(0.4) : Colors.white12,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _publishWithoutAttendance ? Icons.supervised_user_circle_rounded : Icons.people_outline_rounded,
                                  color: _publishWithoutAttendance ? accentGreen : Colors.white70,
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Publish without Attendance List',
                                        style: GoogleFonts.spaceGrotesk(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _publishWithoutAttendance
                                            ? 'Active: Matching files against all ${_allMlynqUsers.length} registered m-Lynq students'
                                            : 'Inactive: Matching only against ${_attendees.length} event attendees',
                                        style: GoogleFonts.inter(
                                          color: Colors.white60,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _publishWithoutAttendance,
                                  activeColor: accentGreen,
                                  onChanged: (val) {
                                    setState(() => _publishWithoutAttendance = val);
                                    if (val && _allMlynqUsers.isEmpty) {
                                      _loadAllMlynqProfiles();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Google Drive Link Input + Fetch Action
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _driveUrlCtrl,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'Google Drive Link (ZIP archive, PDF, or folder)',
                                    labelStyle: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                                    prefixIcon: const Icon(Icons.link, color: Colors.amber),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: _isFetchingDrive
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                    : const Icon(Icons.cloud_download_outlined, size: 18),
                                label: Text(
                                  _isFetchingDrive ? 'Fetching...' : 'Fetch',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                onPressed: _isFetchingDrive ? null : _fetchCertificatesFromDrive,
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.open_in_browser, color: Colors.white70),
                                tooltip: 'Open in Browser',
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

                          // Direct File / ZIP Selection
                          InkWell(
                            onTap: _isExtracting ? null : _pickCertificateFiles,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
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
                                    const Icon(Icons.cloud_upload_outlined, size: 34, color: Colors.amber),
                                  const SizedBox(height: 8),
                                  Text(
                                    _isExtracting ? 'Extracting Archive...' : 'Or Select PDFs, Images, or a .ZIP Archive',
                                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _publishWithoutAttendance
                                        ? 'Loads certificates and matches student names with all m-Lynq logins'
                                        : 'Loads certificates and matches with event attendees',
                                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Files and Match Results Section
                          if (_manualFiles.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            if (_publishWithoutAttendance) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('📁 ${_manualFiles.length} files loaded', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                                  Text(
                                    'Matched with m-Lynq: ${fileMatches.where((m) => m.matchedUser != null).length} / ${_manualFiles.length}',
                                    style: GoogleFonts.inter(color: accentGreen, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Preview list for file -> m-Lynq user matching
                              Container(
                                constraints: const BoxConstraints(maxHeight: 280),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: fileMatches.length,
                                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                                  itemBuilder: (ctx, i) {
                                    final m = fileMatches[i];
                                    final isIssued = m.matchedUser != null && _alreadyIssuedIds.contains(m.matchedUser!['user_id']);
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        m.file.name,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        m.matchedUser != null
                                            ? '👤 ${m.matchedUser!['name']} (${m.matchedUser!['email']})'
                                            : '⚠️ No m-Lynq user matched. Tap edit to assign manually.',
                                        style: TextStyle(
                                          color: m.matchedUser != null ? Colors.white70 : Colors.amberAccent,
                                          fontSize: 11,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isIssued)
                                            const Text('Issued', style: TextStyle(color: accentGreen, fontWeight: FontWeight.bold, fontSize: 11))
                                          else if (m.matchedUser != null)
                                            Text('Matched (${m.matchType})', style: const TextStyle(color: accentBlue, fontSize: 11))
                                          else
                                            const Text('Unmatched', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: const Icon(Icons.edit_note, size: 20, color: Colors.white60),
                                            tooltip: 'Assign m-Lynq User',
                                            onPressed: () => _showUserSelectDialog(m.file.name),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ] else ...[
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
                              // Mapping preview list for attendee -> file matching
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
                              value: _publishWithoutAttendance
                                  ? (_manualFiles.isEmpty ? 0 : (_processedCount / _manualFiles.length).clamp(0.0, 1.0))
                                  : (_attendees.isEmpty ? 0 : (_processedCount / (_attendees.length - _alreadyIssuedIds.length)).clamp(0.0, 1.0)),
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
                  else if (_publishWithoutAttendance)
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 22),
                        label: Text(
                          'Publish $pendingFileMatchedCount Matched Certificates to m-Lynq Users',
                          style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (pendingFileMatchedCount > 0 && !_isProcessing) ? accentGreen : Colors.white12,
                          foregroundColor: (pendingFileMatchedCount > 0 && !_isProcessing) ? Colors.black : Colors.white38,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: (pendingFileMatchedCount == 0 || _isProcessing) ? null : _publishCertificatesWithoutAttendance,
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
