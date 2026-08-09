import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../models/app_models.dart';
import 'package:go_router/go_router.dart';

class ChatScreen extends StatefulWidget {
  final String? otherUserId;
  final int? forumId;
  final String? forumName;

  const ChatScreen({
    super.key, 
    this.otherUserId,
    this.forumId,
    this.forumName,
  }) : assert(otherUserId != null || forumId != null);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<MessageModel> _messages = [];
  String? _myId;
  String _myName = '';
  bool _isOtherUserOnline = false;
  bool _isLoading = true;
  UserModel? _otherUser;
  String? _otherName;
  int _memberCount = 0;
  RealtimeChannel? _chatChannel;
  RealtimeChannel? _presenceChannel;

  List<EventModel> _allEvents = [];
  bool _showEventDropdown = false;
  List<EventModel> _filteredEvents = [];

  User? get user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _myId = user?.id;
    _loadData().then((_) {
      if (_myId != null) {
        _loadMessages();
        _setupRealtime();
        _setupPresence();
      }
    });
  }

  @override
  void dispose() {
    _chatChannel?.unsubscribe();
    _presenceChannel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupPresence() {
    if (_myId == null || widget.otherUserId == null) return;

    _presenceChannel = Supabase.instance.client.channel('presence:${widget.otherUserId}');
    
    _presenceChannel!
      .onPresenceSync((_) {
        final onlineUsers = _presenceChannel!.presenceState();
        bool found = false;
        for (final dynamic presence in onlineUsers) {
          if (presence.payload['user_id'] == widget.otherUserId) {
            found = true;
            break;
          }
        }
        if (mounted) setState(() => _isOtherUserOnline = found);
      })
      .onPresenceJoin((payload) {
        if (payload.newPresences.any((p) => p.payload['user_id'] == widget.otherUserId)) {
          if (mounted) setState(() => _isOtherUserOnline = true);
        }
      })
      .onPresenceLeave((payload) {
        if (payload.leftPresences.any((p) => p.payload['user_id'] == widget.otherUserId)) {
          if (mounted) setState(() => _isOtherUserOnline = false);
        }
      })
      .subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await _presenceChannel!.track({'user_id': _myId, 'online_at': DateTime.now().toIso8601String()});
        }
      });
  }

  void _setupRealtime() {
    if (_myId == null) return;
    
    _chatChannel = Supabase.instance.client.channel('public:messages');
    
    _chatChannel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: widget.forumId != null ? 'execom_id' : 'conversation_id',
        value: widget.forumId != null ? widget.forumId : _generateConvId(_myId!, widget.otherUserId!),
      ),
      callback: (payload) {
        if (widget.forumId == null) {
          final newRecord = payload.newRecord;
          final sender = newRecord['sender_id'] as String?;
          final receiver = newRecord['receiver_id'] as String?;
          if (sender != _myId && receiver != _myId && sender != widget.otherUserId && receiver != widget.otherUserId) return;
        }
        if (payload.eventType == PostgresChangeEvent.insert) {
          final newMsg = MessageModel.fromJson(payload.newRecord);
          // Auto-mark as read if we are the receiver in a DM
          if (widget.otherUserId != null && newMsg.senderId == widget.otherUserId) {
            _markAsRead(newMsg.id);
          }
          if (mounted) {
            setState(() {
              // Avoid duplicates if already added by _sendMessage
              if (!_messages.any((m) => m.id == newMsg.id)) {
                _messages.insert(0, newMsg);
              }
            });
          }
        } else if (payload.eventType == PostgresChangeEvent.update) {
          final updatedMsg = MessageModel.fromJson(payload.newRecord);
          if (mounted) {
            setState(() {
              final index = _messages.indexWhere((m) => m.id == updatedMsg.id);
              if (index != -1) {
                _messages[index] = updatedMsg;
              }
            });
          }
        }
      },
    ).subscribe();
  }

  Future<void> _loadData() async {
    final supabase = Supabase.instance.client;
    try {
      final eventsData = await supabase.from('events').select().order('date', ascending: true);
      _allEvents = (eventsData as List).map((e) => EventModel.fromJson(e)).toList();

      if (widget.forumId != null) {
        final folderData = await supabase.from('folders').select('name').eq('id', widget.forumId!).single();
        final memberCountRes = await supabase.from('folder_members').select('id').eq('execom_id', widget.forumId!);
        setState(() {
          _otherName = folderData['name'] as String? ?? 'Forum';
          _memberCount = (memberCountRes as List).length;
          _isLoading = false;
        });
      } else if (widget.otherUserId != null) {
        final userData = await supabase.from('profiles').select().eq('id', widget.otherUserId!).single();
        setState(() {
          _otherUser = UserModel.fromJson(userData);
          _otherName = _otherUser?.name ?? 'User';
        });
      }

      if (_myId != null) {
        final myData = await supabase.from('profiles').select('name').eq('id', _myId!).single();
        _myName = myData['name'] as String? ?? 'Me';
      }
    } catch (e) {
      debugPrint('Chat load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unsendMessage(MessageModel msg) async {
    if (msg.senderId != _myId) return;
    if (msg.timestamp == null || DateTime.now().difference(msg.timestamp!).inMinutes > 15) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot unsend after 15 minutes')));
      return;
    }
    try {
      await Supabase.instance.client
          .from('messages')
          .update({
            'is_deleted': true,
            'content': 'Message unsent',
          })
          .eq('id', msg.id);

      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == msg.id);
          if (index != -1) {
            _messages[index] = MessageModel(
              id: msg.id,
              senderId: msg.senderId,
              receiverId: msg.receiverId,
              content: 'Message unsent',
              timestamp: msg.timestamp,
              isDeleted: true,
              folderId: msg.folderId,
              senderName: msg.senderName,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error unsending: $e');
    }
  }

  Future<void> _loadMessages() async {
    if (_myId == null) return;
    await _markAllAsRead(); // Wait for existing to mark as read before fetching
    
    var query = Supabase.instance.client
        .from('messages')
        .select();
    
    if (widget.forumId != null) {
      query = query.eq('execom_id', widget.forumId!);
    } else {
      query = query.or('and(sender_id.eq.$_myId,receiver_id.eq.${widget.otherUserId}),and(sender_id.eq.${widget.otherUserId},receiver_id.eq.$_myId)');
    }

    try {
      final data = await query.order('timestamp', ascending: false);
      if (mounted) {
        setState(() {
          _messages = (data as List).map((e) => MessageModel.fromJson(e)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(int messageId) async {
    try {
      await Supabase.instance.client
          .from('messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', messageId);
      debugPrint('Marked message $messageId as read');
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    if (_myId == null || widget.otherUserId == null) return;
    final convId = _generateConvId(_myId!, widget.otherUserId!);
    try {
      await Supabase.instance.client
          .from('messages')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('sender_id', widget.otherUserId!)
          .eq('receiver_id', _myId!)
          .filter('read_at', 'is', null); // Correct null filter
    } catch (e) {
      debugPrint('Mark all as read error: $e');
    }
  }

  String _generateConvId(String id1, String id2) {
    var ids = [id1, id2];
    ids.sort();
    return ids.join('_');
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _myId == null) return;
    final text = _messageController.text.trim();
    _messageController.clear();
    
    // Removing optimistic insert to fix duplication and fake ID issue.
    // Realtime Postgres changes will insert the message instantly.

    try {
      final Map<String, dynamic> payload = {
        'sender_id': _myId,
        'sender': _myName,
        'content': text,
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (widget.forumId != null) {
        payload['execom_id'] = widget.forumId;
      } else {
        payload['receiver_id'] = widget.otherUserId;
        payload['conversation_id'] = _generateConvId(_myId!, widget.otherUserId!);
      }

      await Supabase.instance.client.from('messages').insert(payload);
      
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } catch (e) {
      debugPrint('Send error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      _loadMessages();
    }
  }

  void _onMessageChanged(String text) {
    if (text.contains('@')) {
      final parts = text.split('@');
      final query = parts.last.toLowerCase();
      setState(() {
        _showEventDropdown = true;
        _filteredEvents = _allEvents.where((e) => e.title.toLowerCase().contains(query)).toList();
      });
    } else {
      setState(() {
        _showEventDropdown = false;
      });
    }
  }

  void _onEventSelected(EventModel event) {
    final text = _messageController.text;
    final parts = text.split('@');
    parts.removeLast();
    final newText = '${parts.join('@')}@${event.title} ';
    _messageController.text = newText;
    _messageController.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));
    
    Supabase.instance.client.from('announcements').insert({
      'title': 'Event Mentioned: ${event.title}',
      'content': 'An event was mentioned in the chat: ${event.title}. Tap here to check it out!',
      'visibility': 'public',
      'created_by': _myId,
    }).catchError((e) => debugPrint('Error sending notification: $e'));

    setState(() {
      _showEventDropdown = false;
    });
  }

  Widget _buildMessageText(MessageModel msg, bool isDark) {
    final style = GoogleFonts.inter(
      color: msg.isDeleted ? Colors.grey : (isDark ? Colors.white : Colors.black87), 
      fontSize: 16,
      fontStyle: msg.isDeleted ? FontStyle.italic : FontStyle.normal,
    );
    
    final content = msg.isDeleted ? '🚫 This message was unsent' : msg.content;
    if (!content.contains('@')) return Text(content, style: style);

    List<InlineSpan> spans = [];
    int currentIndex = 0;
    
    // Simple parsing for @EventTitle
    for (final event in _allEvents) {
      final mention = '@${event.title}';
      if (content.contains(mention)) {
        final matches = mention.allMatches(content);
        for (final match in matches) {
          if (match.start >= currentIndex) {
            if (match.start > currentIndex) {
              spans.add(TextSpan(text: content.substring(currentIndex, match.start), style: style));
            }
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: InkWell(
                onTap: () => context.push('/events'), // Specific event details if possible
                child: Text(mention, style: style.copyWith(color: AppTheme.secondary, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
              ),
            ));
            currentIndex = match.end;
          }
        }
      }
    }
    
    if (currentIndex < content.length) {
      spans.add(TextSpan(text: content.substring(currentIndex), style: style));
    }

    if (spans.isEmpty) return Text(content, style: style);
    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFFE5DDD5),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1F2C34) : AppColors.waTeal,
        elevation: 1,
        leadingWidth: 70,
        leading: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[300],
              child: Text(_otherUser?.name != null && _otherUser!.name.isNotEmpty ? _otherUser!.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.forumId != null ? widget.forumName ?? "Forum" : _otherUser?.name ?? "Chat", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
            if (widget.forumId == null)
              Text(_isOtherUserOnline ? "online" : "offline", style: GoogleFonts.inter(fontSize: 11, color: _isOtherUserOnline ? const Color(0xFF00A884) : Colors.white70)),
            if (widget.forumId != null)
              Text("$_memberCount members", style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          if (widget.forumId != null)
            IconButton(
              icon: const Icon(Icons.people_outline, color: Colors.white),
              onPressed: () => context.push('/folders/${widget.forumId}/members', extra: {'forum_name': widget.forumName}),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.05 : 0.08,
              child: Image.asset(
                'assets/images/wa_bg.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: _isLoading && _messages.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final msg = _messages[i];
                            final isMine = msg.senderId == _myId;
                            return _buildWhatsAppBubble(msg, isMine);
                          },
                        ),
                ),
                if (_showEventDropdown && _filteredEvents.isNotEmpty)
                  Container(
                    color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredEvents.length,
                      itemBuilder: (context, i) {
                        final event = _filteredEvents[i];
                        return ListTile(
                          title: Text(event.title, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                          onTap: () => _onEventSelected(event),
                        );
                      },
                    ),
                  ),
                _buildWhatsAppInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppBubble(MessageModel msg, bool isMine) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = isMine 
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFE7FFDB))
        : (isDark ? const Color(0xFF1F2C34) : Colors.white);
    
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: (isMine && !msg.isDeleted) ? () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.white,
              title: const Text('Message Options'),
              content: const Text('Do you want to unsend this message?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _unsendMessage(msg);
                  },
                  child: const Text('Unsend', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          );
        } : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: CustomPaint(
            painter: BubblePainter(
              color: bubbleColor,
              alignment: isMine ? Alignment.topRight : Alignment.topLeft,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMessageText(msg, isDark),
                  const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('hh:mm a').format(msg.timestamp ?? DateTime.now()),
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey[600]),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.done_all, 
                        size: 14, 
                        color: msg.readAt != null ? const Color(0xFF53BDEB) : (isDark ? Colors.white60 : Colors.grey[400])
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildWhatsAppInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey[500]),
                      onPressed: () {},
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black87),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                        ),
                        onChanged: _onMessageChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF00A884),
              child: IconButton(
                icon: Icon(
                  _messageController.text.trim().isEmpty ? Icons.mic : Icons.send,
                  color: Colors.white,
                ),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BubblePainter extends CustomPainter {
  final Color color;
  final Alignment alignment;

  BubblePainter({required this.color, required this.alignment});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    const cornerRadius = 12.0;

    if (alignment == Alignment.topRight) {
      path.addRRect(RRect.fromLTRBR(0, 0, size.width - 8, size.height, const Radius.circular(cornerRadius)));
      path.moveTo(size.width - 8, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width - 8, 12);
    } else {
      path.addRRect(RRect.fromLTRBR(8, 0, size.width, size.height, const Radius.circular(cornerRadius)));
      path.moveTo(8, 0);
      path.lineTo(0, 0);
      path.lineTo(8, 12);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
