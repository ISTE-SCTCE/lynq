class EventModel {
  final int id;
  final String title;
  final DateTime? date;
  final String? description;
  final String? type;
  final int? folderId;
  final String? createdBy;
  final DateTime? createdAt;
  final int memberPrice;
  final int nonMemberPrice;
  final bool isPaid;
  final String? posterUrl;
  final String? location;
  final List<String>? allowedRoles;

  const EventModel({
    required this.id,
    required this.title,
    this.date,
    this.description,
    this.type,
    this.folderId,
    this.createdBy,
    this.createdAt,
    this.memberPrice = 0,
    this.nonMemberPrice = 0,
    this.isPaid = false,
    this.posterUrl,
    this.location,
    this.allowedRoles,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) => EventModel(
    id: json['id'] as int,
    title: json['title'] as String,
    date: json['date'] != null ? DateTime.parse(json['date']) : null,
    description: json['description'] as String?,
    type: json['type'] as String?,
    folderId: json['execom_id'] as int?,
    createdBy: json['created_by'] as String?,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    memberPrice: json['member_price'] as int? ?? 0,
    nonMemberPrice: json['non_member_price'] as int? ?? 0,
    isPaid: json['is_paid'] as bool? ?? false,
    posterUrl: json['poster_url'] as String?,
    location: json['location'] as String?,
    allowedRoles: (json['allowed_roles'] as List?)?.map((e) => e.toString()).toList(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'date': date?.toIso8601String().split('T').first,
    'description': description,
    'type': type,
    'execom_id': folderId,
    'created_by': createdBy,
    'member_price': memberPrice,
    'non_member_price': nonMemberPrice,
    'is_paid': isPaid,
  };
}

class AnnouncementModel {
  final int id;
  final String title;
  final String? content;
  final String? createdBy;
  final String visibility; // 'public' | 'internal'
  final DateTime? createdAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    this.content,
    this.createdBy,
    this.visibility = 'public',
    this.createdAt,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) => AnnouncementModel(
    id: json['id'] as int,
    title: json['title'] as String,
    content: json['content'] as String?,
    createdBy: json['created_by'] as String?,
    visibility: json['visibility'] as String? ?? 'public',
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
  );
}

class BudgetRequestModel {
  final int id;
  final int folderId;
  final String requestedBy;
  final double amount;
  final String? reason;
  final String? proposalUrl;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  const BudgetRequestModel({
    required this.id,
    required this.folderId,
    required this.requestedBy,
    required this.amount,
    this.reason,
    this.proposalUrl,
    this.status = 'pending',
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
  });

  factory BudgetRequestModel.fromJson(Map<String, dynamic> json) => BudgetRequestModel(
    id: json['id'] as int,
    folderId: json['execom_id'] as int? ?? 0,
    requestedBy: json['requested_by'] as String,
    amount: (json['amount'] as num).toDouble(),
    reason: json['reason'] as String?,
    proposalUrl: json['proposal_url'] as String?,
    status: json['status'] as String? ?? 'pending',
    reviewedBy: json['reviewed_by'] as String?,
    reviewedAt: json['reviewed_at'] != null ? DateTime.parse(json['reviewed_at']) : null,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
  );
}

class EventBudgetModel {
  final int id;
  final String eventName;
  final double budgetLimit;
  final double actualSpent;
  final DateTime? date;

  const EventBudgetModel({
    required this.id,
    required this.eventName,
    required this.budgetLimit,
    required this.actualSpent,
    this.date,
  });

  factory EventBudgetModel.fromJson(Map<String, dynamic> json) => EventBudgetModel(
    id: json['id'] as int,
    eventName: json['event_name'] as String,
    budgetLimit: (json['budget_limit'] as num).toDouble(),
    actualSpent: (json['actual_spent'] as num).toDouble(),
    date: json['date'] != null ? DateTime.parse(json['date']) : null,
  );
}


class MessageModel {
  final int id;
  final String? senderId;
  final String? receiverId;
  final String content;
  final String? conversationId;
  final DateTime? readAt;
  final DateTime? timestamp;
  final int? folderId;
  final String? senderName;
  final bool isDeleted;

  const MessageModel({
    required this.id,
    this.senderId,
    this.receiverId,
    this.folderId,
    required this.content,
    this.conversationId,
    this.readAt,
    this.timestamp,
    this.isDeleted = false,
    this.senderName,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
    id: json['id'] as int,
    senderId: json['sender_id'] as String?,
    receiverId: json['receiver_id'] as String?,
    folderId: json['execom_id'] as int?,
    content: json['content'] as String? ?? '',
    conversationId: json['conversation_id'] as String?,
    readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
    timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : null,
    isDeleted: json['is_deleted'] as bool? ?? false,
    senderName: json['sender'] as String?,
  );
}

class ConversationModel {
  final String conversationId;
  final String? otherUserId;
  final int? folderId;
  final String? folderName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isDeleted;
  final String? lastMessageSenderName;
  final String? lastMessageSenderId;

  const ConversationModel({
    required this.conversationId,
    this.otherUserId,
    this.folderId,
    this.folderName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    this.isDeleted = false,
    this.lastMessageSenderName,
    this.lastMessageSenderId,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json, String currentUserId) {
    return ConversationModel(
      conversationId: json['conversation_id'] as String? ?? '',
      otherUserId: json['execom_id'] != null 
          ? null 
          : ((json['sender_id'] == currentUserId) ? json['receiver_id'] as String : json['sender_id'] as String),
      folderId: json['execom_id'] as int?,
      folderName: json['folder_name'] as String?,
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageTime: DateTime.parse(json['last_message_time'] ?? DateTime.now().toIso8601String()),
      unreadCount: json['unread_count'] as int? ?? 0,
      isDeleted: json['is_deleted'] as bool? ?? false,
      lastMessageSenderName: json['sender_name'] as String?,
      lastMessageSenderId: json['sender_id'] as String?,
    );
  }
}

class ReportModel {
  final int id;
  final int? eventId;
  final String? uploadedBy;
  final int? folderId;
  final String title;
  final String content;
  final String? fileUrl;
  final String status;
  final DateTime? createdAt;

  const ReportModel({
    required this.id,
    this.eventId,
    this.uploadedBy,
    this.folderId,
    required this.title,
    required this.content,
    this.fileUrl,
    this.status = 'pending',
    this.createdAt,
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) => ReportModel(
    id: json['id'] as int,
    eventId: json['event_id'] as int?,
    uploadedBy: json['uploaded_by'] as String?,
    folderId: json['execom_id'] as int?,
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    fileUrl: json['file_url'] as String?,
    status: json['status'] as String? ?? 'pending',
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
  );
}

