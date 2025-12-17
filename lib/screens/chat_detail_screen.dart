import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatDetailScreen extends StatefulWidget {
  final Map<String, dynamic> chatData;
  
  const ChatDetailScreen({super.key, required this.chatData});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final supa = Supabase.instance.client;
  final _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _announcements = [];
  bool _loading = false;
  bool _isAdmin = false;

  String _getSportEmoji(String sport) {
    final lower = sport.toLowerCase();
    if (lower.contains('soccer') || lower.contains('football')) return '⚽';
    if (lower.contains('basketball')) return '🏀';
    if (lower.contains('tennis')) return '🎾';
    if (lower.contains('volleyball')) return '🏐';
    if (lower.contains('cricket')) return '🏏';
    if (lower.contains('badminton')) return '🏸';
    return '🏃';
  }

  String _formatTime(DateTime? start) {
    if (start == null) return 'TBA';
    final h24 = start.hour;
    final m = start.minute.toString().padLeft(2, '0');
    final isPM = h24 >= 12;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final ampm = isPM ? 'PM' : 'AM';
    return '${start.month}/${start.day} $h12:$m $ampm';
  }

  @override
  void initState() {
    super.initState();
    _loadChatData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadChatData() async {
    setState(() => _loading = true);
    final user = supa.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final requestId = widget.chatData['request_id'] as String?;
      if (requestId == null) {
        setState(() => _loading = false);
        return;
      }

      // Check if user is admin of either team
      final match = widget.chatData['match_data'] as Map<String, dynamic>?;
      if (match != null) {
        final teamAId = match['team_id'] as String?;
        final teamBId = match['matched_team_id'] as String?;
        
        if (teamAId != null) {
          final memberA = await supa
              .from('team_members')
              .select('role')
              .eq('team_id', teamAId)
              .eq('user_id', user.id)
              .maybeSingle();
          if (memberA != null && (memberA['role'] as String?)?.toLowerCase() == 'admin') {
            _isAdmin = true;
          }
        }
        
        if (!_isAdmin && teamBId != null) {
          final memberB = await supa
              .from('team_members')
              .select('role')
              .eq('team_id', teamBId)
              .eq('user_id', user.id)
              .maybeSingle();
          if (memberB != null && (memberB['role'] as String?)?.toLowerCase() == 'admin') {
            _isAdmin = true;
          }
        }
      }

      // Load announcements (stored in a table or as part of match data)
      // TODO: Create announcements table or use match notes
      _announcements = [];

      // Load messages (would need a messages table)
      // TODO: Create messages table
      _messages = [];

      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load chat: $e')),
      );
    }
  }

  Future<void> _sendAnnouncement(String text) async {
    if (text.trim().isEmpty) return;
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only admins can send announcements')),
      );
      return;
    }

    // TODO: Save announcement to database
    setState(() {
      _announcements.add({
        'text': text,
        'created_at': DateTime.now(),
        'created_by': supa.auth.currentUser?.id,
      });
    });
    _messageController.clear();
  }

  Future<void> _openMap() async {
    final venue = widget.chatData['venue'] as String? ?? '';
    if (venue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No venue address available')),
      );
      return;
    }

    // Show venue in dialog (can be enhanced to open maps app later)
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Venue Location'),
        content: Text(venue),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _setReminder() async {
    final startDt = widget.chatData['time'] as DateTime?;
    if (startDt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No game time set')),
      );
      return;
    }

    // TODO: Implement reminder functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder set for game time')),
    );
  }

  Future<void> _leaveChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Chat'),
        content: const Text('Are you sure you want to leave this chat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Remove user from chat/attendance
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Left chat')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sport = widget.chatData['sport'] as String? ?? '';
    final venue = widget.chatData['venue'] as String? ?? 'Location TBA';
    final startDt = widget.chatData['time'] as DateTime?;
    final timeStr = _formatTime(startDt);
    final sportEmoji = _getSportEmoji(sport);

    return Scaffold(
      appBar: AppBar(
        title: Text('$sportEmoji ${widget.chatData['title'] as String? ?? 'Chat'}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Pinned Section
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pinned:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Expanded(child: Text(venue)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(timeStr),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.rule, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          const Expanded(child: Text('Standard game rules apply')),
                        ],
                      ),
                    ],
                  ),
                ),

                // Announcements Section (if admin)
                if (_isAdmin && _announcements.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.orange.shade50,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.campaign, size: 16, color: Colors.orange),
                            SizedBox(width: 4),
                            Text(
                              'Announcements',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._announcements.map((ann) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                            children: [
                              const Icon(Icons.campaign, size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              Expanded(child: Text(ann['text'] as String? ?? '')),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],

                // Messages Section
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text(
                                'No messages yet',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Start the conversation!',
                                style: TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(msg['sender'] as String? ?? 'User'),
                                subtitle: Text(msg['text'] as String? ?? ''),
                                trailing: Text(
                                  _formatTime(msg['created_at'] as DateTime?),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Quick Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildQuickAction(
                        icon: Icons.map,
                        label: 'Open Map',
                        color: Colors.red,
                        onTap: _openMap,
                      ),
                      const Text('|', style: TextStyle(color: Colors.grey)),
                      _buildQuickAction(
                        icon: Icons.alarm,
                        label: 'Reminder',
                        color: Colors.red,
                        onTap: _setReminder,
                      ),
                      const Text('|', style: TextStyle(color: Colors.grey)),
                      _buildQuickAction(
                        icon: Icons.close,
                        label: 'Leave',
                        color: Colors.red,
                        onTap: _leaveChat,
                      ),
                    ],
                  ),
                ),

                // Message Input (if admin, can send announcements)
                if (_isAdmin)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
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
                            decoration: const InputDecoration(
                              hintText: 'Send announcement...',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send),
                          color: Colors.orange,
                          onPressed: () => _sendAnnouncement(_messageController.text),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

