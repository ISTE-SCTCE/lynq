import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../models/app_models.dart';
import '../../shared/widgets/liquid_glass_nav_bar.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ConversationModel> _directChats = [];
  List<UserModel> _contacts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  RealtimeChannel? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _subscribeToChanges();
  }

  void _subscribeToChanges() {
    _messageSubscription = Supabase.instance.client
        .channel('public:messages_list')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            _loadData(); // Refresh list when any message is sent/updated
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _messageSubscription?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final supabase = Supabase.instance.client;
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      // 1. Load Recent Chats/Forums from view
      final recentData = await supabase
          .from('recent_chats')
          .select()
          .or('sender_id.eq.$myId,receiver_id.eq.$myId')
          .order('last_message_time', ascending: false);
      
      final allRecent = (recentData as List)
          .map((e) => ConversationModel.fromJson(e, myId))
          .toList();

      _directChats = allRecent.where((c) => c.folderId == null && (c.otherUserId != null)).toList();

      // 2. Load Contacts/Users
      final usersData = await supabase
          .from('users')
          .select()
          .neq('id', myId)
          .order('name');
      
      _contacts = (usersData as List).map((e) => UserModel.fromJson(e)).toList();

    } catch (e) {
      debugPrint('Chat load error: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1F2C34) : AppColors.waTeal,
        elevation: 0,
        title: Text('Messages', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'CHATS'),
            Tab(text: 'CONTACTS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatList(),
          _buildContactsList(),
        ],
      ),
      bottomNavigationBar: LiquidGlassNavBar(
        selectedIndex: 2,
        onItemSelected: (i) {
          if (i == 2) return;
          final perms = context.read<AuthProvider>().permissions;
          switch (i) {
            case 0: context.go('/home'); break;
            case 1: 
              if (perms != null && (perms.canRequestBudget || perms.canManageBudget)) {
                context.push('/budget');
              } else {
                context.push('/events');
              }
              break;
            case 3: context.push('/settings'); break;
          }
        },
        items: [
          LiquidNavItem(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_rounded, label: 'Home'),
          LiquidNavItem(
            icon: (context.read<AuthProvider>().permissions?.canRequestBudget ?? false) || (context.read<AuthProvider>().permissions?.canManageBudget ?? false)
                ? Icons.account_balance_wallet_outlined
                : Icons.calendar_today_outlined,
            selectedIcon: (context.read<AuthProvider>().permissions?.canRequestBudget ?? false) || (context.read<AuthProvider>().permissions?.canManageBudget ?? false)
                ? Icons.account_balance_wallet_rounded
                : Icons.calendar_today_rounded,
            label: (context.read<AuthProvider>().permissions?.canRequestBudget ?? false) || (context.read<AuthProvider>().permissions?.canManageBudget ?? false)
                ? 'Budget'
                : 'Events',
          ),
          LiquidNavItem(icon: Icons.chat_bubble_outline_rounded, selectedIcon: Icons.chat_bubble_rounded, label: 'Chat'),
          LiquidNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
        ],
      ),
      extendBody: true,
    );
  }

  Widget _buildChatList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_directChats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No chats yet', style: GoogleFonts.inter(color: Colors.grey)),
            TextButton(onPressed: () => _tabController.animateTo(1), child: const Text('Start messaging')),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _directChats.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80, endIndent: 16),
      itemBuilder: (context, i) {
        final chat = _directChats[i];
        final otherUser = _contacts.firstWhere(
          (u) => u.id == chat.otherUserId, 
          orElse: () => UserModel(id: chat.otherUserId!, name: 'Unknown', email: '', role: '')
        );
        
        return ListTile(
          onTap: () => context.push('/chat?userId=${otherUser.id}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[300],
            child: Text(otherUser.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(otherUser.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(
                DateFormat('hh:mm a').format(chat.lastMessageTime),
                style: GoogleFonts.inter(fontSize: 12, color: (chat.unreadCount > 0 && chat.lastMessageSenderId != context.read<AuthProvider>().currentUser?.id) ? AppColors.waGreen : Colors.grey),
              ),
            ],
          ),
          subtitle: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  chat.isDeleted ? 'Message unsent' : chat.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
              if (chat.unreadCount > 0 && chat.lastMessageSenderId != context.read<AuthProvider>().currentUser?.id)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: AppColors.waGreen, shape: BoxShape.circle),
                  child: Text('${chat.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildContactsList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    return ListView.builder(
      itemCount: _contacts.length,
      itemBuilder: (context, i) {
        final user = _contacts[i];
        return ListTile(
          onTap: () => context.push('/chat?userId=${user.id}'),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.secondary.withValues(alpha: 0.2),
            child: Text(user.name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.darkGreen)),
          ),
          title: Text(user.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          subtitle: Text(user.post ?? user.role, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        );
      },
    );
  }
}
