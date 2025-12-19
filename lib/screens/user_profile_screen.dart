import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/global_search_sheet.dart';

import 'profile_setup_screen.dart';
import 'team_profile_screen.dart';
import 'teams_screen.dart';

class UserProfileScreen extends StatefulWidget {
  /// If null → shows the currently logged-in user's profile.
  /// If non-null → shows that specific user's profile (used when viewing friends).
  final String? userId;

  const UserProfileScreen({super.key, this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _loading = false;
  Map<String, dynamic>? _userRow;
  List<String> _sports = [];
  int _teamsCount = 0;
  String? _baseCity;
  String? _baseState;
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _friendsGroups = [];

  String? _effectiveUserId; // profile being viewed
  String? _currentUserId; // logged-in user
  bool _isSelf = false;

  // Relationship between logged-in user and profile user
  // 'none' | 'accepted' | 'outgoing' | 'incoming'
  String _friendRelationship = 'none';
  String? _friendRequestIdForProfile; // request row id when pending

  // simple list of sports to choose from when creating a team or editing interests
  final List<String> _allSportsOptions = [
    'badminton',
    'cricket',
    'pickleball',
    'tennis',
    'table_tennis',
    'basketball',
    'volleyball',
    'soccer',
    'football',
  ];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final supa = Supabase.instance.client;
    final authUser = supa.auth.currentUser;

    _currentUserId = authUser?.id;

    if (widget.userId != null) {
      _effectiveUserId = widget.userId;
      _isSelf = authUser != null && authUser.id == widget.userId;
    } else {
      _effectiveUserId = authUser?.id;
      _isSelf = true;
    }

    if (_effectiveUserId == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    await _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (_effectiveUserId == null) return;

    setState(() => _loading = true);

    final supa = Supabase.instance.client;
    final userId = _effectiveUserId!;

    try {
      // 1) Load main user row
      final userRow = await supa
          .from('users')
          .select('id, full_name, base_zip_code, photo_url')
          .eq('id', userId)
          .maybeSingle();

      // 2) Load sports interests
      final sportsRows = await supa
          .from('user_sports')
          .select('sport')
          .eq('user_id', userId);

      final sports = (sportsRows as List)
          .map<String>((row) => row['sport'] as String)
          .toList();

      // 3) Load team memberships
      final membershipRows = await supa
          .from('team_members')
          .select('team_id, role')
          .eq('user_id', userId);

      final teamsCount = (membershipRows as List).length;

      // 4) Load team details
      List<Map<String, dynamic>> teams = [];
      if (membershipRows.isNotEmpty) {
        final teamIds =
            membershipRows.map<String>((m) => m['team_id'] as String).toList();

        if (teamIds.isNotEmpty) {
          final teamsRows = await supa
              .from('teams')
              .select(
                'id, name, sport, proficiency_level, zip_code, team_number',
              )
              .inFilter('id', teamIds);

          final Map<String, String> roleByTeamId = {};
          for (final m in membershipRows) {
            roleByTeamId[m['team_id'] as String] =
                m['role'] as String? ?? 'member';
          }

          teams = (teamsRows as List).map<Map<String, dynamic>>((row) {
            final id = row['id'] as String;
            return {
              'id': id,
              'name': row['name'] as String? ?? '',
              'sport': row['sport'] as String? ?? '',
              'proficiency_level': row['proficiency_level'] as String?,
              'zip_code': row['zip_code'] as String?,
              'team_number': row['team_number'],
              'role': roleByTeamId[id] ?? 'member',
            };
          }).toList();

          // Sort: admin → member
          teams.sort((a, b) {
            const rank = {'admin': 0, 'member': 1};
            final ra =
                rank[(a['role'] as String?)?.toLowerCase() ?? 'member'] ?? 2;
            final rb =
                rank[(b['role'] as String?)?.toLowerCase() ?? 'member'] ?? 2;
            return ra.compareTo(rb);
          });
        }
      }

      // 5) City / State via zip_codes
      String? baseCity;
      String? baseState;
      final baseZip = (userRow?['base_zip_code'] as String?)?.trim();
      if (baseZip != null && baseZip.isNotEmpty) {
        final zipRow = await supa
            .from('zip_codes')
            .select('city, state')
            .eq('zip', baseZip)
            .maybeSingle();

        if (zipRow != null) {
          baseCity = zipRow['city'] as String?;
          baseState = zipRow['state'] as String?;
        }
      }

      // 6) Accepted friends (bidirectional) — for listing
      final outgoingRows = await supa
          .from('friends')
          .select('friend_id')
          .eq('user_id', userId)
          .eq('status', 'accepted');

      final incomingRows = await supa
          .from('friends')
          .select('user_id')
          .eq('friend_id', userId)
          .eq('status', 'accepted');

      final friendIds = <String>{};

      if (outgoingRows is List) {
        for (final row in outgoingRows) {
          final fid = row['friend_id'] as String?;
          if (fid != null) friendIds.add(fid);
        }
      }

      if (incomingRows is List) {
        for (final row in incomingRows) {
          final uid = row['user_id'] as String?;
          if (uid != null) friendIds.add(uid);
        }
      }

      List<Map<String, dynamic>> friends = [];
      if (friendIds.isNotEmpty) {
        final friendUsers = await supa
            .from('users')
            .select('id, full_name, photo_url, base_zip_code')
            .inFilter('id', friendIds.toList());

        friends = (friendUsers as List)
            .map<Map<String, dynamic>>((u) => {
                  'id': u['id'] as String,
                  'full_name': u['full_name'] as String? ?? 'Unknown',
                  'photo_url': u['photo_url'] as String?,
                  'base_zip_code': u['base_zip_code'] as String?,
                })
            .toList();

        friends.sort((a, b) {
          final na = (a['full_name'] as String).toLowerCase();
          final nb = (b['full_name'] as String).toLowerCase();
          return na.compareTo(nb);
        });
      }

      // 7) Incoming pending friend requests (only meaningful when viewing self)
      final pendingRows = await supa
          .from('friends')
          .select('id, user_id, created_at')
          .eq('friend_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> incomingRequests = [];
      if (pendingRows is List && pendingRows.isNotEmpty) {
        final requesterIds =
            pendingRows.map<String>((r) => r['user_id'] as String).toList();

        final requesterUsers = await supa
            .from('users')
            .select('id, full_name, photo_url, base_zip_code')
            .inFilter('id', requesterIds);

        final Map<String, Map<String, dynamic>> userById = {};
        for (final u in requesterUsers as List) {
          userById[u['id'] as String] = Map<String, dynamic>.from(u);
        }

        for (final r in pendingRows) {
          final uid = r['user_id'] as String;
          final u = userById[uid];
          if (u != null) {
            incomingRequests.add({
              'request_id': r['id'] as String,
              'user_id': uid,
              'full_name': u['full_name'] as String? ?? 'Unknown',
              'photo_url': u['photo_url'] as String?,
              'base_zip_code': u['base_zip_code'] as String?,
            });
          }
        }
      }

      // 8) Relationship between logged-in user and the profile user
      String relationship = 'none';
      String? relReqId;

      if (_currentUserId != null && _currentUserId != userId) {
        // Case 1: I sent request to them (or already friend)
        final r1 = await supa
            .from('friends')
            .select('id, status')
            .eq('user_id', _currentUserId!)
            .eq('friend_id', userId)
            .maybeSingle();

        // Case 2: They sent request to me (or already friend)
        final r2 = await supa
            .from('friends')
            .select('id, status')
            .eq('user_id', userId)
            .eq('friend_id', _currentUserId!)
            .maybeSingle();

        if (r1 != null || r2 != null) {
          final row = r1 ?? r2!;
          final status = (row['status'] as String?) ?? 'pending';
          if (status == 'accepted') {
            relationship = 'accepted';
          } else {
            // pending
            if (r1 != null) {
              relationship = 'outgoing'; // I sent
            } else {
              relationship = 'incoming'; // they sent
            }
            relReqId = row['id'] as String?;
          }
        }
      }

      setState(() {
        _userRow = userRow != null ? Map<String, dynamic>.from(userRow) : null;
        _sports = sports;
        _teamsCount = teamsCount;
        _baseCity = baseCity;
        _baseState = baseState;
        _teams = teams;
        _friends = friends;
        _incomingRequests = incomingRequests;
        _friendRelationship = relationship;
        _friendRequestIdForProfile = relReqId;
        
        // 8) Load friends groups (only for self)
        if (_isSelf) {
          final groupsRows = await supa
              .from('friends_groups')
              .select('id, name, created_by')
              .or('created_by.eq.$userId,id.in.(select group_id from friends_group_members where user_id.eq.$userId)')
              .order('name');
          
          List<Map<String, dynamic>> groups = [];
          if (groupsRows is List) {
            for (final g in groupsRows) {
              // Get member count for each group
              final memberRows = await supa
                  .from('friends_group_members')
                  .select('id')
                  .eq('group_id', g['id']);
              
              groups.add({
                'id': g['id'],
                'name': g['name'],
                'created_by': g['created_by'],
                'member_count': memberRows is List ? memberRows.length : 0,
              });
            }
          }
          _friendsGroups = groups;
        }
        
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
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

  String? _roleLabel(String role) {
    final lower = role.toLowerCase();
    if (lower == 'admin') {
      return 'Admin';
    }
    return null; // Don't show label for members
  }

  Color? _roleColor(String role) {
    final lower = role.toLowerCase();
    if (lower == 'admin') {
      return Colors.blue;
    }
    return null; // No color for members
  }

  Future<void> _logout() async {
    final supa = Supabase.instance.client;
    try {
      await supa.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to logout: $e')),
      );
    }
  }

  /// Remove friend when you are viewing your own profile (used in Friends list).
  Future<void> _removeFriend(
    String friendUserId,
    String friendName,
  ) async {
    final supa = Supabase.instance.client;
    final currentUserId = _effectiveUserId;
    if (currentUserId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text('Remove $friendName from your friends list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supa
          .from('friends')
          .delete()
          .match({'user_id': currentUserId, 'friend_id': friendUserId});
      await supa
          .from('friends')
          .delete()
          .match({'user_id': friendUserId, 'friend_id': currentUserId});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $friendName from friends')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove friend: $e')),
      );
    }
  }

  /// Generic friend request responder (used for "Friend Requests" list).
  Future<void> _respondToFriendRequest(
    String requestId,
    String requesterName,
    bool accept,
  ) async {
    final supa = Supabase.instance.client;

    try {
      if (accept) {
        await supa
            .from('friends')
            .update({'status': 'accepted'}).eq('id', requestId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You are now friends with $requesterName')),
          );
        }
      } else {
        await supa.from('friends').delete().eq('id', requestId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Declined request from $requesterName')),
          );
        }
      }

      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update request: $e')),
      );
    }
  }

  /// Remove friend from the header when viewing someone else's profile.
  Future<void> _removeFriendWithProfileUser() async {
    final myId = _currentUserId;
    final otherId = _effectiveUserId;
    final name = (_userRow?['full_name'] as String?) ?? 'this player';
    if (myId == null || otherId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text('Remove $name from your friends list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final supa = Supabase.instance.client;
    try {
      await supa
          .from('friends')
          .delete()
          .match({'user_id': myId, 'friend_id': otherId});
      await supa
          .from('friends')
          .delete()
          .match({'user_id': otherId, 'friend_id': myId});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $name from friends')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove friend: $e')),
      );
    }
  }

  /// Send friend request from header when viewing someone else's profile.
  Future<void> _sendFriendRequestToProfileUser() async {
    final myId = _currentUserId;
    final otherId = _effectiveUserId;
    final name = (_userRow?['full_name'] as String?) ?? 'this player';
    if (myId == null || otherId == null) return;

    final supa = Supabase.instance.client;
    try {
      await supa.from('friends').insert({
        'user_id': myId,
        'friend_id': otherId,
        'status': 'pending',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to $name')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send request: $e')),
      );
    }
  }

  /// Cancel a pending outgoing friend request from header.
  Future<void> _cancelFriendRequestToProfileUser() async {
    final reqId = _friendRequestIdForProfile;
    if (reqId == null) return;

    final name = (_userRow?['full_name'] as String?) ?? 'this player';
    final supa = Supabase.instance.client;
    try {
      await supa.from('friends').delete().eq('id', reqId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancelled friend request to $name')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel request: $e')),
      );
    }
  }

  Future<void> _showManageFriendsSheet() async {
    final supa = Supabase.instance.client;
    final currentUserId = _effectiveUserId;
    if (currentUserId == null) return;

    final nameCtrl = TextEditingController();
    final zipCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    List<Map<String, dynamic>> results = [];
    bool searching = false;

    // Map<otherUserId, relationship: 'accepted' | 'outgoing' | 'incoming'>
    final Map<String, String> relationshipByUserId = {};

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
      // ignore for now
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> doSearch() async {
              final name = nameCtrl.text.trim();
              final zip = zipCtrl.text.trim();
              final email = emailCtrl.text.trim();
              final phone = phoneCtrl.text.trim();

              setSheetState(() => searching = true);
              try {
                var query = supa
                    .from('users')
                    .select(
                        'id, full_name, photo_url, base_zip_code, email, phone')
                    .neq('id', currentUserId);

                if (name.isNotEmpty) {
                  query = query.ilike('full_name', '%$name%');
                }
                if (zip.isNotEmpty) {
                  query = query.eq('base_zip_code', zip);
                }
                if (email.isNotEmpty) {
                  query = query.ilike('email', '%$email%');
                }
                if (phone.isNotEmpty) {
                  query = query.ilike('phone', '%$phone%');
                }

                final rows = await query;
                results = (rows as List)
                    .map<Map<String, dynamic>>((u) => {
                          'id': u['id'] as String,
                          'full_name':
                              u['full_name'] as String? ?? 'Unknown',
                          'photo_url': u['photo_url'] as String?,
                          'base_zip_code': u['base_zip_code'] as String?,
                          'email': u['email'] as String?,
                          'phone': u['phone'] as String?,
                        })
                    .toList();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Search failed: $e')),
                  );
                }
              } finally {
                setSheetState(() => searching = false);
              }
            }

            Future<void> addFriend(String targetUserId, String name) async {
              try {
                await supa.from('friends').insert({
                  'user_id': currentUserId,
                  'friend_id': targetUserId,
                  'status': 'pending',
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Friend request sent to $name'),
                    ),
                  );
                  await _loadProfile();
                }

                setSheetState(() {
                  relationshipByUserId[targetUserId] = 'outgoing';
                });
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add friend: $e')),
                  );
                }
              }
            }

            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: bottomInset + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Add new friends',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search by name',
                      prefixIcon: Icon(Icons.person_search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      prefixIcon: Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: zipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ZIP (optional)',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: searching ? null : doSearch,
                      icon: const Icon(Icons.search),
                      label:
                          Text(searching ? 'Searching...' : 'Search'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (results.isEmpty && !searching)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Search players by name, email, phone or ZIP to add as friends.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 260,
                      child: searching
                          ? const Center(
                              child: CircularProgressIndicator(),
                            )
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (ctx, idx) {
                                final r = results[idx];
                                final id = r['id'] as String;
                                final name =
                                    r['full_name'] as String? ?? 'Unknown';
                                final photoUrl =
                                    r['photo_url'] as String?;
                                final zip =
                                    r['base_zip_code'] as String?;
                                final email =
                                    r['email'] as String?;
                                final phone =
                                    r['phone'] as String?;
                                final rel =
                                    relationshipByUserId[id];

                                Widget trailing;
                                if (rel == 'accepted') {
                                  trailing = const Text(
                                    'Friend',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                } else if (rel == 'outgoing') {
                                  trailing = const Text(
                                    'Requested',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                } else if (rel == 'incoming') {
                                  trailing = const Text(
                                    'Request received',
                                    style: TextStyle(
                                      color: Colors.blueGrey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                } else {
                                  trailing = IconButton(
                                    icon: const Icon(
                                        Icons.person_add_alt_1),
                                    onPressed: () =>
                                        addFriend(id, name),
                                  );
                                }

                                final subtitleParts = <String>[];
                                if (zip != null) {
                                  subtitleParts.add('ZIP: $zip');
                                }
                                if (email != null &&
                                    email.isNotEmpty) {
                                  subtitleParts.add(email);
                                }
                                if (phone != null &&
                                    phone.isNotEmpty) {
                                  subtitleParts.add(phone);
                                }

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage:
                                          (photoUrl != null &&
                                                  photoUrl.isNotEmpty)
                                              ? NetworkImage(photoUrl)
                                              : null,
                                      child: (photoUrl == null ||
                                              photoUrl.isEmpty)
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0]
                                                      .toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(name),
                                    subtitle: subtitleParts.isEmpty
                                        ? null
                                        : Text(
                                            subtitleParts.join(' • '),
                                          ),
                                    trailing: trailing,
                                  ),
                                );
                              },
                            ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateTeamSheet() async {
    final supa = Supabase.instance.client;
    final rootContext = context;
    final creatorId = _currentUserId;
    if (creatorId == null) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(content: Text('You must be logged in to create a team')),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final zipCtrl = TextEditingController(
      text: (_userRow?['base_zip_code'] as String?) ?? '',
    );
    final descCtrl = TextEditingController();
    String? selectedSport;
    String? selectedLevel;
    String? errorText;
    bool saving = false;

    await showModalBottomSheet(
      context: rootContext,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        final bottomInset = MediaQuery.of(bottomSheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> submit() async {
              final teamName = nameCtrl.text.trim();
              final zip = zipCtrl.text.trim();
              final desc = descCtrl.text.trim();

              if (selectedSport == null ||
                  teamName.isEmpty ||
                  zip.isEmpty) {
                setSheetState(() {
                  errorText =
                      'Sport, Team name and ZIP code are required.';
                });
                return;
              }

              setSheetState(() {
                saving = true;
                errorText = null;
              });

              try {
                // 1) Insert team
                final insertRes = await supa
                    .from('teams')
                    .insert({
                      'name': teamName,
                      'sport': selectedSport,
                      'zip_code': zip,
                      'description': desc.isEmpty ? null : desc,
                      'proficiency_level': selectedLevel,
                      'created_by': creatorId,
                    })
                    .select('id')
                    .maybeSingle();

                final teamId = insertRes?['id'] as String?;
                if (teamId == null) {
                  throw Exception('Failed to create team (no ID returned)');
                }

                // 2) Add creator as admin
                await supa.from('team_members').insert({
                  'team_id': teamId,
                  'user_id': creatorId,
                  'role': 'admin',
                });

                if (!mounted) return;

                Navigator.of(bottomSheetContext).pop();
                await _loadProfile();

                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    content: Text('Team "$teamName" created'),
                  ),
                );
              } catch (e) {
                setSheetState(() {
                  saving = false;
                  errorText = 'Failed to create team: $e';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: bottomInset + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Create a Team',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Sport dropdown
                    DropdownButtonFormField<String>(
                      value: selectedSport,
                      decoration: const InputDecoration(
                        labelText: 'Sport *',
                        prefixIcon: Icon(Icons.sports),
                      ),
                      items: _allSportsOptions
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(_toDisplaySport(s)),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setSheetState(() {
                          selectedSport = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Team name
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Team name *',
                        prefixIcon: Icon(Icons.group),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ZIP
                    TextField(
                      controller: zipCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Team ZIP code *',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),

                    // Proficiency level
                    DropdownButtonFormField<String>(
                      value: selectedLevel,
                      decoration: const InputDecoration(
                        labelText: 'Proficiency level (optional)',
                        prefixIcon: Icon(Icons.bar_chart),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'casual',
                          child: Text('Casual / Social'),
                        ),
                        DropdownMenuItem(
                          value: 'intermediate',
                          child: Text('Intermediate'),
                        ),
                        DropdownMenuItem(
                          value: 'competitive',
                          child: Text('Competitive'),
                        ),
                      ],
                      onChanged: (val) {
                        setSheetState(() {
                          selectedLevel = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Description
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          errorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.of(bottomSheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: saving ? null : submit,
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(saving ? 'Creating...' : 'Create'),
                        ),
                      ],
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

  /// NEW: bottom sheet to add / edit sports interested.
  Future<void> _showSportsInterestSheet() async {
    final supa = Supabase.instance.client;
    final userId = _effectiveUserId;
    if (userId == null) return;

    // start with current sports selected
    List<String> selectedSports = List<String>.from(_sports);
    bool saving = false;
    String? errorText;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> saveSports() async {
              setSheetState(() {
                saving = true;
                errorText = null;
              });

              try {
                // 1) delete existing rows
                await supa
                    .from('user_sports')
                    .delete()
                    .eq('user_id', userId);

                // 2) insert selected sports
                if (selectedSports.isNotEmpty) {
                  final rows = selectedSports
                      .map((s) => {
                            'user_id': userId,
                            'sport': s,
                          })
                      .toList();
                  await supa.from('user_sports').insert(rows);
                }

                if (!mounted) return;
                Navigator.of(sheetContext).pop();
                await _loadProfile();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sports interests updated'),
                  ),
                );
              } catch (e) {
                setSheetState(() {
                  saving = false;
                  errorText = 'Failed to update sports: $e';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: bottomInset + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select your sports',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose all sports you play or are interested in.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._allSportsOptions.map((sport) {
                      final isSelected = selectedSports.contains(sport);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Text(_toDisplaySport(sport)),
                        dense: true,
                        onChanged: (checked) {
                          setSheetState(() {
                            if (checked == true) {
                              if (!selectedSports.contains(sport)) {
                                selectedSports.add(sport);
                              }
                            } else {
                              selectedSports.remove(sport);
                            }
                          });
                        },
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          errorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: saving ? null : saveSports,
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(saving ? 'Saving...' : 'Save'),
                        ),
                      ],
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

  // ========== FRIENDS GROUPS MANAGEMENT ==========
  
  Future<void> _showCreateFriendsGroupDialog() async {
    final nameController = TextEditingController();
    final selectedFriendIds = <String>{};

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Friends Group'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select friends to add:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: _friends.isEmpty
                          ? const Center(
                              child: Text('No friends to add'),
                            )
                          : ListView.builder(
                              itemCount: _friends.length,
                              itemBuilder: (context, index) {
                                final friend = _friends[index];
                                final friendId = friend['id'] as String;
                                final friendName = friend['full_name'] as String? ?? 'Unknown';
                                final isSelected = selectedFriendIds.contains(friendId);

                                return CheckboxListTile(
                                  title: Text(friendName),
                                  value: isSelected,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedFriendIds.add(friendId);
                                      } else {
                                        selectedFriendIds.remove(friendId);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a group name')),
                      );
                      return;
                    }

                    await _createFriendsGroup(
                      nameController.text.trim(),
                      selectedFriendIds.toList(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createFriendsGroup(String name, List<String> friendIds) async {
    final supa = Supabase.instance.client;
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      // Create group
      final groupResult = await supa
          .from('friends_groups')
          .insert({'name': name, 'created_by': userId})
          .select('id')
          .maybeSingle();

      final groupId = groupResult?['id'] as String?;
      if (groupId == null) {
        throw Exception('Failed to create group');
      }

      // Add members
      if (friendIds.isNotEmpty) {
        final memberRecords = friendIds.map((friendId) => {
          'group_id': groupId,
          'user_id': friendId,
          'added_by': userId,
        }).toList();

        await supa.from('friends_group_members').insert(memberRecords);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friends group created!')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create group: $e')),
      );
    }
  }

  Future<void> _showEditFriendsGroupDialog(Map<String, dynamic> group) async {
    final groupId = group['id'] as String;
    final nameController = TextEditingController(text: group['name'] as String? ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Friends Group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a group name')),
                );
                return;
              }

              await _updateFriendsGroup(groupId, nameController.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateFriendsGroup(String groupId, String name) async {
    final supa = Supabase.instance.client;
    try {
      await supa
          .from('friends_groups')
          .update({'name': name})
          .eq('id', groupId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group updated!')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update group: $e')),
      );
    }
  }

  Future<void> _leaveFriendsGroup(String groupId, String groupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group?'),
        content: Text('Are you sure you want to leave "$groupName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final supa = Supabase.instance.client;
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      await supa
          .from('friends_group_members')
          .delete()
          .match({'group_id': groupId, 'user_id': userId});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Left "$groupName"')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    }
  }

  Future<void> _showFriendsGroupDetails(Map<String, dynamic> group) async {
    final groupId = group['id'] as String;
    final groupName = group['name'] as String? ?? 'Unnamed Group';
    final isCreator = group['created_by'] as String? == _currentUserId;

    final supa = Supabase.instance.client;
    
    // Load members
    final membersRows = await supa
        .from('friends_group_members')
        .select('user_id')
        .eq('group_id', groupId);

    final memberIds = <String>[];
    if (membersRows is List) {
      for (final row in membersRows) {
        final uid = row['user_id'] as String?;
        if (uid != null) memberIds.add(uid);
      }
    }

    // Load user details
    final users = memberIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('users')
            .select('id, full_name, photo_url')
            .inFilter('id', memberIds);

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(groupName),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (users is List && users.isNotEmpty)
                ...users.map((user) {
                  final userId = user['id'] as String;
                  final userName = user['full_name'] as String? ?? 'Unknown';
                  final photoUrl = user['photo_url'] as String?;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl == null || photoUrl.isEmpty
                          ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?')
                          : null,
                    ),
                    title: Text(userName),
                    trailing: isCreator && userId != _currentUserId
                        ? IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () async {
                              await supa
                                  .from('friends_group_members')
                                  .delete()
                                  .match({'group_id': groupId, 'user_id': userId});
                              if (context.mounted) {
                                Navigator.pop(context);
                                await _showFriendsGroupDetails(group);
                              }
                            },
                          )
                        : null,
                  );
                }).toList()
              else
                const Text('No members yet'),
              if (isCreator) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.person_add),
                  title: const Text('Add Members'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _showAddMembersToGroup(group);
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddMembersToGroup(Map<String, dynamic> group) async {
    final groupId = group['id'] as String;
    final selectedFriendIds = <String>{};

    // Get current members
    final supa = Supabase.instance.client;
    final currentMembersRows = await supa
        .from('friends_group_members')
        .select('user_id')
        .eq('group_id', groupId);

    final currentMemberIds = <String>{};
    if (currentMembersRows is List) {
      for (final row in currentMembersRows) {
        final uid = row['user_id'] as String?;
        if (uid != null) currentMemberIds.add(uid);
      }
    }

    // Filter out current members from friends list
    final availableFriends = _friends.where((f) {
      final friendId = f['id'] as String;
      return !currentMemberIds.contains(friendId);
    }).toList();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Members'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (availableFriends.isEmpty)
                      const Text('All friends are already in this group')
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: availableFriends.length,
                          itemBuilder: (context, index) {
                            final friend = availableFriends[index];
                            final friendId = friend['id'] as String;
                            final friendName = friend['full_name'] as String? ?? 'Unknown';
                            final isSelected = selectedFriendIds.contains(friendId);

                            return CheckboxListTile(
                              title: Text(friendName),
                              value: isSelected,
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedFriendIds.add(friendId);
                                  } else {
                                    selectedFriendIds.remove(friendId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedFriendIds.isEmpty
                      ? null
                      : () async {
                          await _addMembersToGroup(groupId, selectedFriendIds.toList());
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addMembersToGroup(String groupId, List<String> friendIds) async {
    final supa = Supabase.instance.client;
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final memberRecords = friendIds.map((friendId) => {
        'group_id': groupId,
        'user_id': friendId,
        'added_by': userId,
      }).toList();

      await supa.from('friends_group_members').insert(memberRecords);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${friendIds.length} member(s)')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add members: $e')),
      );
    }
  }

  /// Friend action bar when viewing someone else's profile.
  Widget _buildFriendHeaderAction() {
    if (_isSelf || _currentUserId == null || _effectiveUserId == null) {
      return const SizedBox.shrink();
    }

    final displayName = (_userRow?['full_name'] as String?) ?? 'Player';

    switch (_friendRelationship) {
      case 'accepted':
        return Row(
          children: [
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.check_circle, color: Colors.green),
              label: const Text('Friends'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _removeFriendWithProfileUser,
              child: const Text('Remove'),
            ),
          ],
        );

      case 'outgoing':
        return Row(
          children: [
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.hourglass_top, color: Colors.orange),
              label: const Text('Request sent'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _cancelFriendRequestToProfileUser,
              child: const Text('Cancel'),
            ),
          ],
        );

      case 'incoming':
        return Row(
          children: [
            ElevatedButton(
              onPressed: _friendRequestIdForProfile == null
                  ? null
                  : () => _respondToFriendRequest(
                        _friendRequestIdForProfile!,
                        displayName,
                        true,
                      ),
              child: const Text('Accept'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _friendRequestIdForProfile == null
                  ? null
                  : () => _respondToFriendRequest(
                        _friendRequestIdForProfile!,
                        displayName,
                        false,
                      ),
              child: const Text('Decline'),
            ),
          ],
        );

      case 'none':
      default:
        return OutlinedButton.icon(
          onPressed: _sendFriendRequestToProfileUser,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add friend'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final supa = Supabase.instance.client;
    final authUser = supa.auth.currentUser;

    // Group teams by sport for UI
    final Map<String, List<Map<String, dynamic>>> teamsBySport = {};
    for (final t in _teams) {
      final key = (t['sport'] as String? ?? '').toString();
      teamsBySport.putIfAbsent(key, () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelf ? 'My Profile' : 'Player Profile'),
        actions: [
          // 🔍 Global search from profile
          IconButton(
            tooltip:
                'Search a player/team by name or ZIP or email id or phone number',
            icon: const Icon(Icons.search),
            onPressed: () => showGlobalSearchSheet(context),
          ),
          if (_isSelf)
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfileSetupScreen(),
                  ),
                );
                if (!mounted) return;
                await _loadProfile();
              },
            ),
          if (_isSelf)
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _userRow == null
              ? const Center(
                  child: Text('No profile found.'),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Header card
                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Avatar
                                      CircleAvatar(
                                        radius: 38,
                                        backgroundImage:
                                            (_userRow!['photo_url']
                                                        as String?)
                                                    ?.isNotEmpty ==
                                                true
                                                ? NetworkImage(
                                                    _userRow!['photo_url']
                                                        as String,
                                                  )
                                                : null,
                                        child: ((_userRow!['photo_url']
                                                        as String?)
                                                    ?.isEmpty ??
                                                true)
                                            ? Text(
                                                (_userRow!['full_name']
                                                            as String?)
                                                        ?.isNotEmpty ==
                                                    true
                                                    ? (_userRow![
                                                                'full_name']
                                                            as String)[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  fontSize: 28,
                                                  fontWeight:
                                                      FontWeight.bold,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (_userRow!['full_name']
                                                          as String?) ??
                                                  'No Name',
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight:
                                                    FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (_isSelf &&
                                                authUser?.email != null)
                                              Text(
                                                authUser!.email!,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            Text(
                                              () {
                                                final zip =
                                                    _userRow![
                                                        'base_zip_code'];
                                                if (zip == null ||
                                                    (zip as String)
                                                        .isEmpty) {
                                                  return 'Location: -';
                                                }
                                                final locParts = <String>[];
                                                locParts
                                                    .add(zip as String);
                                                if (_baseCity != null &&
                                                    _baseCity!
                                                        .isNotEmpty) {
                                                  if (_baseState !=
                                                          null &&
                                                      _baseState!
                                                          .isNotEmpty) {
                                                    locParts.add(
                                                        '$_baseCity, $_baseState');
                                                  } else {
                                                    locParts
                                                        .add(_baseCity!);
                                                  }
                                                }
                                                return 'Location: ${locParts.join(' • ')}';
                                              }(),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.groups,
                                                  size: 16,
                                                  color: Colors
                                                      .blueGrey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Teams: $_teamsCount',
                                                  style:
                                                      const TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        Colors.blueGrey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!_isSelf) ...[
                                    const SizedBox(height: 12),
                                    _buildFriendHeaderAction(),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Sports interests header + button
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Sports Interests',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              if (_isSelf)
                                TextButton.icon(
                                  onPressed: _showSportsInterestSheet,
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Add / edit sports'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_sports.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'No sports selected yet.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _sports
                                  .map(
                                    (s) => Chip(
                                      label: Text(_toDisplaySport(s)),
                                      avatar: const Icon(
                                        Icons.sports,
                                        size: 16,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),

                          const SizedBox(height: 24),

                          // Friend requests (self only)
                          if (_isSelf && _incomingRequests.isNotEmpty) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Friend Requests',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Column(
                              children: _incomingRequests.map((r) {
                                final name =
                                    r['full_name'] as String? ??
                                        'Unknown';
                                final photoUrl =
                                    r['photo_url'] as String?;
                                final zip =
                                    r['base_zip_code'] as String?;
                                final reqId =
                                    r['request_id'] as String;

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage:
                                          (photoUrl != null &&
                                                  photoUrl.isNotEmpty)
                                              ? NetworkImage(photoUrl)
                                              : null,
                                      child: (photoUrl == null ||
                                              photoUrl.isEmpty)
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0]
                                                      .toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(name),
                                    subtitle: zip != null
                                        ? Text('ZIP: $zip')
                                        : null,
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        TextButton(
                                          onPressed: () =>
                                              _respondToFriendRequest(
                                            reqId,
                                            name,
                                            false,
                                          ),
                                          child: const Text('Decline'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              _respondToFriendRequest(
                                            reqId,
                                            name,
                                            true,
                                          ),
                                          child: const Text('Accept'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Friends section
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Friends',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              if (_isSelf)
                                TextButton.icon(
                                  onPressed: _showManageFriendsSheet,
                                  icon: const Icon(
                                    Icons.person_add_alt_1,
                                    size: 18,
                                  ),
                                  label: const Text('Add new friends'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_friends.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'No friends added yet.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          else
                            Column(
                              children: _friends.map((f) {
                                final name =
                                    f['full_name'] as String? ??
                                        'Unknown';
                                final photoUrl =
                                    f['photo_url'] as String?;
                                final zip =
                                    f['base_zip_code'] as String?;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage:
                                          (photoUrl != null &&
                                                  photoUrl.isNotEmpty)
                                              ? NetworkImage(photoUrl)
                                              : null,
                                      child: (photoUrl == null ||
                                              photoUrl.isEmpty)
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0]
                                                      .toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(name),
                                    subtitle: zip != null
                                        ? Text('ZIP: $zip')
                                        : null,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              UserProfileScreen(
                                            userId:
                                                f['id'] as String,
                                          ),
                                        ),
                                      );
                                    },
                                    trailing: _isSelf
                                        ? IconButton(
                                            tooltip: 'Remove friend',
                                            icon: const Icon(
                                              Icons.person_remove,
                                            ),
                                            onPressed: () =>
                                                _removeFriend(
                                              f['id'] as String,
                                              name,
                                            ),
                                          )
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),

                          const SizedBox(height: 24),

                          // Friends Groups section (self only)
                          if (_isSelf) ...[
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Friends Groups',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                TextButton.icon(
                                  onPressed: _showCreateFriendsGroupDialog,
                                  icon: const Icon(
                                    Icons.group_add,
                                    size: 18,
                                  ),
                                  label: const Text('Create Group'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_friendsGroups.isEmpty)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'No friends groups yet. Create one to easily invite multiple friends to games!',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            else
                              Column(
                                children: _friendsGroups.map((group) {
                                  final groupId = group['id'] as String;
                                  final groupName = group['name'] as String? ?? 'Unnamed Group';
                                  final memberCount = group['member_count'] as int? ?? 0;
                                  final isCreator = group['created_by'] as String? == _effectiveUserId;

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade100,
                                        child: Icon(
                                          Icons.group,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      title: Text(
                                        groupName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            tooltip: 'Edit group',
                                            onPressed: () => _showEditFriendsGroupDialog(group),
                                          ),
                                          if (!isCreator)
                                            IconButton(
                                              icon: const Icon(Icons.exit_to_app),
                                              tooltip: 'Leave group',
                                              onPressed: () => _leaveFriendsGroup(groupId, groupName),
                                            ),
                                        ],
                                      ),
                                      onTap: () => _showFriendsGroupDetails(group),
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 24),
                          ],

                          // Teams section (grouped by sport)
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Teams',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              if (_isSelf)
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const TeamsScreen(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.group_add,
                                    size: 18,
                                  ),
                                  label: const Text('Manage'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // "Create your team" card
                          if (_isSelf)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              color: Colors.green.shade50,
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.green,
                                  child: Icon(
                                    Icons.add,
                                    color: Colors.white,
                                  ),
                                ),
                                title: const Text(
                                  'Create your team',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Set up a new team for your sport and invite players.',
                                ),
                                onTap: _showCreateTeamSheet,
                              ),
                            ),

                          if (_teams.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'This player is not part of any team yet.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          else
                            Column(
                              children:
                                  teamsBySport.entries.map((entry) {
                                final sportKey = entry.key;
                                final sportTeams = entry.value;

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.sports,
                                          size: 18,
                                          color: Colors.black87,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _toDisplaySport(sportKey),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ...sportTeams.map((t) {
                                      final role =
                                          (t['role'] as String?) ??
                                              'member';
                                      final roleText =
                                          _roleLabel(role);
                                      final roleColor =
                                          _roleColor(role);

                                      return Card(
                                        margin:
                                            const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            child: Text(
                                              (t['name']
                                                              as String?)
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? (t['name']
                                                          as String)[0]
                                                      .toUpperCase()
                                                  : '?',
                                            ),
                                          ),
                                          title: Text(
                                            t['name'] as String? ?? '',
                                          ),
                                          subtitle: Text(
                                            '${_toDisplaySport(t['sport'] as String? ?? '')}'
                                            ' • ${t['proficiency_level'] ?? 'N/A'}'
                                            ' • ZIP ${t['zip_code'] ?? '-'}',
                                          ),
                                          trailing: roleText != null && roleColor != null
                                              ? Chip(
                                                  label: Text(
                                                    roleText!,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  backgroundColor: roleColor!,
                                                )
                                              : null,
                                          onTap: () {
                                            Navigator.of(context)
                                                .push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    TeamProfileScreen(
                                                  teamId:
                                                      t['id'] as String,
                                                  teamName: t['name']
                                                          as String? ??
                                                      '',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                );
                              }).toList(),
                            ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
