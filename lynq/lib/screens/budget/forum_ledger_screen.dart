import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';
import 'new_transaction_sheet.dart';

class ForumLedgerScreen extends StatefulWidget {
  final int forumId;
  final String forumName;

  const ForumLedgerScreen({super.key, required this.forumId, required this.forumName});

  @override
  State<ForumLedgerScreen> createState() => _ForumLedgerScreenState();
}

class _ForumLedgerScreenState extends State<ForumLedgerScreen> {
  List<Map<String, dynamic>> _ledgerEntries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadForumLedger();
  }

  Future<void> _loadForumLedger() async {
    try {
      final data = await Supabase.instance.client
          .from('financial_ledger')
          .select()
          .eq('execom_id', widget.forumId)
          .isFilter('event_id', null)
          .order('transaction_date', ascending: false);

      setState(() {
        _ledgerEntries = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading forum ledger: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showNewTransactionSheet(BuildContext context, bool isIncomeInitial) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NewTransactionSheet(
        isIncomeInitial: isIncomeInitial,
        myFolderIds: [widget.forumId],
        preselectedFolderId: widget.forumId,
      ),
    ).then((_) => _loadForumLedger());
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F111A) : const Color(0xFFF8FAF8);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text(
          '${widget.forumName} Ledger',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: textColor, fontSize: 18),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewTransactionSheet(context, false),
        backgroundColor: AppTheme.secondary,
        foregroundColor: AppTheme.darkGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ledgerEntries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('No ledger entries for this forum', style: GoogleFonts.inter(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _ledgerEntries.length,
                  itemBuilder: (context, i) => _buildLedgerItem(_ledgerEntries[i]),
                ),
    );
  }
}
