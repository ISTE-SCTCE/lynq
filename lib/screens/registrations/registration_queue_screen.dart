import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/auth_provider.dart';
import '../../core/membership_id.dart';
import '../../models/task_models.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/glass_card.dart';
import '../../core/theme.dart';
import 'registration_service.dart';



class RegistrationQueueScreen extends StatefulWidget {
  final int initialIndex;
  final Map<String, List<RegistrationQueueModel>>? initialGroupedData;

  const RegistrationQueueScreen({
    super.key,
    this.initialIndex = 0,
    this.initialGroupedData,
  });

  @override
  State<RegistrationQueueScreen> createState() => _RegistrationQueueScreenState();
}

class _RegistrationQueueScreenState extends State<RegistrationQueueScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  Map<String, List<RegistrationQueueModel>> _grouped = {};
  bool _isLoading = true;
  bool _isSyncing = false;
  int _totalMembers = 0;
  String _searchQuery = '';

  final _tabs = ['Pending', 'Approved', 'Rejected'];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialIndex);
    
    if (widget.initialGroupedData != null) {
      _grouped = widget.initialGroupedData!;
      _isLoading = false;
    } else {
      _loadQueue();
    }

    // The intake endpoint is protected, so the app refreshes its small queue
    // automatically instead of exposing registrations to the public data API.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadQueue());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    setState(() => _isLoading = true);
    try {
      final result = await RegistrationService.fetchRegistrationData(_supabase);
      if (mounted) {
        setState(() {
          _totalMembers = result['totalMembers'] as int;
          _grouped = result['grouped'] as Map<String, List<RegistrationQueueModel>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Registration Queue', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_rounded),
            tooltip: 'Export Approved Members',
            onPressed: _exportExcel,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _buildTabBar(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadQueue,
              child: TabBarView(
                controller: _tabController,
                children: _tabs.map((t) => _buildList(_grouped[t] ?? [])).toList(),
              ),
            ),
    );
  }

  Widget _buildTabBar() {
    final counts = _tabs.map((t) => _grouped[t]?.length ?? 0).toList();
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: AppTheme.secondary,
      labelColor: AppTheme.secondary,
      unselectedLabelColor: Colors.grey,
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      tabs: List.generate(
        _tabs.length,
        (i) => Tab(text: '${_tabs[i]} (${counts[i]})'),
      ),
    );
  }

  Widget _buildList(List<RegistrationQueueModel> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No registrations found', style: GoogleFonts.inter(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _RegistrationCard(
        registration: items[i],
        onTap: () => _showDetail(context, items[i]),
      ),
    );
  }

  void _showDetail(BuildContext context, RegistrationQueueModel reg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RegistrationDetailSheet(
        registration: reg,
        onAction: _loadQueue,
      ),
    );
  }

  Future<void> _exportExcel() async {
    setState(() => _isSyncing = true);
    try {
      final response = await _supabase.from('profiles').select().order('created_at', ascending: false);
      
      var excel = xl.Excel.createExcel();
      xl.Sheet sheetObject = excel['Members'];
      excel.setDefaultSheet('Members');
      
      sheetObject.appendRow([
        xl.TextCellValue('ISTE ID'),
        xl.TextCellValue('Name'),
        xl.TextCellValue('Email'),
        xl.TextCellValue('Phone'),
        xl.TextCellValue('Branch'),
        xl.TextCellValue('Plan'),
        xl.TextCellValue('Role'),
        xl.TextCellValue('Status'),
        xl.TextCellValue('Joined At'),
      ]);

      for (var row in response) {
        sheetObject.appendRow([
          xl.TextCellValue(row['iste_id']?.toString() ?? ''),
          xl.TextCellValue(row['name']?.toString() ?? ''),
          xl.TextCellValue(row['email']?.toString() ?? ''),
          xl.TextCellValue(row['phone']?.toString() ?? ''),
          xl.TextCellValue(row['branch']?.toString() ?? ''),
          xl.TextCellValue(row['plan']?.toString() ?? ''),
          xl.TextCellValue(row['role']?.toString() ?? ''),
          xl.TextCellValue(row['status']?.toString() ?? ''),
          xl.TextCellValue(row['created_at']?.toString() ?? ''),
        ]);
      }

      final bytes = excel.encode();
      if (bytes != null) {
        if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
          final String? outputFile = await FilePicker.platform.saveFile(
            dialogTitle: 'Save Members Excel File',
            fileName: 'members_export.xlsx',
            type: FileType.custom,
            allowedExtensions: ['xlsx'],
          );

          if (outputFile != null) {
            await File(outputFile).writeAsBytes(bytes);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export saved to $outputFile'), backgroundColor: Colors.green));
            }
          }
        } else {
          // If web or mobile, could use universal_html or share_plus.
          throw Exception('Export currently requires Desktop OS (Windows/Mac/Linux).');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }
}

// ── Registration Card ──────────────────────────────────────────────────────

class _RegistrationCard extends StatelessWidget {
  final RegistrationQueueModel registration;
  final VoidCallback onTap;

  const _RegistrationCard({required this.registration, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: registration.statusColor.withValues(alpha: 0.15),
                child: Text(
                  registration.name.isNotEmpty ? registration.name[0].toUpperCase() : '?',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20, 
                    fontWeight: FontWeight.bold,
                    color: registration.statusColor
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(registration.name,
                        style: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${registration.email}',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                    if (registration.rollNumber != null && registration.rollNumber!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('${registration.rollNumber} · ${registration.branch ?? ""}',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: registration.statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(registration.statusLabel,
                        style: GoogleFonts.inter(
                            fontSize: 10, fontWeight: FontWeight.bold,
                            color: registration.statusColor)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    registration.createdAt != null
                        ? '${registration.createdAt!.day}/${registration.createdAt!.month}/${registration.createdAt!.year}'
                        : '',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Registration Detail Sheet ──────────────────────────────────────────────

class _RegistrationDetailSheet extends StatefulWidget {
  final RegistrationQueueModel registration;
  final VoidCallback onAction;

  const _RegistrationDetailSheet({required this.registration, required this.onAction});

  @override
  State<_RegistrationDetailSheet> createState() => _RegistrationDetailSheetState();
}

class _RegistrationDetailSheetState extends State<_RegistrationDetailSheet> {
  final _supabase = Supabase.instance.client;
  bool _isProcessing = false;

  final _isteIdCtrl = TextEditingController();
  String? _membershipIdError;

  @override
  void dispose() {
    _isteIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reg = widget.registration;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              // Name + status
              Row(
                children: [
                  Expanded(
                    child: Text(reg.name,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: reg.statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(reg.statusLabel,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: reg.statusColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Details
              _detailRow(Icons.email_rounded, 'Email', reg.email),
              _detailRow(Icons.phone_rounded, 'Phone', reg.phone ?? '—'),
              _detailRow(Icons.badge_rounded, 'Roll Number', reg.rollNumber ?? '—'),
              _detailRow(Icons.school_rounded, 'Branch', reg.branch ?? '—'),
              _detailRow(Icons.calendar_today_rounded, 'Year', reg.year ?? '—'),
              _detailRow(Icons.card_membership_rounded, 'Membership', reg.membershipType),
              _detailRow(Icons.payments_rounded, 'Payment', reg.paymentStatus),
              _detailRow(Icons.source_rounded, 'Source', reg.source),
              
               // Action buttons
               if (reg.status == 'pending') ...[
                TextField(
                  controller: _isteIdCtrl,
                  enabled: !_isProcessing,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Official ISTE membership ID',
                    hintText: 'KE104010',
                    helperText: 'Required to approve. Enter the ID issued by ISTE.',
                    errorText: _membershipIdError,
                  ),
                ),
                const SizedBox(height: 20),
                _isProcessing
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _action('rejected'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade400,
                                        side: BorderSide(color: Colors.red.shade400.withValues(alpha: 0.5)),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      label: Text('Reject',
                                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _action('approved'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.darkGreen,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        elevation: 0,
                                      ),
                                      icon: const Icon(Icons.check_rounded, size: 18),
                                      label: Text('Approve',
                                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Text('$label:',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _action(String status) async {
    if (_isProcessing) return;
    final membershipId = normalizeMembershipId(_isteIdCtrl.text);
    if (status == 'approved' && !isOfficialMembershipId(membershipId)) {
      setState(() => _membershipIdError = 'Use KE104 followed by three digits.');
      return;
    }
    setState(() => _membershipIdError = null);
    setState(() => _isProcessing = true);
    try {
      final registrationId =
          widget.registration.rawData['central_registration_id']?.toString();
      if (registrationId == null || registrationId.isEmpty) {
        throw Exception('This legacy registration cannot be reviewed here.');
      }

      await RegistrationService.reviewRegistration(
        _supabase,
        registrationId: registrationId,
        status: status,
        membershipId: status == 'approved' ? membershipId : null,
      );

      widget.onAction();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
