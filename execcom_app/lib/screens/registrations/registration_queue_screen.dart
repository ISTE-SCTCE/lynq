import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_provider.dart';
import '../../models/task_models.dart';

const List<Map<String, dynamic>> _cachedExcelData = [
  {"Timestamp":"2026-04-09T06:21:00.000Z","Name":"Gayathri AS ","DOB":"2007-02-09T18:30:00.000Z","Year":1,"Branch":"Electronics and Communication","Phone":9539338741,"Email":"asgayathri48@gmail.com","Membership":649,"TransactionID":1604247191,"Forum":"None Selected"},
  {"Timestamp":"2026-04-11T08:15:15.000Z","Name":"Parthasarathy","DOB":"2005-06-05T18:30:00.000Z","Year":2,"Branch":"Mechanical Engineering","Phone":8590467936,"Email":"parthasarathy03062005@gmail.com","Membership":649,"TransactionID":61013161514,"Forum":"None Selected"},
  {"Timestamp":"2026-04-11T16:43:52.000Z","Name":"Viswajith S S","DOB":"2006-08-17T18:30:00.000Z","Year":2,"Branch":"Electronics and Communication","Phone":6238969245,"Email":"viswajithss18@gmail.com","Membership":1199,"TransactionID":"CICAgNicmPmZBA","Forum":"EXIS Forum (149)"},
  {"Timestamp":"2026-04-12T04:30:10.000Z","Name":"Sreeram PS","DOB":"2006-09-15T18:30:00.000Z","Year":1,"Branch":"Electronics and Communication","Phone":8848360097,"Email":"sreeramps1609@gmail.com","Membership":649,"TransactionID":646857101286,"Forum":"EXIS Forum (149)"},
  {"Timestamp":"2026-04-17T12:31:13.000Z","Name":"Ganesh G","DOB":"2006-05-30T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":9446967119,"Email":"ganeshgopal3106@gmail.com","Membership":649,"TransactionID":610751875169,"Forum":"BITS Forum (129)"},
  {"Timestamp":"2026-04-18T11:12:25.000Z","Name":"ABHINANTH S NATH","DOB":"2006-03-27T18:30:00.000Z","Year":2,"Branch":"Electronics and Communication","Phone":7012826799,"Email":"abinanth@gmail.com","Membership":649,"TransactionID":646583738939,"Forum":"None Selected"},
  {"Timestamp":"2026-04-18T11:14:43.000Z","Name":"CHINAMAYI","DOB":"2006-03-27T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":9567440301,"Email":"chinmayi@gmail.com","Membership":649,"TransactionID":610126297897,"Forum":"None Selected"},
  {"Timestamp":"2026-04-21T05:32:42.000Z","Name":"ADARSH P VINOD","DOB":"2006-01-27T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":8547313055,"Email":"adarshcr4@gmail.com","Membership":1199,"TransactionID":611163459768,"Forum":"SWaS Forum (299)"},
  {"Timestamp":"2026-04-22T16:02:51.000Z","Name":"Manupriya prasad ","DOB":"2007-04-17T18:30:00.000Z","Year":1,"Branch":"Mechanical and Automobile Engineering","Phone":8075619064,"Email":"manupriyaa7prasad@gmail.com","Membership":1499,"TransactionID":611283130594,"Forum":"SWaS Forum (299), TORQ Forum (129)"},
  {"Timestamp":"2026-04-23T03:36:20.000Z","Name":"Arjun S","DOB":"2006-12-17T18:30:00.000Z","Year":2,"Branch":"Mechanical Engineering","Phone":9947584831,"Email":"arjuns8267@gmail.com","Membership":649,"TransactionID":90602688981,"Forum":"TORQ Forum (129)"},
  {"Timestamp":"2026-04-23T07:34:32.000Z","Name":"MOHAMMED FARHAN","DOB":"2006-07-26T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":7907726056,"Email":"farhanmohammed2706@gmail.com","Membership":649,"TransactionID":611309859624,"Forum":"None Selected"},
  {"Timestamp":"2026-04-23T08:13:56.000Z","Name":"Joneth Jills","DOB":"2006-05-29T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":8848615115,"Email":"jonethjillsff@gmail.com","Membership":649,"TransactionID":647975757708,"Forum":"None Selected"},
  {"Timestamp":"2026-04-23T15:52:56.000Z","Name":"THANU SREE N","DOB":"2006-08-14T18:30:00.000Z","Year":2,"Branch":"Mechanical and Automobile Engineering","Phone":7306961915,"Email":"thanusreenubi@gmail.com","Membership":649,"TransactionID":611347302744,"Forum":"None Selected"},
  {"Timestamp":"2026-05-06T09:47:29.000Z","Name":"Thejas Krishna","DOB":"2006-12-04T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":8129047109,"Email":"thejask9495@gmail.com","Membership":649,"TransactionID":612601555589,"Forum":"None Selected"},
  {"Timestamp":"2026-05-13T05:33:59.000Z","Name":"Ashishna Shahul S ","DOB":"2005-11-24T18:30:00.000Z","Year":2,"Branch":"Computer Science","Phone":6374128384,"Email":"ars.suru786@gmail.com","Membership":1199,"TransactionID":613354433613,"Forum":"SWaS Forum (299), BITS Forum (129)"}
];

class RegistrationQueueScreen extends StatefulWidget {
  const RegistrationQueueScreen({super.key});

  @override
  State<RegistrationQueueScreen> createState() => _RegistrationQueueScreenState();
}

class _RegistrationQueueScreenState extends State<RegistrationQueueScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  Map<String, List<RegistrationQueueModel>> _grouped = {};
  bool _isLoading = true;
  String _searchQuery = '';

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _sage = Color(0xFFB8C4A9);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  final _tabs = ['Pending', 'Payment', 'Approved', 'Rejected', 'Excel Intake'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadQueue();

    // Realtime subscription for new registrations
    _supabase
        .channel('registration_queue')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'registration_queue',
          callback: (_) => _loadQueue(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch live queue from Supabase
      final data = await _supabase
          .from('registration_queue')
          .select()
          .order('created_at', ascending: false);

      final list = (data as List)
          .map((e) => RegistrationQueueModel.fromJson(e as Map<String, dynamic>))
          .toList();

      // 2. Fetch live data from Google Sheets Macro
      List<RegistrationQueueModel> sheetsList = [];
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final request = await client.getUrl(Uri.parse('https://script.google.com/macros/s/AKfycbwSaurzyOEbeJoKTVgCqVhy-esPWq2HpU6UOtfK_7Ds5p7Kisz736_m2k6UnwnWP2Jg/exec'));
        final response = await request.close();
        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final List<dynamic> decoded = jsonDecode(responseBody);
          sheetsList = decoded.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value as Map<String, dynamic>;
            return RegistrationQueueModel(
              id: 9000 + idx,
              name: (item['Name'] as String?)?.trim() ?? 'No Name',
              email: (item['Email'] as String?)?.trim() ?? '',
              phone: item['Phone'] != null ? item['Phone'].toString() : '',
              branch: item['Branch'] as String? ?? '',
              year: item['Year'] != null ? item['Year'].toString() : '',
              membershipType: '₹${item["Membership "] ?? item["Membership"] ?? "649"} (${item["Forum"] ?? "None"})',
              paymentStatus: 'paid',
              rollNumber: item['TransactionID'] != null ? item['TransactionID'].toString() : '',
              source: 'Google Sheet Excel',
              status: 'excel_intake',
              createdAt: item['Timestamp'] != null ? DateTime.tryParse(item['Timestamp']) : DateTime.now(),
              rawData: {
                'raw_forum': item['Forum'] ?? 'None Selected',
                'raw_membership': (item['Membership '] ?? item['Membership'] ?? '649').toString(),
              },
            );
          }).toList();
        } else {
          throw Exception("Sheets fetch non-200");
        }
      } catch (e) {
        debugPrint('Mobile Sheet fetch error, loading cache fallback: $e');
        sheetsList = _cachedExcelData.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return RegistrationQueueModel(
            id: 9000 + idx,
            name: (item['Name'] as String?)?.trim() ?? 'No Name',
            email: (item['Email'] as String?)?.trim() ?? '',
            phone: item['Phone'] != null ? item['Phone'].toString() : '',
            branch: item['Branch'] as String? ?? '',
            year: item['Year'] != null ? item['Year'].toString() : '',
            membershipType: '₹${item["Membership"] ?? "649"} (${item["Forum"] ?? "None"})',
            paymentStatus: 'paid',
            rollNumber: item['TransactionID'] != null ? item['TransactionID'].toString() : '',
            source: 'Google Sheet Excel',
            status: 'excel_intake',
            createdAt: item['Timestamp'] != null ? DateTime.tryParse(item['Timestamp']) : DateTime.now(),
            rawData: {
              'raw_forum': item['Forum'] ?? 'None Selected',
              'raw_membership': (item['Membership'] ?? '649').toString(),
            },
          );
        }).toList();
      }

      if (mounted) {
        setState(() {
          _grouped = {
            'Pending': list.where((r) => r.status == 'pending').toList(),
            'Payment': list.where((r) => r.status == 'payment_pending').toList(),
            'Approved': list.where((r) => r.status == 'approved').toList(),
            'Rejected': list.where((r) => r.status == 'rejected').toList(),
            'Excel Intake': sheetsList,
          };
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
      backgroundColor: _bg,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: _bg,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Registration Queue',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 26, fontWeight: FontWeight.bold, color: _cream)),
                    const SizedBox(height: 6),
                    Text(
                      '${_grouped['Pending']?.length ?? 0} pending review',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: _buildTabBar(),
            ),
          ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _terracotta))
            : RefreshIndicator(
                onRefresh: _loadQueue,
                color: _terracotta,
                backgroundColor: _surface,
                child: TabBarView(
                  controller: _tabController,
                  children: _tabs.map((t) => _buildList(_grouped[t] ?? [])).toList(),
                ),
              ),
      ),
    );
  }

  Widget _buildTabBar() {
    final counts = _tabs.map((t) => _grouped[t]?.length ?? 0).toList();

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: _bg.withValues(alpha: 0.8),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: _terracotta.withValues(alpha: 0.2),
              border: Border.all(color: _terracotta.withValues(alpha: 0.4)),
            ),
            labelColor: _terracotta,
            unselectedLabelColor: Colors.white38,
            labelStyle: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700),
            tabs: List.generate(
              _tabs.length,
              (i) => Tab(text: '${_tabs[i]} (${counts[i]})'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<RegistrationQueueModel> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, size: 64, color: Colors.white12),
            const SizedBox(height: 16),
            Text('Nothing here', style: GoogleFonts.inter(color: Colors.white24, fontSize: 16)),
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
}

// ── Registration Card ──────────────────────────────────────────────────────

class _RegistrationCard extends StatelessWidget {
  final RegistrationQueueModel registration;
  final VoidCallback onTap;

  static const _surface = Color(0xFF1E1E1E);
  static const _cream = Color(0xFFF4E9D7);

  const _RegistrationCard({required this.registration, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: registration.statusColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    registration.statusColor.withValues(alpha: 0.3),
                    registration.statusColor.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  registration.name.isNotEmpty ? registration.name[0].toUpperCase() : '?',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: registration.statusColor),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(registration.name,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 15, fontWeight: FontWeight.w700, color: _cream)),
                  Text(registration.email,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
                  if (registration.rollNumber != null)
                    Text('${registration.rollNumber} · ${registration.branch ?? ""}',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white24)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: registration.statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(registration.statusLabel,
                      style: GoogleFonts.inter(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: registration.statusColor)),
                ),
                const SizedBox(height: 4),
                Text(
                  registration.createdAt != null
                      ? '${registration.createdAt!.day}/${registration.createdAt!.month}'
                      : '',
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.white24),
                ),
              ],
            ),
          ],
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

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _sage = Color(0xFFB8C4A9);
  static const _teal = Color(0xFF6FA4AF);
  static const _surface = Color(0xFF1E1E1E);
  static const _surface2 = Color(0xFF242424);

  @override
  Widget build(BuildContext context) {
    final reg = widget.registration;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
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
                            fontSize: 22, fontWeight: FontWeight.bold, color: _cream)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: reg.statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: reg.statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(reg.statusLabel,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: reg.statusColor, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Details
              _detailRow(Icons.email_rounded, 'Email', reg.email),
              _detailRow(Icons.phone_rounded, 'Phone', reg.phone ?? '—'),
              _detailRow(Icons.badge_rounded, 'Roll Number', reg.rollNumber ?? '—'),
              _detailRow(Icons.school_rounded, 'Branch', reg.branch ?? '—'),
              _detailRow(Icons.calendar_today_rounded, 'Year', reg.year ?? '—'),
              _detailRow(Icons.card_membership_rounded, 'Membership', reg.membershipType),
              _detailRow(Icons.payments_rounded, 'Payment', reg.paymentStatus),
              _detailRow(Icons.source_rounded, 'Source', reg.source),
              const SizedBox(height: 24),
              // Action buttons
              if (reg.status == 'pending' || reg.status == 'payment_pending' || reg.status == 'excel_intake') ...[
                _isProcessing
                    ? const Center(child: CircularProgressIndicator(color: _terracotta))
                    : reg.status == 'excel_intake'
                        ? SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _handleApproveExcelIntake,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _sage,
                                foregroundColor: Colors.black87,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text('Import & Approve Member',
                                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                            ),
                          )
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
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _action('approved'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _sage,
                                        foregroundColor: Colors.black87,
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
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _action('payment_pending'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _terracotta,
                                    side: BorderSide(color: _terracotta.withValues(alpha: 0.5)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  icon: const Icon(Icons.schedule_rounded, size: 18),
                                  label: Text('Mark Payment Pending',
                                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                                ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 10),
          Text('$label:',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _handleApproveExcelIntake() async {
    final auth = context.read<AuthProvider>();
    setState(() => _isProcessing = true);
    try {
      final reg = widget.registration;
      final rawMembership = reg.rawData['raw_membership'] ?? '649';
      final rawForum = reg.rawData['raw_forum'] ?? 'None Selected';

      String plan = '1 Year';
      if (rawMembership == '1199') plan = '2 Year';
      else if (rawMembership == '1499') plan = '3 Year';

      String? forum;
      if (rawForum != 'None Selected' && rawForum != 'None') {
        forum = rawForum.split(' ')[0];
      }

      final response = await _supabase.functions.invoke('admin-create-user', body: {
        'name': reg.name,
        'email': reg.email,
        'role': 'member',
        'phone': reg.phone,
        'roll_number': reg.rollNumber,
        'branch': reg.branch,
        'membership_plan': plan,
        'forum': forum,
        'status': 'active',
      });

      if (response.status != 200 && response.status != 201) {
        throw Exception(response.data?['message'] ?? 'Failed to invoke admin-create-user Edge Function');
      }

      await _supabase.from('registration_queue').insert({
        'name': reg.name,
        'email': reg.email,
        'phone': reg.phone,
        'branch': reg.branch,
        'year': reg.year,
        'membership_type': reg.membershipType,
        'payment_status': 'paid',
        'roll_number': reg.rollNumber,
        'source': 'Google Sheet Excel',
        'status': 'approved',
        'reviewed_by': auth.authUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
        'created_at': reg.createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      });

      widget.onAction();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Member "${reg.name}" successfully imported and approved!'), backgroundColor: _sage),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approval failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _action(String status) async {
    final auth = context.read<AuthProvider>();
    setState(() => _isProcessing = true);
    try {
      await _supabase.from('registration_queue').update({
        'status': status,
        'reviewed_by': auth.authUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.registration.id);

      if (status == 'approved') {
        // Trigger membership generation via Edge Function (to be deployed)
        // For now, we'll note this is a placeholder for the Edge Function call
        debugPrint('TODO: Call generate-membership edge function for ${widget.registration.email}');
      }

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
