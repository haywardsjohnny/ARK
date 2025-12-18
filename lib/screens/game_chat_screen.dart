import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GameChatScreen extends StatefulWidget {
  final String requestId;
  final String chatMode;
  final String? teamAId;
  final String? teamBId;

  const GameChatScreen({
    super.key,
    required this.requestId,
    required this.chatMode,
    this.teamAId,
    this.teamBId,
  });

  @override
  State<GameChatScreen> createState() => _GameChatScreenState();
}

class _GameChatScreenState extends State<GameChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;
  String? _currentUserId;
  Map<String, String> _userNames = {};
  Map<String, bool> _userIsAdmin = {};

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _loadMessages();
    _loadUserInfo();
    _setupRealtime();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final supa = Supabase.instance.client;
    
    // Load user names
    final userIds = _messages.map((m) => m['user_id'] as String).toSet().toList();
    if (userIds.isEmpty) return;
    
    final users = await supa
        .from('users')
        .select('id, full_name')
        .inFilter('id', userIds);
    
    if (users is List) {
      for (final u in users) {
        final id = u['id'] as String?;
        final name = u['full_name'] as String?;
        if (id != null) {
          _userNames[id] = name ?? 'Unknown';
        }
      }
    }
    
    // Load admin status for users
    if (widget.teamAId != null || widget.teamBId != null) {
      final teamIds = [widget.teamAId, widget.teamBId]
          .where((id) => id != null)
          .cast<String>()
          .toList();
      
      if (teamIds.isNotEmpty) {
        final members = await supa
            .from('team_members')
            .select('user_id, team_id, role')
            .inFilter('team_id', teamIds)
            .inFilter('user_id', userIds);
        
        if (members is List) {
          for (final m in members) {
            final uid = m['user_id'] as String?;
            final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
            if (uid != null) {
              _userIsAdmin[uid] = role == 'admin';
            }
          }
        }
      }
    }
    
    if (mounted) setState(() {});
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    
    try {
      final supa = Supabase.instance.client;
      final messages = await supa
          .from('game_messages')
          .select('id, user_id, message, created_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: true);
      
      if (messages is List) {
        _messages.clear();
        _messages.addAll(messages.map((m) => Map<String, dynamic>.from(m)));
        
        // Load user names for new messages
        await _loadUserInfo();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load messages: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  void _setupRealtime() {
    final supa = Supabase.instance.client;
    _channel = supa.channel('game_messages_${widget.requestId}');
    
    _channel?.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'game_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'request_id',
        value: widget.requestId,
      ),
      callback: (payload) {
        final newMessage = payload.newRecord;
        if (newMessage != null) {
          setState(() {
            _messages.add(Map<String, dynamic>.from(newMessage));
          });
          _loadUserInfo();
          _scrollToBottom();
        }
      },
    );
    
    _channel?.subscribe();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    if (_currentUserId == null) return;
    
    // Check if user can send (admins_only mode)
    if (widget.chatMode == 'admins_only') {
      final canSend = _userIsAdmin[_currentUserId] ?? false;
      if (!canSend) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only admins can send messages in this chat'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }
    
    setState(() => _sending = true);
    
    try {
      final supa = Supabase.instance.client;
      await supa.from('game_messages').insert({
        'request_id': widget.requestId,
        'user_id': _currentUserId,
        'message': _messageController.text.trim(),
      });
      
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    
    return '${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMyMessage = (String userId) => userId == _currentUserId;
    final canSend = widget.chatMode == 'all_users' || 
                   (_userIsAdmin[_currentUserId] ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Chat'),
        actions: [
          if (widget.chatMode == 'admins_only')
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Admins Only',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start the conversation!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final userId = message['user_id'] as String? ?? '';
                          final isMine = isMyMessage(userId);
                          final userName = _userNames[userId] ?? 'Unknown';
                          final isAdmin = _userIsAdmin[userId] ?? false;
                          final createdAt = message['created_at'];
                          DateTime? dateTime;
                          if (createdAt is String) {
                            dateTime = DateTime.tryParse(createdAt);
                          }
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: isMine
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMine) ...[
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(
                                      userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: isMine
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            userName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isMine
                                                  ? Colors.orange.shade700
                                                  : Colors.grey.shade700,
                                            ),
                                          ),
                                          if (isAdmin) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade100,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                'Admin',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade800,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatTime(dateTime),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMine
                                              ? Colors.orange.shade700
                                              : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          message['message'] as String? ?? '',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isMine ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isMine) ...[
                                  const SizedBox(width: 8),
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.orange.shade100,
                                    child: Text(
                                      userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: canSend
                          ? 'Type a message...'
                          : 'Only admins can message',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabled: canSend,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: canSend && !_sending ? _sendMessage : null,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.send,
                          color: canSend
                              ? Colors.orange.shade700
                              : Colors.grey.shade400,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

