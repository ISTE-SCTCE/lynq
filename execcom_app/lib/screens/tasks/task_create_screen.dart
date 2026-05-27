import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_provider.dart';
import '../../models/task_models.dart';

class TaskCreateScreen extends StatefulWidget {
  final int? taskId; // if non-null, we're adding a subtask
  const TaskCreateScreen({super.key, this.taskId});

  @override
  State<TaskCreateScreen> createState() => _TaskCreateScreenState();
}

class _TaskCreateScreenState extends State<TaskCreateScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allUsers = [];
  List<String> _selectedUsers = [];
  int? _selectedForumId;
  List<Map<String, dynamic>> _forums = [];
  DateTime? _deadline;
  TaskPriority _priority = TaskPriority.medium;
  bool _proofRequired = true;
  bool _isSaving = false;

  bool get _isSubtask => widget.taskId != null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final [users, forums] = await Future.wait([
        _supabase.from('users').select('id, name, role').order('name'),
        if (!_isSubtask) _supabase.from('folders').select('id, name').order('name'),
      ]);
      if (mounted) {
        setState(() {
          _allUsers = (users as List).cast<Map<String, dynamic>>();
          if (!_isSubtask) _forums = (forums as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final auth = context.read<AuthProvider>();
      if (_isSubtask) {
        await _supabase.from('subtasks').insert({
          'task_id': widget.taskId,
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          'assigned_to': _selectedUsers,
          'deadline': _deadline?.toIso8601String(),
          'priority': _priority.dbValue,
          'proof_required': _proofRequired,
        });
      } else {
        await _supabase.from('tasks').insert({
          'title': _titleCtrl.text.trim(),
          'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          'created_by': auth.authUser?.id,
          'assigned_to': _selectedUsers,
          'forum_id': _selectedForumId,
          'deadline': _deadline?.toIso8601String(),
          'priority': _priority.dbValue,
        });
      }
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isSubtask ? 'Subtask created!' : 'Task created!'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: theme.colorScheme.onBackground.withValues(alpha: 0.7)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _isSubtask ? 'New Subtask' : 'New Task',
          style: GoogleFonts.spaceGrotesk(
              color: theme.colorScheme.onBackground, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 2),
                    ),
                  )
                : ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text('Save', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionLabel('Title', theme),
            _glassField(
              child: TextFormField(
                controller: _titleCtrl,
                style: GoogleFonts.inter(color: theme.colorScheme.onBackground),
                decoration: _inputDecoration('What needs to be done?', theme),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Title is required' : null,
                maxLines: 2,
              ),
              theme: theme,
            ),
            const SizedBox(height: 16),
            _sectionLabel('Description (optional)', theme),
            _glassField(
              child: TextFormField(
                controller: _descCtrl,
                style: GoogleFonts.inter(color: theme.colorScheme.onBackground),
                decoration: _inputDecoration('Add details, instructions...', theme),
                maxLines: 4,
              ),
              theme: theme,
            ),
            const SizedBox(height: 20),
            _sectionLabel('Priority', theme),
            _buildPrioritySelector(theme),
            const SizedBox(height: 20),
            _sectionLabel('Deadline', theme),
            _buildDeadlinePicker(theme),
            const SizedBox(height: 20),
            if (!_isSubtask) ...[
              _sectionLabel('Forum (optional)', theme),
              _buildForumSelector(theme),
              const SizedBox(height: 20),
            ],
            _sectionLabel('Assign To', theme),
            _buildAssigneeSelector(theme),
            const SizedBox(height: 20),
            if (_isSubtask) ...[
              _buildProofToggle(theme),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
            fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onBackground.withValues(alpha: 0.6)),
      ),
    );
  }

  Widget _glassField({required Widget child, required ThemeData theme}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }

  InputDecoration _inputDecoration(String hint, ThemeData theme) {
    return InputDecoration(
      border: InputBorder.none,
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: theme.colorScheme.onBackground.withValues(alpha: 0.3)),
    );
  }

  Widget _buildPrioritySelector(ThemeData theme) {
    return Row(
      children: TaskPriority.values.map((p) {
        final isSelected = _priority == p;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _priority = p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? p.color.withValues(alpha: 0.15) : theme.cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? p.color : theme.dividerColor.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(p.icon, size: 16, color: isSelected ? p.color : theme.colorScheme.onBackground.withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Text(
                    p.label,
                    style: GoogleFonts.spaceGrotesk(
                      color: isSelected ? p.color : theme.colorScheme.onBackground.withValues(alpha: 0.6),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDeadlinePicker(ThemeData theme) {
    return GestureDetector(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: _deadline ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (context, child) => Theme(
            data: theme,
            child: child!,
          ),
        );
        if (d != null) setState(() => _deadline = d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              _deadline == null ? 'Select Date' : _deadline.toString().split(' ')[0],
              style: GoogleFonts.inter(color: theme.colorScheme.onBackground, fontSize: 16),
            ),
            const Spacer(),
            if (_deadline != null)
              GestureDetector(
                onTap: () => setState(() => _deadline = null),
                child: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.onBackground.withValues(alpha: 0.4)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildForumSelector(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedForumId,
          hint: Text('General (No Forum)', style: GoogleFonts.inter(color: theme.colorScheme.onBackground.withValues(alpha: 0.5))),
          isExpanded: true,
          dropdownColor: theme.cardTheme.color,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: theme.colorScheme.onBackground.withValues(alpha: 0.5)),
          style: GoogleFonts.inter(color: theme.colorScheme.onBackground, fontSize: 16),
          items: [
            const DropdownMenuItem(value: null, child: Text('General (No Forum)')),
            ..._forums.map((f) => DropdownMenuItem(
                  value: f['id'] as int,
                  child: Text(f['name'] as String),
                )),
          ],
          onChanged: (v) => setState(() => _selectedForumId = v),
        ),
      ),
    );
  }

  Widget _buildAssigneeSelector(ThemeData theme) {
    if (_allUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }
    
    final filteredUsers = _searchCtrl.text.isEmpty
        ? _allUsers
        : _allUsers.where((u) {
            final name = (u['name'] as String).toLowerCase();
            return name.contains(_searchCtrl.text.toLowerCase());
          }).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      height: 250,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search members...',
                hintStyle: GoogleFonts.inter(color: theme.colorScheme.onBackground.withValues(alpha: 0.4), fontSize: 14),
                prefixIcon: Icon(Icons.search, size: 20, color: theme.colorScheme.onBackground.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              style: GoogleFonts.inter(color: theme.colorScheme.onBackground, fontSize: 14),
              onChanged: (val) => setState(() {}),
            ),
          ),
          Divider(color: theme.dividerColor.withValues(alpha: 0.1), height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: filteredUsers.length,
              itemBuilder: (ctx, i) {
                final u = filteredUsers[i];
                final id = u['id'] as String;
                final isSelected = _selectedUsers.contains(id);
                return CheckboxListTile(
                  value: isSelected,
                  activeColor: theme.colorScheme.primary,
                  checkColor: Colors.white,
                  side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                  title: Text(u['name'] as String, style: GoogleFonts.inter(color: theme.colorScheme.onBackground)),
                  subtitle: Text(u['role'] as String,
                      style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onBackground.withValues(alpha: 0.5))),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedUsers.add(id);
                      } else {
                        _selectedUsers.remove(id);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofToggle(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: SwitchListTile(
        value: _proofRequired,
        activeColor: theme.colorScheme.primary,
        title: Text(
          'Require Proof of Completion',
          style: GoogleFonts.inter(color: theme.colorScheme.onBackground, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Tasker must upload a document/image to complete this task.',
          style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onBackground.withValues(alpha: 0.5)),
        ),
        onChanged: (v) => setState(() => _proofRequired = v),
      ),
    );
  }
}
