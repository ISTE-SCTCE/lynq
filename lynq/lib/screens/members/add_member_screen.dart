import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/primary_button.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'dart:io';
import '../../core/auth_provider.dart';

class AddMemberScreen extends StatefulWidget {
  const AddMemberScreen({super.key});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _postCtrl = TextEditingController();
  
  String _role = 'member';
  String _plan = '1 Year';
  String? _selectedForum;
  DateTime _membershipDate = DateTime.now();
  DateTime? _expiryDate;
  
  bool _isLoading = false;
  String _bulkStatus = '';
  List<Map<String, dynamic>> _bulkData = [];
  bool _enableSwasForum = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _expiryDate = DateTime.now().add(const Duration(days: 365));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _rollCtrl.dispose();
    _branchCtrl.dispose();
    _postCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isMembershipDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isMembershipDate ? _membershipDate : (_expiryDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.secondary,
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1E1E1E),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isMembershipDate) {
          _membershipDate = picked;
        } else {
          _expiryDate = picked;
        }
      });
    }
  }

  Future<void> _addMember() async {
    if (!_formKey.currentState!.validate()) return;
    
    final currentUser = context.read<AuthProvider>().currentUser;
    if (currentUser == null) return;

    final targetRole = AppRole.fromString(_role);
    if (targetRole >= AppRole.forumExeccom) {
      final currentAppRole = AppRole.fromString(currentUser.role);
      if (currentAppRole < AppRole.viceChairman) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only Chairman/Vice Chairman can promote to Execcom+'), backgroundColor: Colors.red),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'admin-create-user',
        body: {
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'role': _role,
          'post': _postCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'roll_number': _rollCtrl.text.trim(),
          'branch': _branchCtrl.text.trim(),
          'membership_plan': _plan,
          'membership_date': _membershipDate.toIso8601String().split('T')[0],
          'forum': _selectedForum,
          'expiry_date': _expiryDate?.toIso8601String().split('T')[0],
        },
      );

      if (response.status != 200) throw response.data['error'] ?? 'Failed to create user';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member added successfully! Default pass: isteISTE2026'), 
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          )
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, // Use FileType.any to avoid strict OS mime-type filtering which often fails for Excel
      withData: true, 
    );
    
    if (result != null) {
      final file = result.files.single;
      final ext = file.extension?.toLowerCase() ?? file.name.split('.').last.toLowerCase();
      
      if (ext != 'xlsx' && ext != 'xls' && ext != 'csv') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a valid Excel or CSV file'), backgroundColor: Colors.red)
        );
        return;
      }
      try {
        final bytes = result.files.single.bytes;
        final xl.Excel excel;
        
        if (bytes != null) {
          excel = xl.Excel.decodeBytes(bytes);
        } else if (result.files.single.path != null) {
          final file = File(result.files.single.path!);
          excel = xl.Excel.decodeBytes(file.readAsBytesSync());
        } else {
          throw 'Could not read file data';
        }
        
        List<Map<String, dynamic>> data = [];
        for (var table in excel.tables.keys) {
          final sheet = excel.tables[table]!;
          if (sheet.maxRows <= 1) continue;
          
          // Improved header normalization: lowercase, trim, remove internal spaces/underscores for matching
          final headers = sheet.rows[0].map((e) {
            String val = e?.value?.toString() ?? '';
            return val.toLowerCase().trim().replaceAll(' ', '').replaceAll('_', '');
          }).toList();

          for (int i = 1; i < sheet.maxRows; i++) {
            final row = sheet.rows[i];
            Map<String, dynamic> item = {};
            for (int j = 0; j < headers.length; j++) {
              if (j < row.length) {
                final val = row[j]?.value;
                // Add BOTH normalized and original-ish keys to be safe
                item[headers[j]] = val?.toString() ?? '';
              }
            }
            if (item.values.any((v) => v.toString().isNotEmpty)) {
              data.add(item);
            }
          }
        }
        setState(() { 
          _bulkData = data; 
          _bulkStatus = 'Ready to import ${data.length} members'; 
        });
      } catch (e) {
        debugPrint('Excel Parse Error: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to parse Excel: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _processBulk() async {
    if (_bulkData.isEmpty) return;
    setState(() => _isLoading = true);
    int success = 0, failed = 0;
    
    for (var m in _bulkData) {
      try {
        final name = _getVal(m, ['name', 'fullname', 'membername', 'studentname']);
        final email = _getVal(m, ['email', 'emailaddress', 'mail', 'id']);
        final role = _getVal(m, ['role', 'type', 'usertype']) ?? 'member';
        final post = _getVal(m, ['post', 'designation', 'position', 'rank']);
        final phone = _getVal(m, ['phone', 'phonenumber', 'whatsapp', 'contact', 'mobile']);
        final roll = _getVal(m, ['rollnumber', 'rollno', 'regno', 'registernumber', 'regid']);
        final branch = _getVal(m, ['branch', 'department', 'dept', 'course']);
        final plan = _getVal(m, ['plan', 'membershipplan', 'subscription', 'package']) ?? '1 Year';
        final forum = _getVal(m, ['forum', 'forumname', 'chapter', 'club']);

        if (email == null || email.isEmpty) {
          failed++;
          continue;
        }

        final params = {
          'name': name ?? '', 
          'email': email,
          'role': role.toString().toLowerCase().trim().replaceAll(' ', '_'),
          'post': post ?? '', 
          'phone': phone ?? '',
          'roll_number': roll ?? '', 
          'branch': branch ?? '',
          'membership_plan': plan, 
          'forum': forum ?? _selectedForum ?? 'NONE',
          'status': 'active',
        };
        
        final res = await Supabase.instance.client.functions.invoke('admin-create-user', body: params);
        if (res.status == 200 || res.status == 201) {
          success++;
        } else {
          failed++;
          debugPrint('Bulk edge dev fail: ${res.data}');
        }
      } catch (e) { 
        failed++; 
        debugPrint('Bulk exception: $e');
      }
      setState(() => _bulkStatus = 'Importing... $success / ${_bulkData.length}');
    }

    setState(() => _isLoading = false);
    _showResultDialog(success, failed);
  }

  void _showResultDialog(int success, int failed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF15201D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: Colors.white10)),
        title: Text('Import Results', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatRow('Successful', success.toString(), Colors.greenAccent),
            const SizedBox(height: 12),
            _buildStatRow('Failed/Skipped', failed.toString(), Colors.redAccent),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (failed == 0) {
                Navigator.pop(context);
              } else {
                setState(() => _bulkData = []); // Clear data if finished
              }
            },
            child: Text('Done', style: GoogleFonts.inter(color: AppTheme.secondary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
          Text(value, style: GoogleFonts.spaceGrotesk(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background Gradient Circles
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.secondary.withValues(alpha: 0.15),
                    AppTheme.secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.blue.withValues(alpha: 0.1),
                    Colors.blue.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildManualEntry(),
                      _buildBulkImport(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppTheme.darkGreen,
                unselectedLabelColor: Colors.white60,
                labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 12),
                tabs: const [
                  Tab(text: 'INDIVIDUAL'),
                  Tab(text: 'BULK IMPORT'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 48), // Spacer for balance
        ],
      ),
    );
  }



  Widget _buildManualEntry() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildSectionHeader('Personal Details', Icons.person_outline),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CustomTextField(
                    label: 'Full Name', 
                    controller: _nameCtrl, 
                    prefixIcon: Icons.badge_outlined, 
                    validator: (v) => v!.isEmpty ? 'Required' : null
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Email address', 
                    controller: _emailCtrl, 
                    prefixIcon: Icons.email_outlined, 
                    keyboardType: TextInputType.emailAddress, 
                    validator: (v) => v!.isEmpty ? 'Required' : null
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Phone number', 
                    controller: _phoneCtrl, 
                    prefixIcon: Icons.phone_outlined, 
                    keyboardType: TextInputType.phone
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Academic & Org Profile', Icons.school_outlined),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: CustomTextField(label: 'Roll No', controller: _rollCtrl, prefixIcon: Icons.numbers_outlined)),
                      const SizedBox(width: 12),
                      Expanded(child: CustomTextField(label: 'Branch', controller: _branchCtrl, prefixIcon: Icons.account_tree_outlined)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDropdownField(
                    'Organization Role', 
                    _role, 
                    AppRole.values.where((r) => r != AppRole.restricted && r != AppRole.forumExeccom && r != AppRole.coreExeccom).map((r) => r.toDbString()).toList(),
                    (v) => setState(() => _role = v!),
                    itemLabel: (v) => AppRole.fromString(v).label,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(label: 'Active Post', controller: _postCtrl, prefixIcon: Icons.work_outline),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Membership Status', Icons.card_membership_outlined),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildDropdownField('Select Plan', _plan, ['1 Year', '4 Years', 'Life Member'], (v) => setState(() => _plan = v!)),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text('Enable SWAS Forum Option', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
                    value: _enableSwasForum,
                    onChanged: (val) {
                      setState(() {
                        _enableSwasForum = val;
                        if (!val && _selectedForum == 'SWAS') {
                          _selectedForum = null;
                        }
                      });
                    },
                    activeColor: AppTheme.secondary,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  _buildForumDropdown(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildDateField('Valid From', _membershipDate, () => _selectDate(context, true))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildDateField('Valid Until', _expiryDate, () => _selectDate(context, false))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              text: 'Enroll Member', 
              onPressed: _addMember, 
              isLoading: _isLoading,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkImport() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.secondary.withValues(alpha: 0.05),
                  blurRadius: 40,
                  spreadRadius: 10,
                )
              ]
            ),
            child: const Icon(Icons.file_upload_outlined, size: 64, color: AppTheme.secondary),
          ),
          const SizedBox(height: 32),
          Text(
            'Bulk Enrollment', 
            style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)
          ),
          const SizedBox(height: 12),
          Text(
            'Import members from an Excel sheet. Supported columns: Name, Email, Phone, RollNumber, Branch, Role, Post, Plan, Forum',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 48),
          if (_bulkData.isNotEmpty) ...[
            GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: AppTheme.secondary, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _bulkStatus, 
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.secondary)
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(text: 'Process Registry', onPressed: _processBulk, isLoading: _isLoading, icon: Icons.bolt),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _bulkData = []), 
                    child: const Text('Cancel & Reset', style: TextStyle(color: Colors.white38))
                  ),
                ],
              ),
            ),
          ] else ...[
            PrimaryButton(
              text: 'Load Excel Sheet', 
              onPressed: _pickExcel, 
              icon: Icons.add_to_photos_outlined,
              color: Colors.white.withValues(alpha: 0.05),
              textColor: Colors.white,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppTheme.secondary),
        ),
        const SizedBox(width: 12),
        Text(
          title.toUpperCase(), 
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 1.1, 
            color: Colors.white70
          )
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
      ],
    );
  }

  Widget _buildDropdownField(String label, String value, List<String> items, Function(String?) onChanged, {String Function(String)? itemLabel}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: value,
          dropdownColor: const Color(0xFF1E1E1E),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.03),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: const BorderSide(color: AppTheme.secondary, width: 1)
            ),
          ),
          items: items.map((item) => DropdownMenuItem(
            value: item, 
            child: Text(itemLabel?.call(item) ?? item)
          )).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDateField(String label, DateTime? date, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03), 
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 16, color: AppTheme.secondary),
                const SizedBox(width: 10),
                Text(
                  date == null ? 'Not Set' : DateFormat('MMM dd, yyyy').format(date), 
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForumDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Forum Association', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _selectedForum,
          hint: Text('Choose Forum', style: GoogleFonts.inter(color: Colors.white24, fontSize: 14)),
          dropdownColor: const Color(0xFF1E1E1E),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.03),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: const BorderSide(color: AppTheme.secondary, width: 1)
            ),
          ),
          items: ['EXIS', 'BITS', 'TORQ', 'GENESIS', if (_enableSwasForum) 'SWAS'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
          onChanged: (v) => setState(() => _selectedForum = v),
        ),
      ],
    );
  }
  String? _getVal(Map<String, dynamic> data, List<String> variations) {
    for (var v in variations) {
      final normalizedV = v.toLowerCase().trim().replaceAll(' ', '').replaceAll('_', '');
      if (data.containsKey(normalizedV) && data[normalizedV].toString().isNotEmpty) {
        return data[normalizedV].toString();
      }
    }
    return null;
  }
}


