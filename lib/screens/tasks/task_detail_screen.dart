import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../core/auth_provider.dart';
import '../../models/task_models.dart';

class TaskDetailScreen extends StatefulWidget {
  final int taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  TaskModel? _task;
  bool _isLoading = true;
  late AnimationController _completionController;
  late Animation<double> _completionAnim;

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _sage = Color(0xFFB8C4A9);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _completionController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _completionAnim = CurvedAnimation(
        parent: _completionController, curve: Curves.easeOutCubic);
    _loadTask();
  }

  @override
  void dispose() {
    _completionController.dispose();
    super.dispose();
  }

  Future<void> _loadTask() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('tasks')
          .select('*, subtasks(*, task_proofs(*))')
          .eq('id', widget.taskId)
          .single();
      if (mounted) {
        setState(() {
          _task = TaskModel.fromJson(data);
          _isLoading = false;
        });
        _completionController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateSubtaskStatus(SubtaskModel subtask, TaskStatus newStatus) async {
    try {
      await _supabase
          .from('subtasks')
          .update({'status': newStatus.dbValue, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', subtask.id);
      
      // Check if all subtasks are complete → auto-complete main task
      await _supabase.rpc('update_task_completion', params: {'task_id_param': widget.taskId});
      
      _loadTask();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        body: const Center(child: CircularProgressIndicator(color: _terracotta)),
      );
    }

    if (_task == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(backgroundColor: _bg),
        body: Center(child: Text('Task not found', style: GoogleFonts.inter(color: Colors.white54))),
      );
    }

    final task = _task!;
    final auth = context.watch<AuthProvider>();
    final canVerify = auth.permissions?.isAtLeastTier1 ?? false;
    final canEdit = auth.permissions?.isAtLeastTier1 ?? false;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(task, canEdit),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildProgressRing(task),
                  const SizedBox(height: 24),
                  _buildInfoCards(task),
                  const SizedBox(height: 24),
                  _buildSubtaskSection(task, canVerify),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(TaskModel task, bool canEdit) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: _bg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      actions: [
        if (canEdit)
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            onPressed: () => _showTaskOptions(task),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                task.priority.color.withValues(alpha: 0.2),
                _bg,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: task.priority.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: task.priority.color.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(task.priority.icon, size: 12, color: task.priority.color),
                        const SizedBox(width: 4),
                        Text(task.priority.label,
                            style: GoogleFonts.inter(
                                fontSize: 11, color: task.priority.color, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: task.status.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: task.status.color.withValues(alpha: 0.4)),
                    ),
                    child: Text(task.status.label,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: task.status.color, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(task.title,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 24, fontWeight: FontWeight.bold, color: _cream)),
              if (task.description != null) ...[
                const SizedBox(height: 6),
                Text(task.description!,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressRing(TaskModel task) {
    return Center(
      child: AnimatedBuilder(
        animation: _completionAnim,
        builder: (ctx, _) {
          final animated = _completionAnim.value * task.subtaskProgress;
          return CircularPercentIndicator(
            radius: 80,
            lineWidth: 10,
            percent: animated,
            animation: false,
            center: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(animated * 100).toInt()}%',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28, fontWeight: FontWeight.bold, color: _cream,
                  ),
                ),
                Text(
                  '${task.completedSubtasks}/${task.subtasks.length} done',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
            progressColor: task.status == TaskStatus.completed ? _sage : _terracotta,
            backgroundColor: Colors.white12,
            circularStrokeCap: CircularStrokeCap.round,
          );
        },
      ),
    );
  }

  Widget _buildInfoCards(TaskModel task) {
    return Row(
      children: [
        Expanded(
          child: _infoCard(
            Icons.schedule_rounded,
            'Deadline',
            task.deadline != null
                ? '${task.deadline!.day}/${task.deadline!.month}/${task.deadline!.year}'
                : 'No deadline',
            task.isOverdue ? Colors.red.shade400 : _teal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoCard(
            Icons.people_rounded,
            'Assigned',
            '${task.assignedTo.length} people',
            _teal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoCard(
            Icons.timer_rounded,
            'Time Left',
            task.timeRemainingLabel,
            task.isOverdue ? Colors.red.shade400 : _sage,
          ),
        ),
      ],
    );
  }

  Widget _infoCard(IconData icon, String label, String value, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text(label,
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w700, color: _cream),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtaskSection(TaskModel task, bool canVerify) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subtasks',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _cream)),
            if (canVerify)
              TextButton.icon(
                onPressed: () => context.push('/tasks/${task.id}/subtasks/create'),
                icon: const Icon(Icons.add_rounded, size: 16, color: _terracotta),
                label: Text('Add', style: GoogleFonts.inter(color: _terracotta, fontSize: 13)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (task.subtasks.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('No subtasks yet',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 14)),
            ),
          )
        else
          ...task.subtasks.asMap().entries.map(
            (entry) => _SubtaskTile(
              subtask: entry.value,
              index: entry.key,
              canVerify: canVerify,
              onTap: () => context.push('/tasks/${task.id}/subtasks/${entry.value.id}'),
              onStatusChange: (s) => _updateSubtaskStatus(entry.value, s),
            ),
          ),
      ],
    );
  }

  void _showTaskOptions(TaskModel task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _surface.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                _optionTile(Icons.edit_rounded, 'Edit Task', _teal, () {
                  Navigator.pop(ctx);
                }),
                _optionTile(Icons.assignment_turned_in_rounded, 'Mark Complete', _sage, () async {
                  Navigator.pop(ctx);
                  await _supabase.from('tasks')
                      .update({'status': 'completed', 'completion_percentage': 100})
                      .eq('id', task.id);
                  _loadTask();
                }),
                _optionTile(Icons.delete_rounded, 'Delete Task', Colors.red.shade400, () async {
                  Navigator.pop(ctx);
                  await _supabase.from('tasks').delete().eq('id', task.id);
                  if (mounted) context.pop();
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(label, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
    );
  }
}

// ── Subtask Tile ──────────────────────────────────────────────────────────

class _SubtaskTile extends StatelessWidget {
  final SubtaskModel subtask;
  final int index;
  final bool canVerify;
  final VoidCallback onTap;
  final Function(TaskStatus) onStatusChange;

  static const _surface = Color(0xFF1E1E1E);
  static const _cream = Color(0xFFF4E9D7);
  static const _terracotta = Color(0xFFD97D55);

  const _SubtaskTile({
    required this.subtask,
    required this.index,
    required this.canVerify,
    required this.onTap,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final proof = subtask.latestProof;
    final isComplete = subtask.status == TaskStatus.completed;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isComplete
                ? const Color(0xFFB8C4A9).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            // Step number / completion indicator
            GestureDetector(
              onTap: canVerify ? () => _showStatusPicker(context) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: subtask.status.color.withValues(alpha: 0.15),
                  border: Border.all(color: subtask.status.color.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: isComplete
                      ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFFB8C4A9))
                      : Text('${index + 1}',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 14, fontWeight: FontWeight.bold,
                              color: subtask.status.color)),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtask.title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: _cream,
                        decoration: isComplete ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.white38,
                      )),
                  if (proof != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(proof.fileTypeIcon, size: 12, color: Colors.white38),
                        const SizedBox(width: 4),
                        Text('Proof uploaded · ${proof.status.label}',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: proof.status.color)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  void _showStatusPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.97),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Update Subtask Status',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            ...TaskStatus.values.map((s) => ListTile(
              leading: Icon(s.icon, color: s.color),
              title: Text(s.label,
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500)),
              trailing: subtask.status == s
                  ? Icon(Icons.check_rounded, color: _terracotta)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                onStatusChange(s);
              },
            )),
          ],
        ),
      ),
    );
  }
}
