import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../core/auth_provider.dart';
import '../../models/task_models.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  List<TaskModel> _allTasks = [];
  bool _isLoading = true;
  String _searchQuery = '';
  TaskStatus? _filterStatus;
  RealtimeChannel? _tasksChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadTasks();
    _setupRealtime();
  }

  void _setupRealtime() {
    _tasksChannel = _supabase.channel('public:tasks');
    _tasksChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tasks',
      callback: (payload) {
        if (!mounted) return;
        final eventType = payload.eventType;
        if (eventType == PostgresChangeEvent.insert) {
          final newTask = TaskModel.fromJson(payload.newRecord);
          setState(() {
            _allTasks.insert(0, newTask);
          });
        } else if (eventType == PostgresChangeEvent.update) {
          final updatedTask = TaskModel.fromJson(payload.newRecord);
          setState(() {
            final index = _allTasks.indexWhere((t) => t.id == updatedTask.id);
            if (index != -1) {
              // keep subtasks
              updatedTask.subtasks.addAll(_allTasks[index].subtasks);
              _allTasks[index] = updatedTask;
            }
          });
        } else if (eventType == PostgresChangeEvent.delete) {
          final deletedId = payload.oldRecord['id'] as int;
          setState(() {
            _allTasks.removeWhere((t) => t.id == deletedId);
          });
        }
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _tasksChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('tasks')
          .select('*, subtasks(*, task_proofs(*))')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _allTasks = (data as List)
              .map((e) => TaskModel.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<TaskModel> get _filteredTasks {
    var tasks = _allTasks;
    if (_searchQuery.isNotEmpty) {
      tasks = tasks
          .where((t) => t.title.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    return tasks;
  }

  List<TaskModel> _getByStatus(TaskStatus status) =>
      _filteredTasks.where((t) => t.status == status).toList();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.permissions?.isAtLeastTier1 ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: canCreate
          ? _buildFAB(context)
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, inner) => [
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            title: Text(
              'Task Management',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onBackground,
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(theme),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _buildTabBar(theme),
            ),
          ),
        ],
        body: RefreshIndicator(
          onRefresh: _loadTasks,
          color: theme.colorScheme.primary,
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTaskList(_filteredTasks, 'All Tasks', theme),
                    _buildTaskList(_getByStatus(TaskStatus.pending), 'No pending tasks', theme),
                    _buildTaskList(_getByStatus(TaskStatus.inProgress), 'Nothing in progress', theme),
                    _buildTaskList(_getByStatus(TaskStatus.awaitingVerification), 'No pending approvals', theme),
                    _buildTaskList(_getByStatus(TaskStatus.completed), 'No completed tasks', theme),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final pending = _allTasks.where((t) => t.status == TaskStatus.pending).length;
    final inProgress = _allTasks.where((t) => t.status == TaskStatus.inProgress).length;
    final awaiting = _allTasks.where((t) => t.status == TaskStatus.awaitingVerification).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildStatBadge('Pending', pending.toString(), TaskStatus.pending.color)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatBadge('Active', inProgress.toString(), TaskStatus.inProgress.color)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatBadge('Review', awaiting.toString(), TaskStatus.awaitingVerification.color)),
            ],
          ),
          const SizedBox(height: 16),
          _buildOverallProgressBar(theme),
        ],
      ),
    );
  }

  Widget _buildOverallProgressBar(ThemeData theme) {
    if (_allTasks.isEmpty) return const SizedBox.shrink();
    
    final completed = _allTasks.where((t) => t.status == TaskStatus.completed).length;
    final progress = completed / _allTasks.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Overall Progress', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onBackground.withValues(alpha: 0.7))),
            Text('${(progress * 100).toInt()}%', style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 8),
        LinearPercentIndicator(
          lineHeight: 8,
          percent: progress,
          backgroundColor: theme.dividerColor.withValues(alpha: 0.2),
          progressColor: theme.colorScheme.primary,
          barRadius: const Radius.circular(4),
          padding: EdgeInsets.zero,
          animation: true,
          animationDuration: 1000,
        ),
      ],
    );
  }

  Widget _buildStatBadge(String label, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(count, style: GoogleFonts.spaceGrotesk(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          Text(label, style: GoogleFonts.inter(color: color.withValues(alpha: 0.8), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1))),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        dividerColor: Colors.transparent,
        indicatorColor: theme.colorScheme.primary,
        indicatorWeight: 3,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onBackground.withValues(alpha: 0.5),
        labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Pending'),
          Tab(text: 'Active'),
          Tab(text: 'Review'),
          Tab(text: 'Done'),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<TaskModel> tasks, String emptyMessage, ThemeData theme) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: theme.colorScheme.onBackground.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(emptyMessage, style: GoogleFonts.inter(color: theme.colorScheme.onBackground.withValues(alpha: 0.4))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: tasks.length,
      itemBuilder: (ctx, i) => _TaskCard(task: tasks[i], theme: theme),
    );
  }

  Widget _buildFAB(BuildContext context) {
    final theme = Theme.of(context);
    return FloatingActionButton.extended(
      onPressed: () => context.push('/tasks/create'),
      backgroundColor: theme.colorScheme.primary,
      icon: const Icon(Icons.add, color: Colors.white),
      label: Text('New Task', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}

// ── Task Card ──────────────────────────────────────────────────────────────

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  final ThemeData theme;

  const _TaskCard({required this.task, required this.theme});

  @override
  Widget build(BuildContext context) {
    final progress = task.subtaskProgress;
    final isOverdue = task.isOverdue;

    return GestureDetector(
      onTap: () => context.push('/tasks/${task.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOverdue ? Colors.red.withValues(alpha: 0.3) : theme.dividerColor.withValues(alpha: 0.1),
            width: isOverdue ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isOverdue ? Colors.red.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: task.priority.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onBackground,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: task.status),
                ],
              ),
              if (task.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  task.description!,
                  style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onBackground.withValues(alpha: 0.5)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 14),
              if (task.subtasks.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearPercentIndicator(
                        lineHeight: 6,
                        percent: progress,
                        backgroundColor: theme.dividerColor.withValues(alpha: 0.2),
                        progressColor: task.status == TaskStatus.completed
                            ? task.priority.color
                            : theme.colorScheme.primary,
                        barRadius: const Radius.circular(3),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${task.completedSubtasks}/${task.subtasks.length}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, color: theme.colorScheme.onBackground.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Icon(
                    isOverdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                    size: 14,
                    color: isOverdue ? Colors.red : theme.colorScheme.onBackground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    task.timeRemainingLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isOverdue ? Colors.red : theme.colorScheme.onBackground.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  Icon(task.priority.icon, size: 14, color: task.priority.color),
                  const SizedBox(width: 4),
                  Text(
                    task.priority.label,
                    style: GoogleFonts.inter(fontSize: 11, color: task.priority.color),
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

// ── Status Chip ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final TaskStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: status.color),
          ),
        ],
      ),
    );
  }
}
