import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme.dart';
import '../../models/app_models.dart';

class NewTransactionSheet extends StatefulWidget {
  final bool isIncomeInitial;
  final List<int> myFolderIds;
  final int? preselectedFolderId;
  const NewTransactionSheet({super.key, required this.isIncomeInitial, required this.myFolderIds, this.preselectedFolderId});

  @override
  State<NewTransactionSheet> createState() => NewTransactionSheetState();
}

class NewTransactionSheetState extends State<NewTransactionSheet> {
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
        'execom_id': widget.preselectedFolderId ?? (widget.myFolderIds.isNotEmpty ? widget.myFolderIds.first : null),
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
