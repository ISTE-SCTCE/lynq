class ExecomModel {
  final int id;
  final String name;
  final String? description;
  final int? parentId;
  final int sortOrder;
  final bool isForum;
  final String? createdBy;
  final DateTime? createdAt;

  const ExecomModel({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
    this.sortOrder = 0,
    this.isForum = false,
    this.createdBy,
    this.createdAt,
  });

  factory ExecomModel.fromJson(Map<String, dynamic> json) => ExecomModel(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
    parentId: json['parent_id'] as int?,
    sortOrder: json['sort_order'] as int? ?? 0,
    isForum: json['is_forum'] as bool? ?? false,
    createdBy: json['created_by'] as String?,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'parent_id': parentId,
    'sort_order': sortOrder,
    'is_forum': isForum,
  };
}

class ExecomMemberModel {
  final int id;
  final int execomId;
  final String userId;
  final String execomRole;
  final DateTime? joinedAt;
  final String? execomName; // populated via join
  final UserSummary? user; // populated via join

  const ExecomMemberModel({
    required this.id,
    required this.execomId,
    required this.userId,
    required this.execomRole,
    this.joinedAt,
    this.execomName,
    this.user,
  });

  factory ExecomMemberModel.fromJson(Map<String, dynamic> json) => ExecomMemberModel(
    id: json['id'] as int,
    execomId: json['execom_id'] as int,
    userId: json['user_id'] as String,
    execomRole: json['execom_role'] as String? ?? 'member',
    joinedAt: json['joined_at'] != null ? DateTime.parse(json['joined_at']) : null,
    execomName: json['execom'] != null ? json['execom']['name'] as String? : null,
    user: json['users'] != null ? UserSummary.fromJson(json['users']) : null,
  );
}

class UserSummary {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? post;

  const UserSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.post,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    post: json['post'] as String?,
  );
}

class ExecomPermissionModel {
  final int id;
  final int execomId;
  final String feature;
  final bool allowed;

  const ExecomPermissionModel({
    required this.id,
    required this.execomId,
    required this.feature,
    required this.allowed,
  });

  factory ExecomPermissionModel.fromJson(Map<String, dynamic> json) => ExecomPermissionModel(
    id: json['id'] as int,
    execomId: json['execom_id'] as int,
    feature: json['feature'] as String,
    allowed: json['allowed'] as bool? ?? false,
  );
}
