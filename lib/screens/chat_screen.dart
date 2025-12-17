import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_tabs/home_tabs_controller.dart';
import 'chat_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final HomeTabsController? controller;
  
  const ChatScreen({super.key, this.controller});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final supa = Supabase.instance.client;
  List<Map<String, dynamic>> _chatList = [];
  bool _loading = false;

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
    if (start == null) return '';
    final now = DateTime.now();
    final isToday = start.year == now.year && 
                    start.month == now.month && 
                    start.day == now.day;
    final isTomorrow = start.year == now.year && 
                       start.month == now.month && 
                       start.day == now.day + 1;
    
    if (isToday) return 'Today';
    if (isTomorrow) return 'Tomorrow';
    return '${start.month}/${start.day}';
  }

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() => _loading = true);
    final user = supa.auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final chatItems = <Map<String, dynamic>>[];

      // Use confirmed matches from controller if available, otherwise load directly
      List<Map<String, dynamic>> confirmedMatches = [];
      if (widget.controller != null) {
        confirmedMatches = widget.controller!.confirmedTeamMatches;
      } else {
        // Fallback: load directly from database
        final matches = await supa
            .from('instant_match_requests')
            .select('id, sport, start_time_1, team_id, matched_team_id, venue')
            .or('team_id.not.is.null,matched_team_id.not.is.null')
            .neq('status', 'cancelled')
            .not('matched_team_id', 'is', null)
            .order('start_time_1', ascending: false)
            .limit(20);
        
        confirmedMatches = (matches as List).map((m) => Map<String, dynamic>.from(m)).toList();
      }

      // Add group chats from confirmed/accepted matches
      for (final match in confirmedMatches) {
        final requestId = match['request_id'] as String? ?? match['id'] as String?;
        if (requestId == null) continue;
        
        final sport = match['sport'] as String? ?? '';
        final venue = match['venue'] as String? ?? '';
        final startDt = match['start_time'] as DateTime? ?? 
                       (match['start_time_1'] is String 
                         ? DateTime.tryParse(match['start_time_1'] as String)
                         : null);
        final teamAName = match['team_a_name'] as String? ?? 'Team A';
        final teamBName = match['team_b_name'] as String? ?? 'Team B';
        
        // Count players (accepted attendance)
        final teamAPlayers = (match['team_a_players'] as List?)?.length ?? 0;
        final teamBPlayers = (match['team_b_players'] as List?)?.length ?? 0;
        final totalPlayers = teamAPlayers + teamBPlayers;
        
        // Get venue name or use team names
        final sportEmoji = _getSportEmoji(sport);
        final chatTitle = venue.isNotEmpty 
            ? '$sportEmoji $sport - $venue'
            : '$sportEmoji $sport - $teamAName vs $teamBName';
        
        chatItems.add({
          'type': 'group',
          'id': requestId,
          'request_id': requestId,
          'sport': sport,
          'title': chatTitle,
          'venue': venue,
          'team_a_name': teamAName,
          'team_b_name': teamBName,
          'players': totalPlayers,
          'time': startDt,
          'time_display': _formatTime(startDt),
          'match_data': match, // Store full match data for detail screen
        });
      }

      setState(() {
        _chatList = chatItems;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load chats: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chatList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No chats yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Start chatting with friends or join group chats',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _chatList.length,
                    itemBuilder: (context, index) {
                      final chat = _chatList[index];
                      final sportEmoji = _getSportEmoji(chat['sport'] as String? ?? '');
                      final players = chat['players'] as int? ?? 0;
                      final timeDisplay = chat['time_display'] as String? ?? '';
                      
                      final venue = chat['venue'] as String? ?? '';
                      final teamAName = chat['team_a_name'] as String? ?? '';
                      final chatSport = chat['sport'] as String? ?? '';
                      final displayTitle = venue.isNotEmpty 
                          ? '$sportEmoji $chatSport - $venue'
                          : '$sportEmoji $chatSport Team';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              sportEmoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                          title: Text(
                            displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (players > 0)
                                Row(
                                  children: [
                                    const Text('👥 ', style: TextStyle(fontSize: 14)),
                                    Text('$players players'),
                                  ],
                                ),
                              if (timeDisplay.isNotEmpty)
                                Row(
                                  children: [
                                    const Text('🕒 ', style: TextStyle(fontSize: 14)),
                                    Text(timeDisplay),
                                  ],
                                ),
                              // Show admin info if available
                              if (venue.isEmpty && teamAName.isNotEmpty)
                                Row(
                                  children: [
                                    const Text('Admin: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text(teamAName, style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(
                                  chatData: chat,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

