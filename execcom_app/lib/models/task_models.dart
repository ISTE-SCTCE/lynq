import 'package:flutter/material.dart';

// ── Enums ──────────────────────────────────────────────────────────────────

enum TaskStatus {
  pending('pending', 'Pending'),
  inProgress('in_progress', 'In Progress'),
  awaitingVerification('awaiting_verification', 'Awaiting Verification'),
  completed('completed', 'Completed'),
  rejected('rejected', 'Rejected');

  final String dbValue;
  final String label;
  const TaskStatus(this.dbValue, this.label);

  static TaskStatus fromString(String? s) => switch (s) {
    'in_progress' => TaskStatus.inProgress,
    'awaiting_verification' => TaskStatus.awaitingVerification,
    'completed' => TaskStatus.completed,
    'rejected' => TaskStatus.rejected,
    _ => TaskStatus.pending,
  };

  Color get color => switch (this) {
    TaskStatus.pending => const Color(0xFF9E9E9E),
    TaskStatus.inProgress => const Color(0xFF6FA4AF),
    TaskStatus.awaitingVerification => const Color(0xFFD97D55),
    TaskStatus.completed => const Color(0xFFB8C4A9),
    TaskStatus.rejected => const Color(0xFFCF6679),
  };

  IconData get icon => switch (this) {
    TaskStatus.pending => Icons.radio_button_unchecked_rounded,
    TaskStatus.inProgress => Icons.timelapse_rounded,
    TaskStatus.awaitingVerification => Icons.pending_actions_rounded,
    TaskStatus.completed => Icons.check_circle_rounded,
    TaskStatus.rejected => Icons.cancel_rounded,
  };
}

enum TaskPriority {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High'),
  critical('critical', 'Critical');

  final String dbValue;
  final String label;
  const TaskPriority(this.dbValue, this.label);

  static TaskPriority fromString(String? s) => switch (s) {
    'low' => TaskPriority.low,
    'high' => TaskPriority.high,
    'critical' => TaskPriority.critical,
    _ => TaskPriority.medium,
  };

  Color get color => switch (this) {
    TaskPriority.low => const Color(0xFF78909C),
    TaskPriority.medium => const Color(0xFF6FA4AF),
    TaskPriority.high => const Color(0xFFD97D55),
    TaskPriority.critical => const Color(0xFFCF6679),
  };

  IconData get icon => switch (this) {
    TaskPriority.low => Icons.arrow_downward_rounded,
    TaskPriority.medium => Icons.remove_rounded,
    TaskPriority.high => Icons.arrow_upward_rounded,
    TaskPriority.critical => Icons.priority_high_rounded,
  };
}

enum ProofStatus {
  pending('pending', 'Pending Review'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected');

  final String dbValue;
  final String label;
  const ProofStatus(this.dbValue, this.label);

  static ProofStatus fromString(String? s) => switch (s) {
    'approved' => ProofStatus.approved,
    'rejected' => ProofStatus.rejected,
    _ => ProofStatus.pending,
  };

  Color get color => switch (this) {
    ProofStatus.pending => const Color(0xFFD97D55),
    ProofStatus.approved => const Color(0xFFB8C4A9),
    ProofStatus.rejected => const Color(0xFFCF6679),
  };
}

// ── Task Model ─────────────────────────────────────────────────────────────

class TaskModel {
  final int id;
  final String title;
  final String? description;
  final String? createdBy;
  final List<String> assignedTo;
  final int? execomId;
  final DateTime? deadline;
  final TaskPriority priority;
  final TaskStatus status;
  final int completionPercentage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  // Joined
  final List<SubtaskModel> subtasks;

  const TaskModel({
    required this.id,
    required this.title,
    this.description,
    this.createdBy,
    this.assignedTo = const [],
    this.execomId,
    this.deadline,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.completionPercentage = 0,
    this.createdAt,
    this.updatedAt,
    this.subtasks = const [],
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
    id: json['id'] as int,
    title: json['title'] as String,
    description: json['description'] as String?,
    createdBy: json['created_by'] as String?,
    assignedTo: (json['assigned_to'] as List<dynamic>?)?.cast<String>() ?? [],
    execomId: json['execom_id'] as int?,
    deadline: json['deadline'] != null ? DateTime.parse(json['deadline']) : null,
    priority: TaskPriority.fromString(json['priority'] as String?),
    status: TaskStatus.fromString(json['status'] as String?),
    completionPercentage: json['completion_percentage'] as int? ?? 0,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    subtasks: (json['subtasks'] as List<dynamic>?)
            ?.map((s) => SubtaskModel.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'assigned_to': assignedTo,
    'execom_id': execomId,
    'deadline': deadline?.toIso8601String(),
    'priority': priority.dbValue,
    'status': status.dbValue,
  };

  bool get isOverdue =>
      deadline != null && deadline!.isBefore(DateTime.now()) && status != TaskStatus.completed;

  Duration? get timeRemaining =>
      deadline != null ? deadline!.difference(DateTime.now()) : null;

  String get timeRemainingLabel {
    final remaining = timeRemaining;
    if (remaining == null) return 'No deadline';
    if (isOverdue) {
      final overdue = remaining.abs();
      if (overdue.inDays > 0) return '${overdue.inDays}d overdue';
      return '${overdue.inHours}h overdue';
    }
    if (remaining.inDays > 0) return '${remaining.inDays}d left';
    if (remaining.inHours > 0) return '${remaining.inHours}h left';
    return '${remaining.inMinutes}m left';
  }

  int get completedSubtasks => subtasks.where((s) => s.status == TaskStatus.completed).length;

  double get subtaskProgress =>
      subtasks.isEmpty ? 0 : completedSubtasks / subtasks.length;
}

// ── Subtask Model ──────────────────────────────────────────────────────────

class SubtaskModel {
  final int id;
  final int taskId;
  final String title;
  final String? description;
  final List<String> assignedTo;
  final DateTime? deadline;
  final TaskPriority priority;
  final TaskStatus status;
  final bool proofRequired;
  final int orderIndex;
  final DateTime? createdAt;
  // Joined
  final List<TaskProofModel> proofs;

  const SubtaskModel({
    required this.id,
    required this.taskId,
    required this.title,
    this.description,
    this.assignedTo = const [],
    this.deadline,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    this.proofRequired = true,
    this.orderIndex = 0,
    this.createdAt,
    this.proofs = const [],
  });

  factory SubtaskModel.fromJson(Map<String, dynamic> json) => SubtaskModel(
    id: json['id'] as int,
    taskId: json['task_id'] as int,
    title: json['title'] as String,
    description: json['description'] as String?,
    assignedTo: (json['assigned_to'] as List<dynamic>?)?.cast<String>() ?? [],
    deadline: json['deadline'] != null ? DateTime.parse(json['deadline']) : null,
    priority: TaskPriority.fromString(json['priority'] as String?),
    status: TaskStatus.fromString(json['status'] as String?),
    proofRequired: json['proof_required'] as bool? ?? true,
    orderIndex: json['order_index'] as int? ?? 0,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    proofs: (json['task_proofs'] as List<dynamic>?)
            ?.map((p) => TaskProofModel.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'title': title,
    'description': description,
    'assigned_to': assignedTo,
    'deadline': deadline?.toIso8601String(),
    'priority': priority.dbValue,
    'proof_required': proofRequired,
    'order_index': orderIndex,
  };

  bool get isOverdue =>
      deadline != null && deadline!.isBefore(DateTime.now()) && status != TaskStatus.completed;

  TaskProofModel? get latestProof =>
      proofs.isEmpty ? null : proofs.reduce((a, b) => a.createdAt != null && b.createdAt != null
          ? (a.createdAt!.isAfter(b.createdAt!) ? a : b)
          : a);
}

// ── Task Proof Model ───────────────────────────────────────────────────────

class TaskProofModel {
  final int id;
  final int subtaskId;
  final String? uploadedBy;
  final String fileUrl;
  final String fileType;
  final String? notes;
  final ProofStatus status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime? createdAt;

  const TaskProofModel({
    required this.id,
    required this.subtaskId,
    this.uploadedBy,
    required this.fileUrl,
    this.fileType = 'image',
    this.notes,
    this.status = ProofStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.createdAt,
  });

  factory TaskProofModel.fromJson(Map<String, dynamic> json) => TaskProofModel(
    id: json['id'] as int,
    subtaskId: json['subtask_id'] as int,
    uploadedBy: json['uploaded_by'] as String?,
    fileUrl: json['file_url'] as String,
    fileType: json['file_type'] as String? ?? 'image',
    notes: json['notes'] as String?,
    status: ProofStatus.fromString(json['status'] as String?),
    reviewedBy: json['reviewed_by'] as String?,
    reviewedAt: json['reviewed_at'] != null ? DateTime.parse(json['reviewed_at']) : null,
    rejectionReason: json['rejection_reason'] as String?,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
  );

  IconData get fileTypeIcon => switch (fileType) {
    'pdf' => Icons.picture_as_pdf_rounded,
    'video' => Icons.play_circle_rounded,
    'document' => Icons.description_rounded,
    'drive_link' => Icons.folder_shared_rounded,
    _ => Icons.image_rounded,
  };
}

// ── Registration Queue Model ───────────────────────────────────────────────

class RegistrationQueueModel {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? rollNumber;
  final String? branch;
  final String? year;
  final String membershipType;
  final String paymentStatus;
  final String source;
  final Map<String, dynamic> rawData;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final DateTime? createdAt;

  const RegistrationQueueModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.rollNumber,
    this.branch,
    this.year,
    this.membershipType = 'standard',
    this.paymentStatus = 'pending',
    this.source = 'google_form',
    this.rawData = const {},
    this.status = 'pending',
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.createdAt,
  });

  factory RegistrationQueueModel.fromJson(Map<String, dynamic> json) =>
      RegistrationQueueModel(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        rollNumber: json['roll_number'] as String?,
        branch: json['branch'] as String?,
        year: json['year'] as String?,
        membershipType: json['membership_type'] as String? ?? 'standard',
        paymentStatus: json['payment_status'] as String? ?? 'pending',
        source: json['source'] as String? ?? 'google_form',
        rawData: (json['raw_data'] as Map<String, dynamic>?) ?? {},
        status: json['status'] as String? ?? 'pending',
        reviewedBy: json['reviewed_by'] as String?,
        reviewedAt: json['reviewed_at'] != null
            ? DateTime.parse(json['reviewed_at'])
            : null,
        rejectionReason: json['rejection_reason'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : null,
      );

  Color get statusColor => switch (status) {
    'approved' => const Color(0xFFB8C4A9),
    'rejected' => const Color(0xFFCF6679),
    'payment_pending' => const Color(0xFFD97D55),
    'excel_intake' => const Color(0xFF0284C7),
    _ => const Color(0xFF6FA4AF),
  };

  String get statusLabel => switch (status) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'payment_pending' => 'Payment Pending',
    'excel_intake' => 'Excel Intake',
    _ => 'Pending',
  };
}
