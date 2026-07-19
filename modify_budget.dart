import 'dart:io';

void main() {
  final file = File('lynq/lib/screens/budget/budget_overview_screen.dart');
  String content = file.readAsStringSync();

  // 1. Add state variable
  content = content.replaceFirst(
    '  List<Map<String, dynamic>> _ledgerEntries = []; // Detailed ledger data\n  String _myForumNames = \'\'; // Combined forum names for header',
    '  List<Map<String, dynamic>> _ledgerEntries = []; // Detailed ledger data\n  String _myForumNames = \'\'; // Combined forum names for header\n  List<Map<String, dynamic>> _adminForumAllocations = []; // For Tier 1 and 2 allocation feature',
  );

  // 2. Add loading logic for _adminForumAllocations
  final oldEventQuery = '''      // 7. Load Event Budgets
      var eventQuery = Supabase.instance.client.from('event_budgets').select();
      if (!canViewTotal && _myFolderIds.isNotEmpty) {
        eventQuery = eventQuery.inFilter('execom_id', _myFolderIds);
      }
      final eventBudgetData = await eventQuery.order('date', ascending: false);
      _eventBudgets = (eventBudgetData as List).map((e) => EventBudgetModel.fromJson(e)).toList();''';

  final newEventQuery = oldEventQuery + '''\n\n      // 8. Fetch Admin Forum Allocations (if Tier 1 or 2)
      if (canViewTotal) {
        final forumsResp = await Supabase.instance.client
            .from('folders')
            .select('id, name')
            .eq('is_forum', true)
            .inFilter('name', ['EXIS', 'BITS', 'TORQ', 'GENESIS', 'SWAS', 'exis', 'bits', 'torq', 'Genesis', 'SWAS', 'Genesis']); // Case insensitivity coverage
        
        final fbResp = await Supabase.instance.client.from('forum_budgets').select();
        
        List<Map<String, dynamic>> allocations = [];
        for (var f in (forumsResp as List)) {
          final n = f['name'].toString().toUpperCase();
          if (['EXIS', 'BITS', 'TORQ', 'GENESIS', 'SWAS'].contains(n)) {
            final fb = (fbResp as List).firstWhere((element) => element['execom_id'] == f['id'], orElse: () => null);
            allocations.add({
              'id': f['id'],
              'name': n,
              'allocated_amount': fb != null ? (fb['allocated_amount'] as num).toDouble() : 0.0,
            });
          }
        }
        _adminForumAllocations = allocations;
      }''';

  content = content.replaceFirst(oldEventQuery, newEventQuery);

  // 3. Fix calculation logic for forums
  final oldCalc = '''    final remaining = _forumAllocation - _totalSpent;
    final spentPercentage = _forumAllocation > 0 ? (_totalSpent / _forumAllocation) : 0;''';
  
  final newCalc = '''    final totalAvailableBudget = _forumAllocation + _totalApproved;
    final remaining = totalAvailableBudget - _totalSpent;
    final spentPercentage = totalAvailableBudget > 0 ? (_totalSpent / totalAvailableBudget) : 0;''';

  content = content.replaceFirst(oldCalc, newCalc);

  // 4. Update the summary mini card
  final oldMini = '''                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSummaryMini('Allocation', '₹\${_forumAllocation.toStringAsFixed(0)}', textSecondary!),
                    _buildSummaryMini('Spent', '₹\${_totalSpent.toStringAsFixed(0)}', Colors.redAccent),
                  ],
                ),''';

  final newMini = '''                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSummaryMini('Total Budget', '₹\${totalAvailableBudget.toStringAsFixed(0)}', textSecondary!),
                    _buildSummaryMini('Spent', '₹\${_totalSpent.toStringAsFixed(0)}', Colors.redAccent),
                  ],
                ),''';

  content = content.replaceFirst(oldMini, newMini);

  // 5. Add UI logic for the allocation feature in _buildDashboardTab
  final oldDashboardEnd = '''          const SizedBox(height: 32),
          
          const SizedBox(height: 48),
          const SizedBox(height: 48),
        ],
      ),
    );
  }''';

  final newDashboardEnd = '''          const SizedBox(height: 32),
          _buildForumAllocationsSection(context),
          const SizedBox(height: 48),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildForumAllocationsSection(BuildContext context) {
    if (_adminForumAllocations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Forum Budget Allocations', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Manage base budget limits for designated forums.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        ..._adminForumAllocations.map((forum) {
          final amt = forum['allocated_amount'] as double;
          return GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance, color: AppTheme.secondary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      forum['name'],
                      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '₹\${amt.toStringAsFixed(0)}',
                      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18, color: AppTheme.secondary),
                      onPressed: () => _showEditAllocationDialog(forum['id'], forum['name'], amt),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  void _showEditAllocationDialog(int folderId, String forumName, double currentAmt) {
    final controller = TextEditingController(text: currentAmt.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF161925) : Colors.white,
        title: Text('Edit \${forumName} Allocation', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update the base budget limit for \${forumName}.', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Allocation (₹)',
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
                try {
                  // Check if exists first
                  final existing = await Supabase.instance.client.from('forum_budgets').select().eq('execom_id', folderId);
                  if ((existing as List).isEmpty) {
                    await Supabase.instance.client.from('forum_budgets').insert({
                      'execom_id': folderId,
                      'allocated_amount': newLimit,
                      'start_date': DateTime.now().toIso8601String(),
                      'end_date': DateTime.now().add(const Duration(days: 365)).toIso8601String()
                    });
                  } else {
                    await Supabase.instance.client.from('forum_budgets').update({
                      'allocated_amount': newLimit,
                    }).eq('execom_id', folderId);
                  }
                  
                  _loadBudget();
                  if (mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('\$forumName budget updated successfully')));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: \$e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }''';

  content = content.replaceFirst(oldDashboardEnd, newDashboardEnd);

  file.writeAsStringSync(content);
  print('Modifications complete.');
}
