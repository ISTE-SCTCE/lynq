import 'dart:io';

void main() {
  final file = File('lynq/lib/screens/budget/budget_overview_screen.dart');
  final lines = file.readAsLinesSync();
  final out = <String>[];

  bool insertedAdminAllocations = false;
  bool insertedQuery = false;
  bool insertedCalc = false;
  bool insertedSummary = false;
  bool insertedDashboard = false;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (!insertedAdminAllocations && line.contains("String _myForumNames = '';")) {
      out.add(line);
      out.add("  List<Map<String, dynamic>> _adminForumAllocations = []; // For Tier 1 and 2 allocation feature");
      insertedAdminAllocations = true;
      continue;
    }

    if (!insertedQuery && line.contains("// 7. Load Event Budgets")) {
      out.add(line);
      out.add(lines[i+1]);
      out.add(lines[i+2]);
      out.add(lines[i+3]);
      out.add(lines[i+4]);
      out.add(lines[i+5]);
      out.add(lines[i+6]);
      
      out.add("""
      // 8. Fetch Admin Forum Allocations (if Tier 1 or 2)
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
      }""");
      i += 6;
      insertedQuery = true;
      continue;
    }

    if (!insertedCalc && line.contains("final remaining = _forumAllocation - _totalSpent;")) {
      out.add("    final totalAvailableBudget = _forumAllocation + _totalApproved;");
      out.add("    final remaining = totalAvailableBudget - _totalSpent;");
      out.add("    final spentPercentage = totalAvailableBudget > 0 ? (_totalSpent / totalAvailableBudget) : 0;");
      i += 1; // skip next line (spentPercentage = ...)
      insertedCalc = true;
      continue;
    }

    if (!insertedSummary && line.contains("_buildSummaryMini('Allocation',")) {
      out.add("                    _buildSummaryMini('Total Budget', '₹\${totalAvailableBudget.toStringAsFixed(0)}', textSecondary!),");
      insertedSummary = true;
      continue;
    }

    if (!insertedDashboard && line.contains("const SizedBox(height: 48);") && lines[i-1].contains("const SizedBox(height: 48);")) {
      out.add("          _buildForumAllocationsSection(context),");
      out.add(line);
      insertedDashboard = true;
      continue;
    }

    out.add(line);
  }

  // Insert new methods at the end of _BudgetOverviewScreenState class
  final newMethods = """
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
                      decoration: const BoxDecoration(
                        color: Colors.white, // White background as requested
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
        title: Text('Edit \$forumName Allocation', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update the base budget limit for \$forumName.', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey)),
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
  }
""";

  // In the 1854-line file, _BudgetOverviewScreenState ends around line 1250, right before "class NewTransactionSheet extends StatefulWidget"
  for (int i = 0; i < out.length; i++) {
    if (out[i].contains("class NewTransactionSheet extends StatefulWidget")) {
      // Find the closing brace of the previous class
      for (int j = i - 1; j >= 0; j--) {
        if (out[j].trim() == '}') {
          out.insert(j, newMethods);
          break;
        }
      }
      break;
    }
  }

  // Join lines carefully to avoid single line formatting
  String finalString = '';
  for(var line in out) {
      finalString += line + '\\n';
  }

  file.writeAsStringSync(finalString);
  print('Modifications complete. Flags: \$insertedAdminAllocations \$insertedQuery \$insertedCalc \$insertedSummary \$insertedDashboard');
}
