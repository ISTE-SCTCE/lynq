import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth_provider.dart';
import '../../core/permission_engine.dart';
import '../../core/theme.dart';
import '../../models/app_models.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/liquid_glass_nav_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' as io;

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';

class BudgetOverviewScreen extends StatefulWidget {
  final int? initialTab;
  const BudgetOverviewScreen({super.key, this.initialTab});

  @override
  State<BudgetOverviewScreen> createState() => _BudgetOverviewScreenState();
}

class _BudgetOverviewScreenState extends State<BudgetOverviewScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<BudgetRequestModel> _requests = [];
  bool _isLoading = true;
  double _totalApproved = 0;
  double _totalSpent = 0; // Cumulative Expense from ledger
  double _totalIncome = 0; // Cumulative Income from ledger
  double _totalPlanned = 0; // Pending requests amount
  double _forumAllocation = 0; // Allocation for current user's forum
  bool _isArchivedView = false;
  List<int> _myExecomIds = []; // Execoms the user belongs to
  List<Map<String, dynamic>> _allCategories = []; // All categories for setup
  List<EventBudgetModel> _eventBudgets = []; // Event specific budgets
  List<Map<String, dynamic>> _ledgerEntries = []; // Detailed ledger data

  RealtimeChannel? _ledgerChannel;

  @override
  void initState() {
    super.initState();
    final perms = context.read<AuthProvider>().permissions;
    final tabCount = (perms?.isAtLeastTier2 ?? false) ? 4 : 3;
    _tabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: (widget.initialTab != null && widget.initialTab! < tabCount) ? widget.initialTab! : 0,
    );
    _loadBudget();
    _setupRealtime();
  }

  void _setupRealtime() {
    _ledgerChannel = Supabase.instance.client.channel('public:financial_ledger');
    _ledgerChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'financial_ledger',
      callback: (payload) {
        if (mounted) _loadBudget();
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _ledgerChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBudget() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 1. Get user's folder memberships
      final membershipData = await Supabase.instance.client
          .from('execom_members')
          .select('execom_id')
          .eq('user_id', user.id);
      
      _myExecomIds = (membershipData as List).map((m) => m['execom_id'] as int).toList();

      // 2. Load requests
      final perms = context.read<AuthProvider>().permissions;
      var query = Supabase.instance.client.from('budget_requests').select();
      
      if (perms != null && !perms.isAtLeastTier2) {
        query = query.inFilter('execom_id', _myExecomIds);
      }

      final data = await query.order('created_at', ascending: false).range(0, 50);
      _requests = (data as List).map((e) => BudgetRequestModel.fromJson(e)).toList();
      
      // 3. Load Financial Ledger Data
      final canViewTotal = perms?.canViewTotalBudget ?? false;
      
      if (canViewTotal) {
        final ledgerData = await Supabase.instance.client
            .from('financial_ledger')
            .select()
            .order('transaction_date', ascending: false);
        
        _ledgerEntries = List<Map<String, dynamic>>.from(ledgerData);
        _totalIncome = 0;
        _totalSpent = 0;
        
        for (var entry in _ledgerEntries) {
          final amt = (entry['amount'] as num).toDouble();
          if (entry['type'] == 'Income') {
            _totalIncome += amt;
          } else {
            _totalSpent += amt;
          }
        }
      } else {
        // Scoped view - only see transactions from their execom
        final ledgerData = await Supabase.instance.client
            .from('financial_ledger')
            .select()
            .inFilter('execom_id', _myExecomIds)
            .order('transaction_date', ascending: false);
            
        _ledgerEntries = List<Map<String, dynamic>>.from(ledgerData);
        _totalIncome = 0;
        _totalSpent = 0;
        for (var entry in _ledgerEntries) {
          final amt = (entry['amount'] as num).toDouble();
          if (entry['type'] == 'Income') {
            _totalIncome += amt;
          } else {
            _totalSpent += amt;
          }
        }
      }

      // 4. Calculate Forum specific stats from requests
      _totalApproved = _requests
          .where((r) => r.status == 'approved')
          .fold(0, (sum, r) => sum + r.amount);
      
      _totalPlanned = _requests
          .where((r) => r.status == 'pending')
          .fold(0, (sum, r) => sum + r.amount);

      // 5. Fetch Forum Allocation (if scoped view)
      if (!canViewTotal && _myExecomIds.isNotEmpty) {
        final allocationData = await Supabase.instance.client
            .from('execom_budgets')
            .select('allocated_amount')
            .filter('execom_id', 'in', '(${_myExecomIds.join(',')})');
        
        double totalAllocation = 0;
        if (allocationData != null) {
          for (var row in (allocationData as List)) {
            totalAllocation += (row['allocated_amount'] as num).toDouble();
          }
        }
        _forumAllocation = totalAllocation;
      }

      // 6. Load all categories for setup
      final catData = await Supabase.instance.client
          .from('budget_categories')
          .select()
          .order('name');
      _allCategories = List<Map<String, dynamic>>.from(catData);

      // 7. Load Event Budgets
      final eventBudgetData = await Supabase.instance.client
          .from('event_budgets')
          .select()
          .order('date', ascending: false);
      _eventBudgets = (eventBudgetData as List).map((e) => EventBudgetModel.fromJson(e)).toList();

    } catch (e) {
      debugPrint('Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _reviewRequest(int id, String status) async {
    try {
      await Supabase.instance.client.from('budget_requests').update({
        'status': status,
        'reviewed_by': Supabase.instance.client.auth.currentUser?.id,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      _loadBudget();
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _showEditEventBudgetDialog(EventBudgetModel eb) {
    final controller = TextEditingController(text: eb.budgetLimit.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF161925) : Colors.white,
        title: Text('Edit Budget Limit', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(eb.eventName, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New Limit (₹)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newLimit = double.tryParse(controller.text);
              if (newLimit != null) {
                await Supabase.instance.client
                  .from('event_budgets')
                  .update({'budget_limit': newLimit})
                  .eq('id', eb.id);
                _loadBudget();
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEventBudget(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event Budget'),
        content: const Text('Are you sure you want to delete this event budget? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Delete', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('event_budgets').delete().eq('id', id);
      setState(() {
        _eventBudgets.removeWhere((e) => e.id == id);
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event budget deleted')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }



  void _showExportDialog() {
    DateTime? startDate;
    DateTime? endDate;
    String? selectedCategory;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Export Report'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Start Date'),
                    subtitle: Text(startDate?.toString().split(' ')[0] ?? 'Any'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (picked != null) setState(() => startDate = picked);
                    },
                  ),
                  ListTile(
                    title: const Text('End Date'),
                    subtitle: Text(endDate?.toString().split(' ')[0] ?? 'Any'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (picked != null) setState(() => endDate = picked);
                    },
                  ),
                  DropdownButtonFormField<String?>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Categories')),
                      ..._allCategories.map((c) => DropdownMenuItem(value: c['name'] as String, child: Text(c['name']))),
                    ],
                    onChanged: (v) => setState(() => selectedCategory = v),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _exportPdf(startDate, endDate, selectedCategory);
                  },
                  child: const Text('PDF'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _exportCsv(startDate, endDate, selectedCategory);
                  },
                  child: const Text('CSV'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportPdf(DateTime? start, DateTime? end, String? category) async {
    final pdf = pw.Document();

    final filteredEntries = _ledgerEntries.where((e) {
      final date = DateTime.parse(e['transaction_date'].toString());
      if (start != null && date.isBefore(start)) return false;
      if (end != null && date.isAfter(end.add(const Duration(days: 1)))) return false;
      if (category != null && e['category'] != category) return false;
      return true;
    }).toList();

    double totalIncome = filteredEntries.where((e) => e['type'] == 'Income').fold(0.0, (sum, e) => sum + (e['amount'] as num).toDouble());
    double totalExpense = filteredEntries.where((e) => e['type'] != 'Income').fold(0.0, (sum, e) => sum + (e['amount'] as num).toDouble());
    double remainingBalance = totalIncome - totalExpense;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Execom Financial Statement', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${DateTime.now().toLocal().toString().split(' ')[0]}'),
                ],
              )
            ),
            pw.SizedBox(height: 20),
            if (start != null || end != null) pw.Text('Filter: ${start?.toString().split(' ')[0] ?? 'Any'} to ${end?.toString().split(' ')[0] ?? 'Any'}'),
            if (category != null) pw.Text('Category: $category'),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Income: INR ${totalIncome.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 16)),
                pw.Text('Total Expense: INR ${totalExpense.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 16)),
              ]
            ),
            pw.SizedBox(height: 10),
            pw.Text('Net Balance: INR ${remainingBalance.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 30),
            pw.Text('Transaction History', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Category', 'Source', 'Type', 'Notes', 'Amount'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
                5: pw.Alignment.centerRight,
              },
              data: filteredEntries.map((e) => [
                (e['transaction_date'] as String).split('T')[0],
                e['category'] ?? 'N/A',
                e['source'] ?? 'N/A',
                e['type'],
                e['notes'] ?? e['description'] ?? 'N/A',
                'INR ${(e['amount'] as num).toDouble().toStringAsFixed(2)}',
              ]).toList(),
            ),
            pw.SizedBox(height: 30),
            pw.Text('End of Statement', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
          ];
        }
      )
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Execom_Financial_Statement.pdf');
  }

  Future<void> _exportCsv(DateTime? start, DateTime? end, String? category) async {
    final filteredEntries = _ledgerEntries.where((e) {
      final date = DateTime.parse(e['transaction_date'].toString());
      if (start != null && date.isBefore(start)) return false;
      if (end != null && date.isAfter(end.add(const Duration(days: 1)))) return false;
      if (category != null && e['category'] != category) return false;
      return true;
    }).toList();

    String csv = "Date,Category,Source,Type,Notes,Attachment,Amount\n";
    for (var e in filteredEntries) {
      final d = (e['transaction_date'] as String).split('T')[0];
      final c = e['category'] ?? 'N/A';
      final s = e['source'] ?? 'N/A';
      final t = e['type'];
      final n = (e['notes'] ?? e['description'] ?? 'N/A').toString().replaceAll(',', ' ').replaceAll('\n', ' ');
      final att = e['attachment_url'] ?? 'N/A';
      final a = (e['amount'] as num).toDouble().toStringAsFixed(2);
      csv += "$d,$c,$s,$t,$n,$att,$a\n";
    }
    
    // Convert string to bytes and share
    final bytes = Uint8List.fromList(csv.codeUnits);
    await Printing.sharePdf(bytes: bytes, filename: 'Financial_Statement.csv');
  }

  // Main Entry Point for UI
  @override
  Widget build(BuildContext context) {
    final perms = context.watch<AuthProvider>().permissions;
    if (perms == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F111A) : const Color(0xFFF8FAF8);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          perms.isAtLeastTier2 ? 'Budget Management' : 'My Forum Budget', 
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: textColor, fontSize: 22)
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download_outlined, color: textColor),
            onPressed: _showExportDialog,
          ),
          if (perms.isAtLeastTier2)
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: textColor),
              onPressed: () => _showNewTransactionSheet(context, true),
            ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppTheme.secondary,
          unselectedLabelColor: isDark ? Colors.white70 : Colors.grey[600],
          indicatorColor: AppTheme.secondary,
          indicatorWeight: 3,
          tabs: perms.isAtLeastTier2 
            ? const [
                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
                Tab(icon: Icon(Icons.people_outline), text: 'Requests'),
                Tab(icon: Icon(Icons.history), text: 'Ledger'),
                Tab(icon: Icon(Icons.calendar_today_outlined), text: 'Events'),
              ]
            : const [
                Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Summary'),
                Tab(icon: Icon(Icons.people_outline), text: 'Requests'),
                Tab(icon: Icon(Icons.calendar_today_outlined), text: 'Events'),
              ],
        ),
      ),
      floatingActionButton: _buildFAB(perms),
      bottomNavigationBar: LiquidGlassNavBar(
        selectedIndex: 1,
        onItemSelected: (i) {
          if (i == 1) return;
          switch (i) {
            case 0: context.go('/home'); break;
            case 2: context.push('/chat'); break;
            case 3: context.push('/settings'); break;
          }
        },
        items: [
          LiquidNavItem(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view, label: 'Home'),
          LiquidNavItem(
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet,
            label: 'Budget',
          ),
          LiquidNavItem(icon: Icons.chat_bubble_outline, selectedIcon: Icons.chat_bubble, label: 'Chat'),
          LiquidNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
        ],
      ),
      extendBody: true,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: perms.isAtLeastTier2
                  ? [
                      _buildDashboardTab(context, perms),
                      _buildForumsTab(context, perms),
                      _buildHistoryTab(perms),
                      _buildEventsTab(context),
                    ]
                  : [
                      _buildForumSummaryTab(context, perms),
                      _buildForumsTab(context, perms),
                      _buildEventsTab(context),
                    ],
            ),
    );
  }

  void _showNewTransactionSheet(BuildContext context, bool isIncomeInitial) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NewTransactionSheet(
        isIncomeInitial: isIncomeInitial,
        myExecomIds: _myExecomIds,
      ),
    ).then((_) => _loadBudget());
  }

  Widget? _buildFAB(PermissionEngine perms) {
    if (perms.isAtLeastTier2) {
      return FloatingActionButton(
        onPressed: () => _showNewTransactionSheet(context, false),
        backgroundColor: AppTheme.secondary,
        foregroundColor: AppTheme.darkGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  Widget _buildForumSummaryTab(BuildContext context, PermissionEngine perms) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600];
    final cardBg = isDark ? const Color(0xFF1A2035) : Colors.white;

    final remaining = _forumAllocation - _totalSpent;
    final spentPercentage = _forumAllocation > 0 ? (_totalSpent / _forumAllocation) : 0;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('FORUM BUDGET OVERVIEW', 
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: textSecondary, letterSpacing: 1.2)),
                const SizedBox(height: 24),
                
                // Allocation vs Spent
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSummaryMini('Allocation', '₹${_forumAllocation.toStringAsFixed(0)}', textSecondary!),
                    _buildSummaryMini('Spent', '₹${_totalSpent.toStringAsFixed(0)}', Colors.redAccent),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Progress Bar
                Stack(
                  children: [
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: spentPercentage.clamp(0.0, 1.0).toDouble(),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppTheme.darkGreen, Colors.greenAccent]),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(color: AppTheme.darkGreen.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Main Balance
                Text('REMAINING BALANCE', 
                  style: GoogleFonts.inter(fontSize: 11, color: textSecondary, letterSpacing: 1)),
                const SizedBox(height: 8),
                Text('₹${remaining.toStringAsFixed(0)}', 
                  style: GoogleFonts.spaceGrotesk(fontSize: 42, fontWeight: FontWeight.bold, color: remaining >= 0 ? AppTheme.darkGreen : Colors.redAccent)),
                
                const SizedBox(height: 24),
                Divider(color: isDark ? Colors.white10 : Colors.grey[200]),
                const SizedBox(height: 16),
                
                // Request Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatMini('Approved', '₹${_totalApproved.toStringAsFixed(0)}', Colors.green),
                    _buildStatMini('Pending', '₹${_totalPlanned.toStringAsFixed(0)}', Colors.amber),
                  ],
                ),

              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_requests.isEmpty)
            _buildEmptyState('No budget requests yet. Tap the button above to make one!')
          else
            ..._requests.take(5).map((req) => _buildBudgetCard(req, perms)),
        ],
      ),
    );
  }

  Widget _buildSummaryMini(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }


  Widget _buildForumsTab(BuildContext context, PermissionEngine perms) {
    final pendingRequests = _requests.where((r) => r.status == 'pending').toList();
    
    if (pendingRequests.isEmpty) {
      return _buildEmptyState('No pending forum requests');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pendingRequests.length,
      itemBuilder: (context, i) {
        final req = pendingRequests[i];
        return _buildBudgetCard(req, perms);
      },
    );
  }

  Widget _buildEventsTab(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_eventBudgets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No event budgets found', style: GoogleFonts.inter(color: Colors.grey)),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _eventBudgets.length,
      itemBuilder: (context, index) {
        final eb = _eventBudgets[index];
        final progress = eb.budgetLimit > 0 ? (eb.actualSpent / eb.budgetLimit).clamp(0.0, 1.0) : 0.0;
        final isOverBudget = eb.actualSpent > eb.budgetLimit;

        return GlassCard(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eb.eventName,
                            style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                          ),
                          if (eb.date != null)
                            Text(
                              eb.date!.toString().split(' ').first,
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                    if (isOverBudget)
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    if (context.read<AuthProvider>().permissions?.canManageBudget ?? false)
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit_note, size: 20, color: textColor.withValues(alpha: 0.5)),
                            onPressed: () => _showEditEventBudgetDialog(eb),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                            onPressed: () => _deleteEventBudget(eb.id),
                          ),
                        ]
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Budget: ₹${eb.budgetLimit.toStringAsFixed(0)}', style: GoogleFonts.inter(color: textColor.withValues(alpha: 0.7))),
                    Text('Spent: ₹${eb.actualSpent.toStringAsFixed(0)}', 
                      style: GoogleFonts.inter(
                        color: isOverBudget ? Colors.redAccent : textColor.withValues(alpha: 0.7),
                        fontWeight: isOverBudget ? FontWeight.bold : FontWeight.normal,
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isOverBudget ? Colors.redAccent : progress > 0.8 ? Colors.orange : AppTheme.darkGreen,
                    ),
                  ),
                ),
                if (isOverBudget) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Over budget by ₹${(eb.actualSpent - eb.budgetLimit).toStringAsFixed(0)}',
                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }



  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 48, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.inter(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context, PermissionEngine perms) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('INCOME', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white54 : Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text('₹${_totalIncome.toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('EXPENSE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white54 : Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text('₹${_totalSpent.toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.secondary, 
                        width: 12,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _totalIncome == 0 ? '0%' : '${(((_totalIncome - _totalSpent) / _totalIncome) * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('REMAINING BALANCE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white54 : Colors.grey[600], letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Text('₹${(_totalIncome - _totalSpent).toStringAsFixed(0)}', style: GoogleFonts.spaceGrotesk(fontSize: 40, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatMini('Current Bal.', '₹${(_totalIncome - _totalSpent).toStringAsFixed(0)}', AppTheme.secondary),
                    const SizedBox(width: 24),
                    _buildStatMini('Total Funds', '₹${_totalIncome.toStringAsFixed(0)}', isDark ? Colors.white70 : Colors.black87),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          Text('Financial Trends', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Cumulative Balance vs Income & Expense', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          _buildUnifiedFinancialChart(),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Transactions', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => _tabController.animateTo(3), 
                child: Text('View All', style: GoogleFonts.inter(color: const Color(0xFF6C63FF))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_ledgerEntries.isEmpty)
            _buildEmptyState('No transactions yet')
          else
            ..._ledgerEntries.take(5).map((e) => _buildLedgerItem(e)),
          
          const SizedBox(height: 32),
          
          const SizedBox(height: 48),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildStatMini(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
      ],
    );
  }





  Widget _buildHistoryTab(PermissionEngine? perms) {
    if (_ledgerEntries.isEmpty) {
      return _buildEmptyState('No transaction logs found');
    }
    return RefreshIndicator(
      onRefresh: _loadBudget,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _ledgerEntries.length,
        itemBuilder: (context, i) {
          final entry = _ledgerEntries[i];
          return _buildLedgerItem(entry);
        },
      ),
    );
  }

  Widget _buildBudgetCard(BudgetRequestModel req, PermissionEngine? perms) {
    final statusColor = _statusColor(req.status);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.receipt_long, color: statusColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${req.amount.toStringAsFixed(0)}',
                        style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Execom #${req.execomId}',
                        style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    req.status.toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
            if (req.proposalUrl != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final url = Uri.tryParse(req.proposalUrl!);
                  if (url != null && await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open proposal link')),
                      );
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_file, size: 14, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text('View Proposal', style: GoogleFonts.inter(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
            if (req.reason != null) ...[

              const SizedBox(height: 12),
              Text(
                req.reason!,
                style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey[800]),
              ),
            ],
            if (req.status == 'pending' && (perms?.canApproveBudget ?? false)) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reviewRequest(req.id, 'rejected'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Reject', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _reviewRequest(req.id, 'approved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Approve', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }


  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.redAccent;
      case 'pending': return Colors.orange;
      case 'archived': return Colors.grey;
      default: return Colors.blue;
    }
  }

  Widget _buildLedgerItem(Map<String, dynamic> entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIncome = entry['type'] == 'Income';
    final amt = (entry['amount'] as num).toDouble();
    final date = DateTime.parse(entry['transaction_date']);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isIncome ? Colors.green : Colors.redAccent).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                color: isIncome ? Colors.green : Colors.redAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry['source'] ?? (isIncome ? 'Income' : 'Expense'),
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    '${entry['category'] ?? 'General'} • ${date.day}/${date.month}/${date.year}',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Text(
              '${isIncome ? '+' : '-'}₹${amt.toStringAsFixed(0)}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isIncome ? Colors.green : Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Removed duplicate _downloadPdfReport and _showAddCategoryDialog methods

  void _showEditCategoryDialog(Map<String, dynamic> cat) {
    final nameController = TextEditingController(text: cat['name']);
    String type = cat['type'];
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit Category', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Category Name'),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: type,
                isExpanded: true,
                items: ['Income', 'Expense'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => type = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  await Supabase.instance.client.from('budget_categories').update({
                    'name': nameController.text.trim(),
                    'type': type,
                  }).eq('id', cat['id']);
                  _loadBudget();
                  if (context.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCategory(int id) async {
    try {
      await Supabase.instance.client.from('budget_categories').delete().eq('id', id);
      _loadBudget();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }


  Widget _buildUnifiedFinancialChart() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Group last 10 days of data for a better trend view
    final Map<String, double> incomeMap = {};
    final Map<String, double> expenseMap = {};
    final List<String> last10Days = [];
    
    for (int i = 9; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i)).toIso8601String().split('T')[0];
      last10Days.add(date);
      incomeMap[date] = 0;
      expenseMap[date] = 0;
    }

    for (var entry in _ledgerEntries) {
      final date = (entry['transaction_date'] as String).split('T')[0];
      if (last10Days.contains(date)) {
        final amt = (entry['amount'] as num).toDouble();
        if (entry['type'] == 'Income') {
          incomeMap[date] = (incomeMap[date] ?? 0) + amt;
        } else {
          expenseMap[date] = (expenseMap[date] ?? 0) + amt;
        }
      }
    }

    double runningBalance = 0;
    List<FlSpot> balanceSpots = [];
    List<FlSpot> incomeSpots = [];
    List<FlSpot> expenseSpots = [];

    for (int i = 0; i < 10; i++) {
      final date = last10Days[i];
      final inc = incomeMap[date]!;
      final exp = expenseMap[date]!;
      runningBalance += (inc - exp);
      
      balanceSpots.add(FlSpot(i.toDouble(), runningBalance));
      incomeSpots.add(FlSpot(i.toDouble(), inc));
      expenseSpots.add(FlSpot(i.toDouble(), exp));
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 2,
                      getTitlesWidget: (value, meta) {
                        if (value < 0 || value >= 10) return const SizedBox();
                        final date = last10Days[value.toInt()];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(date.split('-').last, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: balanceSpots,
                    isCurved: true,
                    color: AppTheme.secondary,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: AppTheme.secondary.withValues(alpha: 0.1)),
                  ),
                  LineChartBarData(
                    spots: incomeSpots,
                    isCurved: true,
                    color: Colors.greenAccent,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: expenseSpots,
                    isCurved: true,
                    color: Colors.redAccent,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _chartLegendTool('Balance', AppTheme.secondary),
              const SizedBox(width: 16),
              _chartLegendTool('Income', Colors.greenAccent),
              const SizedBox(width: 16),
              _chartLegendTool('Expense', Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartLegendTool(String label, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
      ],
    );
  }



  // Removed redundant _buildBudgetChart
}

class _NewTransactionSheet extends StatefulWidget {
  final bool isIncomeInitial;
  final List<int> myExecomIds;
  const _NewTransactionSheet({required this.isIncomeInitial, required this.myExecomIds});

  @override
  State<_NewTransactionSheet> createState() => _NewTransactionSheetState();
}

class _NewTransactionSheetState extends State<_NewTransactionSheet> {
  late bool isIncome;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String _category = 'Category';
  bool _isLoading = false;
  List<String> _categories = [];
  List<EventBudgetModel> _events = [];
  int? _selectedEventId;
  PlatformFile? _pickedFile;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png', 'jpeg'],
      );

      if (result != null && mounted) {
        setState(() => _pickedFile = result.files.first);
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    isIncome = widget.isIncomeInitial;
    _loadCategories();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final data = await Supabase.instance.client
          .from('event_budgets')
          .select()
          .order('date', ascending: false);
      
      if (mounted) {
        setState(() {
          _events = (data as List).map((e) => EventBudgetModel.fromJson(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading events: $e');
    }
  }

  Future<void> _loadCategories() async {
    try {
      final data = await Supabase.instance.client
          .from('budget_categories')
          .select('name')
          .eq('type', isIncome ? 'Income' : 'Expense');
      
      if (mounted) {
        setState(() {
          _categories = (data as List).map((e) => e['name'] as String).toList();
          // Ensure default category is valid or reset if not in list
          if (!_categories.contains(_category) && _category != 'Category') {
            _category = 'Category';
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  Future<void> _confirmTransaction() async {
    if (_amountController.text.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;

      String? attachmentUrl;
      if (_pickedFile != null) {
        final fileBytes = _pickedFile!.bytes;
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_pickedFile!.name}';
        final path = 'ledger/$fileName';

        if (fileBytes != null) {
          await Supabase.instance.client.storage
              .from('ledger_attachments')
              .uploadBinary(path, fileBytes);
        } else if (_pickedFile!.path != null) {
          final file = io.File(_pickedFile!.path!);
          await Supabase.instance.client.storage
              .from('ledger_attachments')
              .upload(path, file);
        }

        attachmentUrl = Supabase.instance.client.storage
            .from('ledger_attachments')
            .getPublicUrl(path);
      }

      await Supabase.instance.client.from('financial_ledger').insert({
        'type': isIncome ? 'Income' : 'Expense',
        'amount': double.parse(_amountController.text),
        'category': _category == 'Category' ? (isIncome ? 'Sponsorship' : 'Miscellaneous') : _category,
        'source': _sourceController.text.trim(),
        'description': _notesController.text.trim(),
        'notes': _notesController.text.trim(),
        'created_by': user?.id,
        'transaction_date': DateTime.now().toIso8601String(),
        'event_id': !isIncome ? _selectedEventId : null,
        'execom_id': widget.myExecomIds.isNotEmpty ? widget.myExecomIds.first : null,
        'attachment_url': attachmentUrl,
      });
      
      if (_selectedEventId != null && !isIncome) {
        // Update actual_spent in event_budgets
        final event = _events.firstWhere((e) => e.id == _selectedEventId);
        final newSpent = event.actualSpent + double.parse(_amountController.text);
        await Supabase.instance.client
            .from('event_budgets')
            .update({'actual_spent': newSpent})
            .eq('id', _selectedEventId!);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Transaction error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Removed previous initState redundant block

  @override
  void dispose() {
    _amountController.dispose();
    _sourceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF161925) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isIncome ? 'New Income' : 'New Expense',
                    style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Segmented Control
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F111A) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            isIncome = true;
                            _loadCategories();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isIncome ? AppTheme.darkGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Income',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color: isIncome ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            isIncome = false;
                            _loadCategories();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !isIncome ? Colors.redAccent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Expense',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color: !isIncome ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Text(
                'AMOUNT (₹)',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
              ),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold, color: textColor),
                decoration: InputDecoration(
                  hintText: '0.00',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.grey[300]),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'CATEGORY',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: bgColor,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (ctx) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Select Category', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 16),
                          if (_categories.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Text('No categories found. Add one in Setup.', style: GoogleFonts.inter(color: textColor)),
                            ),
                          ..._categories.map((c) => ListTile(
                            title: Text(c, style: GoogleFonts.inter(color: textColor)),
                            onTap: () {
                              setState(() => _category = c);
                              Navigator.pop(ctx);
                            },
                          )),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_category, style: GoogleFonts.inter(color: _category == 'Category' ? Colors.grey : textColor)),
                      const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),

              if (!isIncome) ...[
                Text(
                  'LINK TO EVENT (OPTIONAL)',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: bgColor,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (ctx) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Select Event', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                            const SizedBox(height: 16),
                            if (_events.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Text('No active events found', style: GoogleFonts.inter(color: textColor)),
                              ),
                            ..._events.map((e) => ListTile(
                              title: Text(e.eventName, style: GoogleFonts.inter(color: textColor)),
                              subtitle: Text('Budget: ₹${e.budgetLimit.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                              onTap: () {
                                setState(() => _selectedEventId = e.id);
                                Navigator.pop(ctx);
                              },
                              trailing: _selectedEventId == e.id 
                                  ? Icon(Icons.check_circle, color: AppTheme.darkGreen)
                                  : null,
                            )),
                            ListTile(
                              title: Text('None', style: GoogleFonts.inter(color: Colors.redAccent)),
                              onTap: () {
                                setState(() => _selectedEventId = null);
                                Navigator.pop(ctx);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedEventId == null 
                              ? 'Select Event' 
                              : _events.firstWhere((e) => e.id == _selectedEventId).eventName,
                          style: GoogleFonts.inter(color: _selectedEventId == null ? Colors.grey : textColor),
                        ),
                        const Icon(Icons.event, size: 20, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              
              Text(
                'SOURCE / VENDOR',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
              ),
              TextField(
                controller: _sourceController,
                style: GoogleFonts.inter(color: textColor),
                decoration: InputDecoration(
                  hintText: isIncome ? 'e.g. Sponsorship' : 'e.g. Amazon',
                  hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.grey[400]),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!)),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'NOTES',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
              ),
              TextField(
                controller: _notesController,
                style: GoogleFonts.inter(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Additional details...',
                  hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.grey[400]),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!)),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'ATTACHMENT (OPTIONAL)',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickFile,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _pickedFile != null ? Icons.description : Icons.upload_file,
                        color: _pickedFile != null ? AppTheme.secondary : (isDark ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _pickedFile?.name ?? 'Select document / image receipt',
                          style: GoogleFonts.inter(
                            color: _pickedFile != null ? textColor : (isDark ? Colors.white54 : Colors.black45),
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_pickedFile != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
                          onPressed: () => setState(() => _pickedFile = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _confirmTransaction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isIncome ? AppTheme.darkGreen : Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Confirm Transaction', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
