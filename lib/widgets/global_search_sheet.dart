import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/user_profile_screen.dart';
import '../screens/team_profile_screen.dart';

/// Opens a bottom sheet that lets you search players & teams
/// by name / ZIP / email / phone (free-text).
Future<void> showGlobalSearchSheet(BuildContext context) async {
  final supa = Supabase.instance.client;
  final searchCtrl = TextEditingController();
  final currentUser = supa.auth.currentUser;
  final currentUserId = currentUser?.id;

  bool searching = false;
  List<Map<String, dynamic>> playerResults = [];
  List<Map<String, dynamic>> teamResults = [];
  
  // Map<otherUserId, relationship: 'accepted' | 'outgoing' | 'incoming' | 'none'>
  final Map<String, String> relationshipByUserId = {};

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> loadFriendRelationships() async {
            if (currentUserId == null) return;
            
            try {
              final relRows = await supa
                  .from('friends')
                  .select('user_id, friend_id, status')
                  .or('user_id.eq.$currentUserId,friend_id.eq.$currentUserId');

              if (relRows is List) {
                for (final r in relRows) {
                  final uid = r['user_id'] as String;
                  final fid = r['friend_id'] as String;
                  final status = (r['status'] as String?) ?? 'pending';

                  if (uid == currentUserId) {
                    final key = fid;
                    if (status == 'accepted') {
                      relationshipByUserId[key] = 'accepted';
                    } else if (status == 'pending') {
                      relationshipByUserId[key] = 'outgoing';
                    }
                  } else if (fid == currentUserId) {
                    final key = uid;
                    if (status == 'accepted') {
                      relationshipByUserId[key] = 'accepted';
                    } else if (status == 'pending') {
                      relationshipByUserId[key] = 'incoming';
                    }
                  }
                }
              }
            } catch (_) {
              // ignore
            }
          }

          Future<void> doSearch() async {
            final term = searchCtrl.text.trim();
            if (term.isEmpty) return;

            setSheetState(() {
              searching = true;
              relationshipByUserId.clear();
              playerResults = [];
              teamResults = [];
            });

            try {
              // Load friend relationships first
              await loadFriendRelationships();

              // ---------- PLAYERS ----------
              var userQuery = supa
                  .from('users')
                  .select(
                      'id, full_name, photo_url, base_zip_code, email, phone');
              
              // Filter out current user if logged in
              if (currentUserId != null) {
                userQuery = userQuery.neq('id', currentUserId);
              }
              
              final userRows = await userQuery.or(
                [
                  "full_name.ilike.%$term%",
                  "base_zip_code.eq.$term",
                  "email.ilike.%$term%",
                  "phone.ilike.%$term%",
                ].join(','),
              );

              final newPlayerResults = (userRows as List)
                  .map<Map<String, dynamic>>((u) => {
                        'id': u['id'] as String,
                        'full_name': u['full_name'] as String? ?? 'Unknown',
                        'photo_url': u['photo_url'] as String?,
                        'zip': u['base_zip_code'] as String?,
                        'email': u['email'] as String?,
                        'phone': u['phone'] as String?,
                      })
                  .toList();

              // ---------- TEAMS ----------
              final teamRows = await supa
                  .from('teams')
                  .select('id, name, sport, zip_code, proficiency_level')
                  .or(
                    [
                      "name.ilike.%$term%",
                      "zip_code.eq.$term",
                    ].join(','),
                  );

              final newTeamResults = (teamRows as List)
                  .map<Map<String, dynamic>>((t) => {
                        'id': t['id'] as String,
                        'name': t['name'] as String? ?? '',
                        'sport': t['sport'] as String? ?? '',
                        'zip': t['zip_code'] as String?,
                        'level': t['proficiency_level'] as String?,
                      })
                  .toList();

              // Update state with results
              setSheetState(() {
                playerResults = newPlayerResults;
                teamResults = newTeamResults;
                searching = false;
              });
            } catch (e) {
              if (Navigator.of(ctx).canPop()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Search failed: $e')),
                );
              }
              setSheetState(() {
                searching = false;
                playerResults = [];
                teamResults = [];
              });
            }
          }

          Future<void> addFriend(String targetUserId, String name) async {
            if (currentUserId == null) return;
            
            try {
              await supa.from('friends').insert({
                'user_id': currentUserId,
                'friend_id': targetUserId,
                'status': 'pending',
              });

              setSheetState(() {
                relationshipByUserId[targetUserId] = 'outgoing';
              });

              if (Navigator.of(ctx).canPop()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Friend request sent to $name'),
                  ),
                );
              }
            } catch (e) {
              if (Navigator.of(ctx).canPop()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add friend: $e')),
                );
              }
            }
          }

          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          final screenHeight = MediaQuery.of(ctx).size.height;

          return Container(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.9,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: bottomInset + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                const Text(
                  'Search players / teams',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'Search a player/team by name or ZIP or email id or phone number',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => doSearch(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: searching ? null : doSearch,
                    child: Text(searching ? 'Searching…' : 'Search'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: screenHeight * 0.5,
                  child: !searching &&
                          playerResults.isEmpty &&
                          teamResults.isEmpty
                      ? const Center(
                          child: Text(
                            'Type a keyword above and tap Search.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )
                      : searching
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                            children: [
                              // ---- PLAYERS ----
                              if (playerResults.isNotEmpty)
                                const Text(
                                  'Players',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ...playerResults.map((p) {
                                final name =
                                    p['full_name'] as String? ?? 'Unknown';
                                final photoUrl = p['photo_url'] as String?;
                                final zip = p['zip'] as String?;
                                final email = p['email'] as String?;
                                final phone = p['phone'] as String?;
                                final userId = p['id'] as String;
                                final relationship = relationshipByUserId[userId] ?? 'none';
                                final isCurrentUser = currentUserId == userId;

                                String subtitle = '';
                                if (zip != null) subtitle += 'ZIP: $zip';
                                if (email != null) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += email;
                                }
                                if (phone != null) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += phone;
                                }

                                Widget? trailing;
                                if (!isCurrentUser) {
                                  if (relationship == 'accepted') {
                                    trailing = const Text(
                                      'Friend',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  } else if (relationship == 'outgoing') {
                                    trailing = const Text(
                                      'Requested',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  } else if (relationship == 'incoming') {
                                    trailing = const Text(
                                      'Request received',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  } else {
                                    trailing = IconButton(
                                      icon: const Icon(Icons.person_add),
                                      tooltip: 'Add friend',
                                      onPressed: () => addFriend(userId, name),
                                    );
                                  }
                                }

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage: (photoUrl != null &&
                                              photoUrl.isNotEmpty)
                                          ? NetworkImage(photoUrl)
                                          : null,
                                      child: (photoUrl == null ||
                                              photoUrl.isEmpty)
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(name),
                                    subtitle: subtitle.isNotEmpty
                                        ? Text(subtitle)
                                        : null,
                                    trailing: trailing,
                                    onTap: () {
                                      Navigator.of(ctx).pop();
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
                              }),

                              const SizedBox(height: 8),

                              // ---- TEAMS ----
                              if (teamResults.isNotEmpty)
                                const Text(
                                  'Teams',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ...teamResults.map((t) {
                                final name =
                                    t['name'] as String? ?? 'Unnamed team';
                                final sport = t['sport'] as String? ?? '';
                                final zip = t['zip'] as String?;
                                final level = t['level'] as String?;
                                final teamId = t['id'] as String;

                                String subtitle = sport;
                                if (level != null && level.isNotEmpty) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += level;
                                }
                                if (zip != null) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += 'ZIP $zip';
                                }

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      child: Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                      ),
                                    ),
                                    title: Text(name),
                                    subtitle: subtitle.isNotEmpty
                                        ? Text(subtitle)
                                        : null,
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TeamProfileScreen(
                                            teamId: teamId,
                                            teamName: name,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
