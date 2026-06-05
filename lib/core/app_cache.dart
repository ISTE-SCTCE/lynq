import '../models/user_model.dart';

// Generic cache entry — eliminates repeating (data, timestamp, staleCheck) for every cached type.
class _CacheEntry<T> {
  T? value;
  DateTime? _fetchedAt;
  final Duration ttl;

  _CacheEntry(this.ttl);

  bool get isStale => _fetchedAt == null || DateTime.now().difference(_fetchedAt!) > ttl;
  bool get hasData => value != null;

  void update(T data) {
    value = data;
    _fetchedAt = DateTime.now();
  }

  void invalidate() {
    value = null;
    _fetchedAt = null;
  }
}

/// App-wide in-memory cache to avoid redundant network fetches.
/// Each entry has a 5-minute TTL. After expiry, the data is still returned
/// immediately (to avoid loading spinners) while a background refresh runs.
class AppCache {
  static final AppCache _instance = AppCache._internal();
  factory AppCache() => _instance;
  AppCache._internal();

  static const _ttl = Duration(minutes: 5);

  final _members       = _CacheEntry<List<UserModel>>(_ttl);
  final _globalUsers   = _CacheEntry<List<UserModel>>(_ttl);
  final _registration  = _CacheEntry<Map<String, dynamic>>(_ttl);
  final _chats         = _CacheEntry<List<dynamic>>(_ttl);

  // --- Members ---
  List<UserModel>? get membersList      => _members.value;
  bool get isMembersStale               => _members.isStale;
  void updateMembers(List<UserModel> v) => _members.update(v);

  // --- Global Users (for picker screens) ---
  List<UserModel>? get globalUsers          => _globalUsers.value;
  bool get isGlobalUsersStale               => _globalUsers.isStale;
  void updateGlobalUsers(List<UserModel> v) => _globalUsers.update(v);

  // --- Registration Summary ---
  Map<String, dynamic>? get registrationData             => _registration.value;
  bool get isRegistrationStale                           => _registration.isStale;
  void updateRegistrationData(Map<String, dynamic> v)    => _registration.update(v);

  // --- Chats ---
  List<dynamic>? get chatList          => _chats.value;
  bool get isChatsStale                => _chats.isStale;
  void updateChats(List<dynamic> v)    => _chats.update(v);

  /// Call on sign-out to wipe all cached data.
  void invalidateAll() {
    _members.invalidate();
    _globalUsers.invalidate();
    _registration.invalidate();
    _chats.invalidate();
  }
}
