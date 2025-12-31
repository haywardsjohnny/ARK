import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile_screen.dart';

class FriendsGroupProfileScreen extends StatefulWidget {
  final String groupId;
  final String groupName; // just for initial AppBar title

  const FriendsGroupProfileScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<FriendsGroupProfileScreen> createState() => _FriendsGroupProfileScreenState();
}

class _FriendsGroupProfileScreenState extends State<FriendsGroupProfileScreen> {
  bool _loading = false;
  Map<String, dynamic>? _group;
  List<Map<String, dynamic>> _members = [];
  bool _isCreator = false;

  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadGroupProfile();
  }

  Future<void> _loadGroupProfile() async {
    setState(() => _loading = true);

    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;

    try {
      // 1) Load group details
      final groupRow = await supa
          .from('friends_groups')
          .select('id, name, sport, created_by')
          .eq('id', widget.groupId)
          .maybeSingle();

      if (groupRow == null) {
        setState(() {
          _group = null;
          _members = [];
          _isCreator = false;
          _currentUserId = null;
          _loading = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group not found')),
        );
        return;
      }

      // 2) Load group members
      final memberRows = await supa
          .from('friends_group_members')
          .select('user_id')
          .eq('group_id', widget.groupId);

      final memberIds = <String>[];
      if (memberRows is List) {
        for (final row in memberRows) {
          final uid = row['user_id'] as String?;
          if (uid != null) memberIds.add(uid);
        }
      }

      // 3) Load user details for all members
      Map<String, Map<String, dynamic>> userById = {};

      if (memberIds.isNotEmpty) {
        final usersRows = await supa
            .from('users')
            .select('id, full_name, photo_url, base_zip_code')
            .inFilter('id', memberIds);

        for (final u in usersRows as List) {
          final uid = u['id'] as String;
          userById[uid] = Map<String, dynamic>.from(u);
        }
      }

      // 4) Combine members with user details
      final combinedMembers = <Map<String, dynamic>>[];
      for (final uid in memberIds) {
        final u = userById[uid] ?? {};
        combinedMembers.add({
          'user_id': uid,
          'full_name': u['full_name'] as String? ?? 'Unknown',
          'photo_url': u['photo_url'] as String?,
          'base_zip_code': u['base_zip_code'] as String?,
        });
      }

      // Sort members: creator first, then alphabetically
      combinedMembers.sort((a, b) {
        final aIsCreator = a['user_id'] == groupRow['created_by'];
        final bIsCreator = b['user_id'] == groupRow['created_by'];
        if (aIsCreator && !bIsCreator) return -1;
        if (!aIsCreator && bIsCreator) return 1;
        return (a['full_name'] as String)
            .toLowerCase()
            .compareTo((b['full_name'] as String).toLowerCase());
      });

      // 5) Determine if current user is creator
      String? currentUserId = user?.id;
      bool isCreator = currentUserId != null && currentUserId == groupRow['created_by'];

      setState(() {
        _group = Map<String, dynamic>.from(groupRow);
        _members = combinedMembers;
        _isCreator = isCreator;
        _currentUserId = currentUserId;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load group profile: $e')),
      );
    }
  }

  Future<void> _removeMember(String userId, String fullName) async {
    if (_group == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $fullName from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final supa = Supabase.instance.client;
    try {
      await supa
          .from('friends_group_members')
          .delete()
          .match({'group_id': widget.groupId, 'user_id': userId});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $fullName from group')),
      );

      await _loadGroupProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove member: $e')),
      );
    }
  }

  String _toDisplaySport(String storageSport) {
    final withSpaces = storageSport.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? w
              : w[0].toUpperCase() +
                  (w.length > 1 ? w.substring(1).toLowerCase() : ''),
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_group?['name'] as String? ?? widget.groupName),
        actions: _isCreator
            ? [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit group',
                  onPressed: () {
                    // Edit functionality can be added later or navigated to edit screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Edit group from your profile page'),
                      ),
                    );
                  },
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _group == null
              ? const Center(child: Text('Group not found'))
              : RefreshIndicator(
                  onRefresh: _loadGroupProfile,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Group summary card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _group!['name'] as String? ?? 'Unnamed Group',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sport: ${_toDisplaySport(_group!['sport'] as String? ?? '')}',
                              ),
                              Text(
                                '${_members.length} ${_members.length == 1 ? 'member' : 'members'}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Members',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_members.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: Text('No members yet'),
                            ),
                          ),
                        )
                      else
                        ..._members.map((member) {
                          final userId = member['user_id'] as String;
                          final fullName = member['full_name'] as String? ?? 'Unknown';
                          final photoUrl = member['photo_url'] as String?;
                          final isGroupCreator = userId == _group!['created_by'];
                          final isSelf = userId == _currentUserId;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: (photoUrl != null &&
                                        photoUrl.isNotEmpty)
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: (photoUrl == null || photoUrl.isEmpty)
                                    ? Text(
                                        fullName.isNotEmpty
                                            ? fullName[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Expanded(child: Text(fullName)),
                                  if (isGroupCreator)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Created by',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: isSelf
                                  ? const Text(
                                      'You',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  : _isCreator && !isGroupCreator
                                      ? IconButton(
                                          icon: const Icon(Icons.remove_circle_outline),
                                          tooltip: 'Remove from group',
                                          onPressed: () =>
                                              _removeMember(userId, fullName),
                                        )
                                      : null,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                      userId: userId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
    );
  }
}
