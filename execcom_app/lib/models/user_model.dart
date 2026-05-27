class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? post;
  final String? phone;
  final String? rollNumber;
  final String? branch;
  final String? membershipPlan;
  final DateTime? membershipDate;
  final String? forum;
  final DateTime? expiryDate;
  final bool isPrimaryChairman;
  final bool isSudo;
  final bool isBudgetActivated;
  final Map<String, dynamic> permissions;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.post,
    this.phone,
    this.rollNumber,
    this.branch,
    this.membershipPlan,
    this.membershipDate,
    this.forum,
    this.expiryDate,
    this.isPrimaryChairman = false,
    this.isSudo = false,
    this.isBudgetActivated = false,
    this.permissions = const {},
    this.lastSeen,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    post: json['post'] as String?,
    phone: json['phone'] as String?,
    rollNumber: json['roll_number'] as String?,
    branch: json['branch'] as String?,
    membershipPlan: json['membership_plan'] as String?,
    membershipDate: json['membership_date'] != null ? DateTime.parse(json['membership_date']) : null,
    forum: json['forum'] as String?,
    expiryDate: json['expiry_date'] != null ? DateTime.parse(json['expiry_date']) : null,
    isPrimaryChairman: json['is_primary_chairman'] as bool? ?? false,
    isSudo: json['is_sudo'] as bool? ?? false,
    isBudgetActivated: json['is_budget_activated'] as bool? ?? false,
    permissions: (json['permissions'] as Map<String, dynamic>?) ?? {},
    lastSeen: json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'role': role,
    'post': post,
    'phone': phone,
    'roll_number': rollNumber,
    'branch': branch,
    'membership_plan': membershipPlan,
    'membership_date': membershipDate?.toIso8601String().split('T')[0],
    'forum': forum,
    'expiry_date': expiryDate?.toIso8601String().split('T')[0],
    'is_primary_chairman': isPrimaryChairman,
    'is_sudo': isSudo,
    'is_budget_activated': isBudgetActivated,
    'permissions': permissions,
  };

  UserModel copyWith({
    String? name,
    String? email,
    String? role,
    String? post,
    String? phone,
    String? rollNumber,
    String? branch,
    String? membershipPlan,
    DateTime? membershipDate,
    String? forum,
    DateTime? expiryDate,
    bool? isSudo,
    bool? isBudgetActivated,
    Map<String, dynamic>? permissions,
  }) => UserModel(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    role: role ?? this.role,
    post: post ?? this.post,
    phone: phone ?? this.phone,
    rollNumber: rollNumber ?? this.rollNumber,
    branch: branch ?? this.branch,
    membershipPlan: membershipPlan ?? this.membershipPlan,
    membershipDate: membershipDate ?? this.membershipDate,
    forum: forum ?? this.forum,
    expiryDate: expiryDate ?? this.expiryDate,
    isPrimaryChairman: isPrimaryChairman,
    isSudo: isSudo ?? this.isSudo,
    isBudgetActivated: isBudgetActivated ?? this.isBudgetActivated,
    permissions: permissions ?? this.permissions,
    lastSeen: lastSeen,
    createdAt: createdAt,
  );
}
