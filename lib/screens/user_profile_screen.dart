import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';
import '../widgets/global_search_sheet.dart';

import 'team_profile_screen.dart';
import 'teams_screen.dart';
import 'friends_screen.dart';
import 'friends_group_profile_screen.dart';
import 'select_sports_screen.dart';

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
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _friendsGroups = [];
  int _gamesCount = 0; // Games participated
  int _winsCount = 0; // Wins count

  String? _effectiveUserId; // profile being viewed
  String? _currentUserId; // logged-in user
  bool _isSelf = false;

  // Relationship between logged-in user and profile user
  // 'none' | 'accepted' | 'outgoing' | 'incoming'
  String _friendRelationship = 'none';
  String? _friendRequestIdForProfile; // request row id when pending

  // Edit mode state
  bool _isEditing = false;
  final TextEditingController _nameEditController = TextEditingController();
  final TextEditingController _bioEditController = TextEditingController();
  String? _editHomeCity;
  String? _editHomeState;
  String? _editHomeZipCode;
  bool _savingProfile = false;

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

  @override
  void dispose() {
    _nameEditController.dispose();
    _bioEditController.dispose();
    super.dispose();
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
      // 1) Load main user row (including bio and home location)
      final userRow = await supa
          .from('users')
          .select(
            'id, full_name, photo_url, bio, home_city, home_state, home_zip_code',
          )
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

      // 4) Load team details
      List<Map<String, dynamic>> teams = [];
      if (membershipRows.isNotEmpty) {
        final teamIds = membershipRows
            .map<String>((m) => m['team_id'] as String)
            .toList();

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

          // Get member counts for all teams at once
          if (teamIds.isNotEmpty) {
            final allMemberRows = await supa
                .from('team_members')
                .select('team_id')
                .inFilter('team_id', teamIds);
            
            // Count members per team
            final Map<String, int> memberCounts = {};
            if (allMemberRows is List) {
              for (final memberRow in allMemberRows) {
                final tid = memberRow['team_id'] as String?;
                if (tid != null) {
                  memberCounts[tid] = (memberCounts[tid] ?? 0) + 1;
                }
              }
            }
            
            // Add member_count to each team
            for (final team in teams) {
              final teamId = team['id'] as String;
              team['member_count'] = memberCounts[teamId] ?? 0;
            }
          } else {
            // No teams, set member_count to 0 for all
            for (final team in teams) {
              team['member_count'] = 0;
            }
          }

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

      // 5) Location is now device-based, not ZIP-based
      // No need to fetch city/state from ZIP codes

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
            .map<Map<String, dynamic>>(
              (u) => {
                  'id': u['id'] as String,
                  'full_name': u['full_name'] as String? ?? 'Unknown',
                  'photo_url': u['photo_url'] as String?,
                  'base_zip_code': u['base_zip_code'] as String?,
              },
            )
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
        final requesterIds = pendingRows
            .map<String>((r) => r['user_id'] as String)
            .toList();

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

      // 8) Load friends groups (for profile user - can be self or other user)
      List<Map<String, dynamic>> groups = [];
      // First, get groups where profile user is the creator
      final createdGroupsRows = await supa
          .from('friends_groups')
          .select('id, name, created_by, sport')
          .eq('created_by', userId)
          .order('sport, name');
      
      // Then, get group IDs where profile user is a member
      final memberGroupsRows = await supa
          .from('friends_group_members')
          .select('group_id')
          .eq('user_id', userId);
      
      // Collect all group IDs (created + member)
      Set<String> allGroupIds = {};
      if (createdGroupsRows is List) {
        for (final g in createdGroupsRows) {
          final groupId = g['id'] as String?;
          if (groupId != null) allGroupIds.add(groupId);
        }
      }
      if (memberGroupsRows is List) {
        for (final m in memberGroupsRows) {
          final groupId = m['group_id'] as String?;
          if (groupId != null) allGroupIds.add(groupId);
        }
      }
      
      // Fetch all groups (if we have member groups that aren't in created groups)
      if (allGroupIds.isNotEmpty) {
        final allGroupsRows = await supa
            .from('friends_groups')
            .select('id, name, created_by, sport')
            .inFilter('id', allGroupIds.toList())
            .order('sport, name');
        
        if (allGroupsRows is List) {
          for (final g in allGroupsRows) {
            // Get member count for each group
            final memberRows = await supa
                .from('friends_group_members')
                .select('id')
                .eq('group_id', g['id']);
            
            groups.add({
              'id': g['id'],
              'name': g['name'],
              'sport': g['sport'],
              'created_by': g['created_by'],
              'member_count': memberRows is List ? memberRows.length : 0,
            });
          }
        }
      }

      // 9) Load games count and wins count
      int gamesCount = 0;
      int winsCount = 0;
      
      if (teams.isNotEmpty) {
        final teamIds = teams.map<String>((t) => t['id'] as String).toList();
        
        // Count games where user participated (team_match_attendance with status 'confirmed')
        final attendanceRows = await supa
            .from('team_match_attendance')
            .select('request_id, team_id, status')
            .inFilter('team_id', teamIds)
            .eq('status', 'confirmed');
        
        // Get unique request_ids to count distinct games
        final gameIds = <String>{};
        if (attendanceRows is List) {
          for (final row in attendanceRows) {
            final requestId = row['request_id'] as String?;
            if (requestId != null) {
              gameIds.add(requestId);
            }
          }
        }
        gamesCount = gameIds.length;
        
        // TODO: Count wins - this requires a winner field in confirmed_matches or team_match_request
        // For now, set wins to 0 until winner tracking is implemented
        winsCount = 0;
      }

      setState(() {
        _userRow = userRow != null ? Map<String, dynamic>.from(userRow) : null;
        _sports = sports;
        _teams = teams;
        _friends = friends;
        _incomingRequests = incomingRequests;
        _friendRelationship = relationship;
        _friendRequestIdForProfile = relReqId;
        _friendsGroups = groups;
        _gamesCount = gamesCount;
        _winsCount = winsCount;
        _loading = false;
        
        // Update edit controllers if not in edit mode
        if (!_isEditing && _userRow != null) {
          _nameEditController.text = _userRow!['full_name'] as String? ?? '';
          _bioEditController.text = _userRow!['bio'] as String? ?? '';
          _editHomeCity = _userRow!['home_city'] as String?;
          _editHomeState = _userRow!['home_state'] as String?;
          _editHomeZipCode = _userRow!['home_zip_code'] as String?;
        }
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load profile: $e')));
    }
  }

  void _startEditing() {
    if (_userRow == null) return;
    setState(() {
      _isEditing = true;
      _nameEditController.text = _userRow!['full_name'] as String? ?? '';
      _bioEditController.text = _userRow!['bio'] as String? ?? '';
      _editHomeCity = _userRow!['home_city'] as String?;
      _editHomeState = _userRow!['home_state'] as String?;
      _editHomeZipCode = _userRow!['home_zip_code'] as String?;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _nameEditController.text = _userRow?['full_name'] as String? ?? '';
      _bioEditController.text = _userRow?['bio'] as String? ?? '';
      _editHomeCity = _userRow?['home_city'] as String?;
      _editHomeState = _userRow?['home_state'] as String?;
      _editHomeZipCode = _userRow?['home_zip_code'] as String?;
    });
  }

  Future<void> _saveProfile() async {
    if (_effectiveUserId == null) return;

    setState(() => _savingProfile = true);

    final supa = Supabase.instance.client;
    try {
      await supa
          .from('users')
          .update({
        'full_name': _nameEditController.text.trim(),
        'bio': _bioEditController.text.trim(),
        'home_city': _editHomeCity,
        'home_state': _editHomeState,
        'home_zip_code': _editHomeZipCode,
        'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _effectiveUserId!);

      setState(() {
        _isEditing = false;
        _savingProfile = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );

      await _loadProfile();
    } catch (e) {
      setState(() => _savingProfile = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
    }
  }

  Future<void> _showHomeLocationPicker() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _HomeLocationPickerDialog(
        currentCity: _editHomeCity,
        currentState: _editHomeState,
        currentZip: _editHomeZipCode,
      ),
    );

    if (result != null) {
      setState(() {
        _editHomeCity = result['city'];
        _editHomeState = result['state'];
        _editHomeZipCode = result['zip'];
      });
    }
  }

  Future<void> _changeProfilePhoto() async {
    if (!_isSelf || _effectiveUserId == null) return;

    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (picked == null) return;

      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) return;

      // Upload to storage
      Uint8List bytes = await picked.readAsBytes();
      final fileExt = picked.name.split('.').last;
      final filePath =
          'avatar_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await supa.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: picked.mimeType ?? 'image/$fileExt',
              upsert: true,
            ),
          );

      // Get public URL
      final publicUrl = supa.storage.from('avatars').getPublicUrl(filePath);

      // Update users table
      await supa
          .from('users')
          .update({
        'photo_url': publicUrl,
        'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _effectiveUserId!);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo updated')));

      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to upload photo: $e')));
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
      // Note: We don't clear location cache on logout anymore
      // Cache is now user-specific, so each user has their own cached location
      // This allows faster loading while keeping locations separate per user
      
      await supa.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logged out')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to logout: $e')));
    }
  }

  /// Remove friend when you are viewing your own profile (used in Friends list).
  Future<void> _removeFriend(String friendUserId, String friendName) async {
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
      await supa.from('friends').delete().match({
        'user_id': currentUserId,
        'friend_id': friendUserId,
      });
      await supa.from('friends').delete().match({
        'user_id': friendUserId,
        'friend_id': currentUserId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $friendName from friends')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove friend: $e')));
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
            .update({'status': 'accepted'})
            .eq('id', requestId);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update request: $e')));
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
      await supa.from('friends').delete().match({
        'user_id': myId,
        'friend_id': otherId,
      });
      await supa.from('friends').delete().match({
        'user_id': otherId,
        'friend_id': myId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed $name from friends')));
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove friend: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Friend request sent to $name')));
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send request: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to cancel request: $e')));
    }
  }

  Future<void> _showManageFriendsSheet() async {
    final supa = Supabase.instance.client;
    final currentUserId = _effectiveUserId;
    if (currentUserId == null) return;

    final nameCtrl = TextEditingController();
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
              final email = emailCtrl.text.trim();
              final phone = phoneCtrl.text.trim();

              setSheetState(() => searching = true);
              try {
                var query = supa
                    .from('users')
                    .select('id, full_name, photo_url, email, phone')
                    .neq('id', currentUserId);

                if (name.isNotEmpty) {
                  query = query.ilike('full_name', '%$name%');
                }
                if (email.isNotEmpty) {
                  query = query.ilike('email', '%$email%');
                }
                if (phone.isNotEmpty) {
                  query = query.ilike('phone', '%$phone%');
                }

                final rows = await query;
                results = (rows as List)
                    .map<Map<String, dynamic>>(
                      (u) => {
                          'id': u['id'] as String,
                        'full_name': u['full_name'] as String? ?? 'Unknown',
                          'photo_url': u['photo_url'] as String?,
                          'base_zip_code': u['base_zip_code'] as String?,
                          'email': u['email'] as String?,
                          'phone': u['phone'] as String?,
                      },
                    )
                    .toList();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
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
                    SnackBar(content: Text('Friend request sent to $name')),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: searching ? null : doSearch,
                      icon: const Icon(Icons.search),
                      label: Text(searching ? 'Searching...' : 'Search'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (results.isEmpty && !searching)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Search players by name, email, or phone to add as friends.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  else
                    SizedBox(
                      height: 260,
                      child: searching
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (ctx, idx) {
                                final r = results[idx];
                                final id = r['id'] as String;
                                final name =
                                    r['full_name'] as String? ?? 'Unknown';
                                final photoUrl = r['photo_url'] as String?;
                                final email = r['email'] as String?;
                                final phone = r['phone'] as String?;
                                final rel = relationshipByUserId[id];

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
                                    icon: const Icon(Icons.person_add_alt_1),
                                    onPressed: () => addFriend(id, name),
                                  );
                                }

                                final subtitleParts = <String>[];
                                if (email != null && email.isNotEmpty) {
                                  subtitleParts.add(email);
                                }
                                if (phone != null && phone.isNotEmpty) {
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
                                      child:
                                          (photoUrl == null || photoUrl.isEmpty)
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(name),
                                    subtitle: subtitleParts.isEmpty
                                        ? null
                                        : Text(subtitleParts.join(' • ')),
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
              final desc = descCtrl.text.trim();

              if (selectedSport == null || teamName.isEmpty) {
                setSheetState(() {
                  errorText = 'Sport and Team name are required.';
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
                  SnackBar(content: Text('Team "$teamName" created')),
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
                await supa.from('user_sports').delete().eq('user_id', userId);

                // 2) insert selected sports
                if (selectedSports.isNotEmpty) {
                  final rows = selectedSports
                      .map((s) => {'user_id': userId, 'sport': s})
                      .toList();
                  await supa.from('user_sports').insert(rows);
                }

                if (!mounted) return;
                Navigator.of(sheetContext).pop();
                await _loadProfile();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sports interests updated')),
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
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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
    String? selectedSport;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String _displaySport(String key) {
              return key
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map(
                    (w) => w.isEmpty
                        ? w
                        : w[0].toUpperCase() + w.substring(1).toLowerCase(),
                  )
                  .join(' ');
            }

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
                      'Select Sport:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedSport,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Choose a sport',
                      ),
                      items: _sports.map((sport) {
                        return DropdownMenuItem<String>(
                          value: sport,
                          child: Text(_displaySport(sport)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedSport = value;
                        });
                      },
                    ),
                    if (selectedSport != null) ...[
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
                                child: Text(
                                  'No friends available',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _friends.length,
                                itemBuilder: (context, index) {
                                  final friend = _friends[index];
                                  final friendId = friend['id'] as String;
                                  final friendName =
                                      friend['full_name'] as String? ??
                                      'Unknown';
                                  final isSelected = selectedFriendIds.contains(
                                    friendId,
                                  );

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
                        const SnackBar(
                          content: Text('Please enter a group name'),
                        ),
                      );
                      return;
                    }

                    if (selectedSport == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select a sport')),
                      );
                      return;
                    }

                    if (selectedFriendIds.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select at least one friend'),
                        ),
                      );
                      return;
                    }

                    await _createFriendsGroup(
                      nameController.text.trim(),
                      selectedSport!,
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

  Future<void> _showManageFriendsGroupSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Manage Friends Groups',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _friendsGroups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.group_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No friends groups yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create a group to get started',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          // Group by sport
                          final Map<String, List<Map<String, dynamic>>>
                          groupsBySport = {};
                          for (final group in _friendsGroups) {
                            final sport =
                                (group['sport'] as String?) ?? 'Other';
                            groupsBySport
                                .putIfAbsent(sport, () => [])
                                .add(group);
                          }

                          // Sort sports
                          final sortedSports = groupsBySport.keys.toList()
                            ..sort();

                          String _displaySport(String key) {
                            return key
                                .replaceAll('_', ' ')
                                .split(' ')
                                .map(
                                  (w) => w.isEmpty
                                      ? w
                                      : w[0].toUpperCase() +
                                            w.substring(1).toLowerCase(),
                                )
                                .join(' ');
                          }

                          return ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            children: sortedSports.expand<Widget>((sportKey) {
                              final sportGroups = groupsBySport[sportKey]!;
                              return [
                                // Sport header
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.sports,
                                        size: 18,
                                        color: Colors.black87,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _displaySport(sportKey),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Groups for this sport
                                ...sportGroups.map<Widget>((group) {
                                  final groupId = group['id'] as String;
                                  final groupName =
                                      group['name'] as String? ??
                                      'Unnamed Group';
                                  final groupSport = group['sport'] as String?;
                                  final memberCount =
                                      group['member_count'] as int? ?? 0;
                                  final isCreator =
                                      (group['created_by'] as String?) ==
                                      _currentUserId;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade100,
                                        child: Icon(
                                          Icons.group,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      title: Text(
                                        groupSport != null
                                            ? '$groupName, ${_displaySport(groupSport)}'
                                            : groupName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert),
                                        onSelected: (value) async {
                                          Navigator.pop(
                                            context,
                                          ); // Close popup menu
                                          switch (value) {
                                            case 'view':
                                              Navigator.pop(
                                                context,
                                              ); // Close bottom sheet
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      FriendsGroupProfileScreen(
                                                        groupId:
                                                            group['id']
                                                                as String,
                                                        groupName:
                                                            group['name']
                                                                as String? ??
                                                            'Unnamed Group',
                                                  ),
                                                ),
                                              );
                                              break;
                                            case 'edit':
                                              if (isCreator) {
                                                Navigator.pop(
                                                  context,
                                                ); // Close bottom sheet
                                                _showEditFriendsGroupDialog(
                                                  group,
                                                );
                                              }
                                              break;
                                            case 'add_members':
                                              if (isCreator) {
                                                Navigator.pop(
                                                  context,
                                                ); // Close bottom sheet
                                                await _showAddMembersToGroup(
                                                  group,
                                                );
                                              }
                                              break;
                                            case 'delete':
                                              if (isCreator) {
                                                Navigator.pop(
                                                  context,
                                                ); // Close bottom sheet
                                                _showDeleteFriendsGroupDialog(
                                                  group,
                                                );
                                              }
                                              break;
                                            case 'leave':
                                              if (!isCreator) {
                                                Navigator.pop(
                                                  context,
                                                ); // Close bottom sheet
                                                _leaveFriendsGroup(
                                                  groupId,
                                                  groupName,
                                                );
                                              }
                                              break;
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'view',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.visibility,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 8),
                                                Text('View Details'),
                                              ],
                                            ),
                                          ),
                                          if (isCreator) ...[
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Edit Group'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'add_members',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.person_add,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Add Members'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete,
                                                    size: 20,
                                                    color: Colors.red,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Delete Group',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else
                                            const PopupMenuItem(
                                              value: 'leave',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.exit_to_app,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Leave Group'),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      onTap: () {
                                        Navigator.pop(
                                          context,
                                        ); // Close bottom sheet
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                FriendsGroupProfileScreen(
                                                  groupId:
                                                      group['id'] as String,
                                                  groupName:
                                                      group['name']
                                                          as String? ??
                                                      'Unnamed Group',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }),
                              ];
                            }).toList(),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createFriendsGroup(
    String name,
    String sport,
    List<String> friendIds,
  ) async {
    final supa = Supabase.instance.client;
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      // Create group
      final groupResult = await supa
          .from('friends_groups')
          .insert({'name': name, 'sport': sport, 'created_by': userId})
          .select('id')
          .maybeSingle();

      final groupId = groupResult?['id'] as String?;
      if (groupId == null) {
        throw Exception('Failed to create group');
      }

      // Add members (including creator)
      // Filter out creator from friendIds if they were somehow selected
      final membersToAdd = friendIds.where((id) => id != userId).toList();
      
      // Create member records: creator + selected friends
      final memberRecords = <Map<String, dynamic>>[
        // Add creator as first member
        {'group_id': groupId, 'user_id': userId, 'added_by': userId},
        // Add selected friends
        ...membersToAdd.map(
          (friendId) => {
          'group_id': groupId,
          'user_id': friendId,
          'added_by': userId,
          },
        ),
      ];

      await supa.from('friends_group_members').insert(memberRecords);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friends group created!')));
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create group: $e')));
    }
  }

  Future<void> _showEditFriendsGroupDialog(Map<String, dynamic> group) async {
    final groupId = group['id'] as String;
    final nameController = TextEditingController(
      text: group['name'] as String? ?? '',
    );

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group updated!')));
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update group: $e')));
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
      await supa.from('friends_group_members').delete().match({
        'group_id': groupId,
        'user_id': userId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Left "$groupName"')));
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to leave group: $e')));
    }
  }

  Future<void> _showFriendsGroupDetails(Map<String, dynamic> group) async {
    final groupId = group['id'] as String;
    final groupName = group['name'] as String? ?? 'Unnamed Group';
    final isCreator = (group['created_by'] as String?) == _currentUserId;
    final currentUserId = _currentUserId;

    if (currentUserId == null) return;

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

    // Check friendship status for each member
    final Map<String, String> friendshipStatus =
        {}; // 'accepted', 'pending', 'none'
    final Map<String, String?> friendRequestIds = {};
    
    if (memberIds.isNotEmpty) {
      // Check if current user is friends with each member
      final friendsRows = await supa
          .from('friends')
          .select('id, friend_id, status')
          .eq('user_id', currentUserId)
          .inFilter('friend_id', memberIds);

      if (friendsRows is List) {
        for (final row in friendsRows) {
          final friendId = row['friend_id'] as String?;
          final status = row['status'] as String?;
          final reqId = row['id'] as String?;
          if (friendId != null) {
            friendshipStatus[friendId] = status ?? 'pending';
            friendRequestIds[friendId] = reqId;
          }
        }
      }

      // Also check reverse (if they sent request to us)
      final reverseRows = await supa
          .from('friends')
          .select('id, user_id, status')
          .eq('friend_id', currentUserId)
          .inFilter('user_id', memberIds);

      if (reverseRows is List) {
        for (final row in reverseRows) {
          final userId = row['user_id'] as String?;
          final status = row['status'] as String?;
          final reqId = row['id'] as String?;
          if (userId != null) {
            friendshipStatus[userId] = status ?? 'pending';
            friendRequestIds[userId] = reqId;
          }
        }
      }
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> sendFriendRequest(
            String friendId,
            String friendName,
          ) async {
            try {
              await supa.from('friends').insert({
                'user_id': currentUserId,
                'friend_id': friendId,
                'status': 'pending',
              });

              setDialogState(() {
                friendshipStatus[friendId] = 'pending';
              });

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Friend request sent to $friendName')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to send request: $e')),
                );
              }
            }
          }

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(groupName),
                const SizedBox(height: 4),
                Text(
                  '${memberIds.length} ${memberIds.length == 1 ? 'member' : 'members'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (users is List && users.isNotEmpty)
                    ...users.map((user) {
                      final userId = user['id'] as String;
                      final userName =
                          user['full_name'] as String? ?? 'Unknown';
                      final photoUrl = user['photo_url'] as String?;
                      final isFriend = friendshipStatus[userId] == 'accepted';
                      final hasPendingRequest =
                          friendshipStatus[userId] == 'pending';
                      final isSelf = userId == currentUserId;
                      final isGroupCreator = userId == group['created_by'];

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              photoUrl != null && photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null || photoUrl.isEmpty
                              ? Text(
                                  userName.isNotEmpty
                                      ? userName[0].toUpperCase()
                                      : '?',
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(userName)),
                            if (isGroupCreator)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
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
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isFriend && !hasPendingRequest)
                                    TextButton.icon(
                                      icon: const Icon(
                                        Icons.person_add,
                                        size: 18,
                                      ),
                                      label: const Text('Add Friend'),
                                      onPressed: () =>
                                          sendFriendRequest(userId, userName),
                                    ),
                                  if (hasPendingRequest)
                                    const Text(
                                      'Request sent',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (isFriend)
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                  if (isCreator && !isSelf)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      tooltip: 'Remove from group',
                                      onPressed: () async {
                                        await supa
                                            .from('friends_group_members')
                                            .delete()
                                            .match({
                                              'group_id': groupId,
                                              'user_id': userId,
                                            });
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          await _showFriendsGroupDetails(group);
                                        }
                                      },
                                    ),
                                ],
                              ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(userId: userId),
                            ),
                          );
                        },
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
          );
        },
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
                            final friendName =
                                friend['full_name'] as String? ?? 'Unknown';
                            final isSelected = selectedFriendIds.contains(
                              friendId,
                            );

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
                          await _addMembersToGroup(
                            groupId,
                            selectedFriendIds.toList(),
                          );
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

  Future<void> _addMembersToGroup(
    String groupId,
    List<String> friendIds,
  ) async {
    final supa = Supabase.instance.client;
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final memberRecords = friendIds
          .map(
            (friendId) => {
        'group_id': groupId,
        'user_id': friendId,
        'added_by': userId,
            },
          )
          .toList();

      await supa.from('friends_group_members').insert(memberRecords);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${friendIds.length} member(s)')),
      );
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add members: $e')));
    }
  }

  Future<void> _showDeleteFriendsGroupDialog(Map<String, dynamic> group) async {
    final groupId = group['id'] as String;
    final groupName = group['name'] as String? ?? 'Unnamed Group';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text(
          'Are you sure you want to delete "$groupName"? This action cannot be undone.',
        ),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final supa = Supabase.instance.client;
    try {
      await supa.from('friends_groups').delete().eq('id', groupId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted "$groupName"')));
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete group: $e')));
    }
  }

  Future<void> _showDeleteTeamDialog(String teamId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Team?'),
        content: Text(
          'Are you sure you want to delete "$teamName"? This action cannot be undone.',
        ),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final supa = Supabase.instance.client;
    try {
      // Delete team members first (cascade should handle this, but being explicit)
      await supa.from('team_members').delete().eq('team_id', teamId);

      // Delete the team
      await supa.from('teams').delete().eq('id', teamId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted "$teamName"')));
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete team: $e')));
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

  // Collapsible state for Groups and Teams
  bool _groupsExpanded = true;
  bool _teamsExpanded = true;

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

    // Color constants matching rules.md
    const tealDark = Color(0xFF0E7C7B);
    const teal = Color(0xFF0E8E8E);
    const tealSoft = Color(0xFF5CB8B4);
    const white = Color(0xFFFFFFFF);
    const offWhite = Color(0xFFEFF7F6);
    const orange = Color(0xFFFF6B35);
    const greenButton = Color(0xFF4FAFAF);
    const textDark = Color(0xFF0F2E2E);
    const profileTeal = Color(0xFF14919B);

    return Scaffold(
      // 0️⃣ APP BAR (TOP) — forbidden
      appBar: null,
      // 1️⃣ PAGE BACKGROUND — white
      backgroundColor: white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_userRow == null)
            const Center(child: Text('No profile found.'))
          else
            Column(
              children: [
                // Top section with teal green background (extended to cover buttons)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screenHeight = MediaQuery.of(context).size.height;
                    // Extended height to cover buttons - approximately 28% of screen
                    final topSectionHeight = screenHeight * 0.28; // Extended from 1/5 to cover buttons
                    return Container(
                      height: topSectionHeight,
                      width: double.infinity,
                      color: teal,
                      child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              // Profile Photo and Name Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Profile Photo - top left
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 36, // 72x72
                                        backgroundColor: orange,
                                        backgroundImage:
                                            (_userRow!['photo_url'] as String?)
                                                    ?.isNotEmpty ==
                                                true
                                                ? NetworkImage(
                                                    _userRow!['photo_url'] as String,
                                                  )
                                                : null,
                                        child: ((_userRow!['photo_url'] as String?)
                                                    ?.isEmpty ??
                                                true)
                                            ? Text(
                                                (_userRow!['full_name'] as String?)
                                                        ?.isNotEmpty ==
                                                    true
                                                ? (_userRow!['full_name']
                                                        as String)[0]
                                                    .toUpperCase()
                                                : '?',
                                                style: const TextStyle(
                                                  fontFamily: 'Inter',
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w700,
                                                  color: white,
                                                ),
                                              )
                                            : null,
                                      ),
                                      if (_isSelf)
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: GestureDetector(
                                            onTap: _changeProfilePhoto,
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: const BoxDecoration(
                                                color: orange,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.camera_alt,
                                                size: 16,
                                                color: white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  // Name and City - horizontally aligned next to photo
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Name - top aligned
                                        if (_isEditing)
                                          TextField(
                                            controller: _nameEditController,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 26,
                                              fontWeight: FontWeight.w600,
                                              color: white,
                                            ),
                                            decoration: InputDecoration(
                                              border: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderSide: BorderSide(color: greenButton),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                            ),
                                          )
                                        else
                                          Text(
                                            (_userRow!['full_name'] as String?) ?? 'No Name',
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 26,
                                              fontWeight: FontWeight.w600,
                                              color: white,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        const SizedBox(height: 6),
                                        // City only (hide state and zip) with location icon
                                        Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                            const Icon(
                                              Icons.location_on,
                                              size: 16,
                                              color: white,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                () {
                                                  final homeCity = _userRow!['home_city'] as String?;
                                                  if (homeCity != null && homeCity.isNotEmpty) {
                                                    return homeCity;
                                                  }
                                                  return '';
                                                    }(),
                                                    style: const TextStyle(
                                                  fontFamily: 'Inter',
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w400,
                                                  color: white,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Edit Profile and Share buttons
                              if (_isSelf) ...[
                                const SizedBox(height: 20),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final availableWidth = constraints.maxWidth; // Already accounts for padding
                                    final buttonSpacing = 12.0;
                                    final buttonWidth = (availableWidth - buttonSpacing) / 2;
                                    return Row(
                                      children: [
                                        SizedBox(
                                          width: buttonWidth,
                                          child: InkWell(
                                            onTap: _startEditing,
                                            borderRadius: BorderRadius.circular(12),
                                            child: Container(
                                              height: 52,
                                              decoration: BoxDecoration(
                                              color: Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.grey.shade300,
                                                  width: 1,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.05),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.edit,
                                                    size: 20,
                                                    color: teal,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Edit Profile',
                                                    style: TextStyle(
                                                      fontFamily: 'Inter',
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w600,
                                                      color: teal,
                                    ),
                                  ),
                                ],
                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: buttonSpacing),
                                        SizedBox(
                                          width: buttonWidth,
                                          child: InkWell(
                                            onTap: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Share functionality coming soon',
                                                  ),
                                                ),
                                              );
                                            },
                                            borderRadius: BorderRadius.circular(12),
                                            child: Container(
                                              height: 52,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.grey.shade300,
                                                  width: 1,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.05),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.share,
                                                    size: 20,
                                                    color: teal,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Share',
                                                    style: TextStyle(
                                                      fontFamily: 'Inter',
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w600,
                                                      color: teal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Rest of content (white background)
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                        // Statistics Section - touches borders
                        _buildStatisticsSection(),
                        // Spacing to separate chips visually
                        const SizedBox(height: 8),
                        // Friends Section - similar to stats
                        _buildFriendsSection(),
                        // Spacing between Friends and Teams/Groups sections
                        const SizedBox(height: 12),
                        // My Teams and My Groups sections side by side
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // My Teams section (left half)
                              Expanded(
                                child: _buildMyTeamsSection(),
                                    ),
                                    const SizedBox(width: 8),
                              // My Groups section (right half)
                              Expanded(
                                child: _buildMyGroupsSection(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          // 8️⃣ FLOATING ACTION BUTTONS (ONLY PLACE FOR ORANGE) - moved further down
          if (_isSelf)
            Positioned(
              bottom: 160, // Moved further down from bottom nav
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'create_team',
                    onPressed: _showCreateTeamSheet,
                    backgroundColor: orange,
                    icon: const Icon(Icons.group_add, color: white),
                    label: const Text(
                      'Create Team',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'create_group',
                    onPressed: _showCreateFriendsGroupDialog,
                    backgroundColor: orange,
                    icon: const Icon(Icons.group, color: white),
                    label: const Text(
                      'Create Group',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: white,
                      ),
                    ),
                  ),
                                ],
                              ),
                            ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection() {
    const tealDark = Color(0xFF0E7C7B);
    const teal = Color(0xFF0E8E8E);
    const white = Color(0xFFFFFFFF);
    const textDark = Color(0xFF0F2E2E);

    // Stats section with darker white background (chip-like), rounded corners, touches borders
    return Container(
      height: 110, // Increased height
      decoration: BoxDecoration(
        color: Colors.grey.shade100, // Darker white background for chip appearance
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withOpacity(0.1), // Light thin black border
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
                                child: Column(
                                  children: [
          // Top row: Games + Teams
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 22, color: tealDark),
                        const SizedBox(width: 10),
                                    Text(
                          _gamesCount.toString(),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Games',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.grey.shade200),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                        Icon(Icons.groups, size: 22, color: tealDark),
                        const SizedBox(width: 10),
                        Text(
                          _teams.length.toString(),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Teams',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: teal,
                            ),
                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                            ),
                                  ],
                                ),
                              ),
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
          // Bottom row: Wins + chevron
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events, size: 22, color: tealDark),
                  const SizedBox(width: 10),
                  Text(
                    _winsCount.toString(),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Wins',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: teal,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 22, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsSection() {
    const tealDark = Color(0xFF0E7C7B);
    const white = Color(0xFFFFFFFF);
    const textDark = Color(0xFF0F2E2E);
    const teal = Color(0xFF0E8E8E);

    // Friends section with darker white background (chip-like), rounded corners, touches borders - matches image design
    return Container(
      height: 145, // Increased height to accommodate larger chips (85x85) + small buffer
      decoration: BoxDecoration(
        color: Colors.grey.shade100, // Darker white background for chip appearance
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withOpacity(0.1), // Light thin black border
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
                              child: Column(
                                children: [
          // Header row: Friends (count) + Add button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                Row(
                  children: [
                    Icon(Icons.people, size: 20, color: tealDark),
                    const SizedBox(width: 8),
                                      Text(
                                        'Friends (${_friends.length})',
                                        style: const TextStyle(
                        fontFamily: 'Inter',
                                          fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: teal,
                                        ),
                    ),
                  ],
                                      ),
                                      if (_isSelf)
                  InkWell(
                    onTap: _showManageFriendsSheet,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add, size: 18, color: teal),
                        const SizedBox(width: 4),
                        const Text(
                          'Add',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: teal,
                          ),
                                        ),
                                    ],
                                  ),
                  ),
              ],
            ),
          ),
          // Horizontal scrollable friend list (max 2-3 friends visible)
          Expanded(
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: (_friends.length > 3 ? 3 : _friends.length) + 1, // Max 3 friends + chevron
                                        itemBuilder: (context, index) {
                final maxVisible = _friends.length > 3 ? 3 : _friends.length;

                if (index == maxVisible) {
                  // Chevron card for more friends
                                          return GestureDetector(
                                            onTap: () {
                                              Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FriendsScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        width: 85,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.chevron_right,
                            size: 28,
                            color: Colors.grey.shade600,
                          ),
                        ),
                                                  ),
                                                ),
                                              );
                }
                
                final friend = _friends[index];
                final friendName = friend['full_name'] as String? ?? 'Unknown';
                final photoUrl = friend['photo_url'] as String?;
                final friendId = friend['id'] as String?;
                
                return GestureDetector(
                  onTap: friendId != null
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(userId: friendId),
                            ),
                          );
                        }
                      : null,
                                            child: Padding(
                    padding: EdgeInsets.only(right: index < maxVisible - 1 ? 12 : 0),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                        // Profile picture with overlay icon (reduced size to prevent overflow)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 85,
                              height: 85,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: photoUrl != null && photoUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(photoUrl),
                                        fit: BoxFit.cover,
                                      )
                                                        : null,
                                color: photoUrl == null || photoUrl.isEmpty
                                    ? Colors.grey.shade300
                                    : null,
                              ),
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? Icon(Icons.person, size: 42, color: Colors.grey.shade600)
                                                        : null,
                            ),
                            // Overlay icon (yellow background with red symbol)
                            Positioned(
                              bottom: 2,
                              left: 2,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.yellow.shade700,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.groups,
                                  size: 12,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                                                  ),
                                                  const SizedBox(height: 4),
                        // Friend name (with overflow protection)
                                                  SizedBox(
                          width: 85,
                                                    child: Text(
                            friendName,
                                                      style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                            textAlign: TextAlign.center,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
    );
  }

  Widget _buildMyTeamsSection() {
    const tealDark = Color(0xFF0E7C7B);
    const teal = Color(0xFF0E8E8E);
    const orange = Color(0xFFFF6B35);
    const white = Color(0xFFFFFFFF);
    const textDark = Color(0xFF0F2E2E);

    // Group teams by sport and get top 2 by member count for each sport
    Map<String, List<Map<String, dynamic>>> teamsBySport = {};
    for (final team in _teams) {
      final sport = (team['sport'] as String?) ?? 'Unknown';
      if (!teamsBySport.containsKey(sport)) {
        teamsBySport[sport] = [];
      }
      teamsBySport[sport]!.add(team);
    }

    // Sort teams within each sport by member_count (descending), then take top 2
    for (final sport in teamsBySport.keys) {
      teamsBySport[sport]!.sort((a, b) {
        final countA = (a['member_count'] as int?) ?? 0;
        final countB = (b['member_count'] as int?) ?? 0;
        return countB.compareTo(countA);
      });
      teamsBySport[sport] = teamsBySport[sport]!.take(2).toList();
    }

    // Get first sport (or default)
    final sportKeys = teamsBySport.keys.toList();
    if (sportKeys.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.1),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                          Row(
                                            children: [
                  Icon(Icons.groups, size: 20, color: tealDark),
                  const SizedBox(width: 8),
                                              const Text(
                    'My Teams',
                                                style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textDark,
                    ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
              const Text(
                'No teams yet',
                                          style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final firstSport = sportKeys.first;
    final teamsForSport = teamsBySport[firstSport] ?? [];

    String _formatSportName(String sport) {
      return sport
          .split('_')
          .map((word) => word.isEmpty
              ? word
              : word[0].toUpperCase() + (word.length > 1 ? word.substring(1).toLowerCase() : ''))
          .join(' ');
    }

    return InkWell(
      onTap: () => _showTeamsGroupsBottomSheet(context, isTeams: true),
      child: Container(
        decoration: BoxDecoration(
          color: white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.1),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
              // Header
              Row(
                children: [
                  Icon(Icons.groups, size: 20, color: tealDark),
                  const SizedBox(width: 8),
                  const Text(
                    'My Teams',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Sport name with chevron
              Row(
                children: [
                  Icon(Icons.sports_soccer, size: 18, color: tealDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatSportName(firstSport),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 12),
              // Teams list (top 2)
              ...teamsForSport.map((team) {
                final teamName = (team['name'] as String?) ?? 'Unknown';
                final memberCount = (team['member_count'] as int?) ?? 0;
                final role = (team['role'] as String?) ?? 'member';
                final isAdmin = role.toLowerCase() == 'admin';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                                                          child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                      // Team icon
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: tealDark.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.sports_volleyball, size: 18, color: tealDark),
                      ),
                      const SizedBox(width: 12),
                      // Team name and player count
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                                                              Text(
                              teamName,
                                                                style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                                                  fontWeight: FontWeight.w600,
                                color: textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$memberCount players',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey.shade600,
                                                                ),
                                    ),
                                  ],
                                ),
                                                        ),
                      // Admin tag (orange if admin)
                      if (isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
                                        ],
                                      ),
                                    ),
                                  ),
    );
  }

  void _showTeamsGroupsBottomSheet(BuildContext context, {required bool isTeams}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TeamsGroupsBottomSheet(
        teams: _teams,
        groups: _friendsGroups,
        initialIsTeams: isTeams,
        isSelf: _isSelf,
      ),
    );
  }

  Widget _buildMyGroupsSection() {
    const tealDark = Color(0xFF0E7C7B);
    const teal = Color(0xFF0E8E8E);
    const white = Color(0xFFFFFFFF);
    const textDark = Color(0xFF0F2E2E);

    // Group groups by sport and get top 2 by member count for each sport
    Map<String, List<Map<String, dynamic>>> groupsBySport = {};
    for (final group in _friendsGroups) {
      final sport = (group['sport'] as String?) ?? 'Unknown';
      if (!groupsBySport.containsKey(sport)) {
        groupsBySport[sport] = [];
      }
      groupsBySport[sport]!.add(group);
    }

    // Sort groups within each sport by member_count (descending), then take top 2
    for (final sport in groupsBySport.keys) {
      groupsBySport[sport]!.sort((a, b) {
        final countA = (a['member_count'] as int?) ?? 0;
        final countB = (b['member_count'] as int?) ?? 0;
        return countB.compareTo(countA);
      });
      groupsBySport[sport] = groupsBySport[sport]!.take(2).toList();
    }

    // Get first sport (or default)
    final sportKeys = groupsBySport.keys.toList();
    if (sportKeys.isEmpty) {
      return InkWell(
        onTap: () => _showTeamsGroupsBottomSheet(context, isTeams: false),
        child: Container(
          decoration: BoxDecoration(
            color: white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.black.withOpacity(0.1),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                    Icon(Icons.people, size: 20, color: tealDark),
                    const SizedBox(width: 8),
                                              const Text(
                      'My Groups',
                                                style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textDark,
                      ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                const Text(
                  'No groups yet',
                                    style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
        ),
      );
    }

    final firstSport = sportKeys.first;
    final groupsForSport = groupsBySport[firstSport] ?? [];

    String _formatSportName(String sport) {
      return sport
          .split('_')
          .map((word) => word.isEmpty
              ? word
              : word[0].toUpperCase() + (word.length > 1 ? word.substring(1).toLowerCase() : ''))
          .join(' ');
    }

    return InkWell(
      onTap: () => _showTeamsGroupsBottomSheet(context, isTeams: false),
      child: Container(
        decoration: BoxDecoration(
          color: white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withOpacity(0.1),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.people, size: 20, color: tealDark),
                  const SizedBox(width: 8),
                  const Text(
                    'My Groups',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Sport name with chevron
              Row(
                                                                      children: [
                  Icon(Icons.sports_soccer, size: 18, color: tealDark),
                                                                        const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatSportName(firstSport),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 12),
              // Groups list (top 2)
              ...groupsForSport.map((group) {
                final groupName = (group['name'] as String?) ?? 'Unknown';
                final memberCount = (group['member_count'] as int?) ?? 0;
                final createdBy = (group['created_by'] as String?) ?? '';
                final isAdmin = createdBy == _effectiveUserId;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group icon
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: tealDark.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.shield, size: 18, color: tealDark),
                      ),
                      const SizedBox(width: 12),
                      // Group name and player count
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groupName,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$memberCount players',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                      // Admin tag (light teal if admin)
                      if (isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: teal.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: tealDark,
                            ),
                  ),
                ),
              ],
                  ),
                );
              }),
            ],
          ),
                      ),
                    ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    const tealDark = Color(0xFF0E7C7B);
    const textDark = Color(0xFF0F2E2E);

    return Column(
      children: [
        Icon(icon, color: tealDark, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: textDark)),
        const SizedBox(height: 4),
        const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
      ],
    );
  }

  Widget _buildSportsIdentitySection() {
    const tealDark = Color(0xFF0E7C7B);
    const greenButton = Color(0xFF4FAFAF);
    const white = Color(0xFFFFFFFF);
    const textDark = Color(0xFF0F2E2E);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      color: white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.sports, size: 20, color: tealDark),
                    const SizedBox(width: 8),
                const Text(
                  'Sports Identity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                        color: textDark,
                  ),
                    ),
                  ],
                ),
                if (_isSelf)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context)
                          .push(
                        MaterialPageRoute(
                          builder: (_) => const SelectSportsScreen(),
                        ),
                          )
                          .then((_) => _loadProfile());
                    },
                    icon: const Icon(Icons.add, size: 18, color: greenButton),
                    label: const Text(
                      'Add',
                      style: TextStyle(color: greenButton),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_sports.isEmpty)
              Center(
                child: Text(
                'No sports selected yet.',
                style: TextStyle(
                  fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              )
            else ...[
                  if (_sports.isNotEmpty)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: tealDark.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                        child: Row(
                        mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getSportIcon(_sports[0]),
                            size: 16,
                            color: tealDark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _toDisplaySport(_sports[0]),
                              style: const TextStyle(
                              fontSize: 14,
                                fontWeight: FontWeight.w500,
                              color: textDark,
                            ),
                          ),
                          ],
                        ),
                      ),
                  ],
                    ),
                  if (_sports.length > 1) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sports.skip(1).map((sport) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: tealDark.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getSportIcon(sport),
                            size: 16,
                            color: tealDark,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _toDisplaySport(sport)[0].toUpperCase() +
                                _toDisplaySport(sport).substring(1),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textDark,
                            ),
                          ),
                        ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
          ],
        ),
      ),
    );
  }

  IconData _getSportIcon(String sport) {
    final sportLower = sport.toLowerCase();
    switch (sportLower) {
      case 'cricket':
        return Icons.sports_cricket;
      case 'tennis':
        return Icons.sports_tennis;
      case 'basketball':
        return Icons.sports_basketball;
      case 'soccer':
      case 'football':
        return Icons.sports_soccer;
      case 'volleyball':
        return Icons.sports_volleyball;
      case 'badminton':
        return Icons.sports;
      case 'pickleball':
        return Icons.sports;
      case 'table_tennis':
        return Icons.sports;
      default:
        return Icons.sports;
    }
  }
}

// Bottom sheet widget for Teams and Groups
class _TeamsGroupsBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> teams;
  final List<Map<String, dynamic>> groups;
  final bool initialIsTeams;
  final bool isSelf;

  const _TeamsGroupsBottomSheet({
    required this.teams,
    required this.groups,
    required this.initialIsTeams,
    required this.isSelf,
  });

  @override
  State<_TeamsGroupsBottomSheet> createState() => _TeamsGroupsBottomSheetState();
}

class _TeamsGroupsBottomSheetState extends State<_TeamsGroupsBottomSheet> {
  late bool _isTeams;

  @override
  void initState() {
    super.initState();
    _isTeams = widget.initialIsTeams;
  }

  @override
  Widget build(BuildContext context) {
    const tealDark = Color(0xFF0E7C7B);
    const teal = Color(0xFF0E8E8E);
    const white = Color(0xFFFFFFFF);

    final items = _isTeams ? widget.teams : widget.groups;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header with toggle and Manage button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Toggle switch
                Expanded(
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _isTeams = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isTeams ? tealDark : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Teams',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _isTeams ? white : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _isTeams = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: !_isTeams ? tealDark : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Groups',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: !_isTeams ? white : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Manage button
                if (widget.isSelf)
                  TextButton(
                    onPressed: () {
                      // TODO: Implement manage functionality
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Manage',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: tealDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          // List of items
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No ${_isTeams ? 'teams' : 'groups'} yet',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final name = item['name'] as String? ?? 'Unknown';
                      final sport = item['sport'] as String?;
                      
                      return ListTile(
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: sport != null
                            ? Text(
                                sport,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              )
                            : null,
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          // TODO: Navigate to team/group details
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Simplified location picker dialog for home location selection
class _HomeLocationPickerDialog extends StatefulWidget {
  final String? currentCity;
  final String? currentState;
  final String? currentZip;

  const _HomeLocationPickerDialog({
    this.currentCity,
    this.currentState,
    this.currentZip,
  });

  @override
  State<_HomeLocationPickerDialog> createState() =>
      _HomeLocationPickerDialogState();
}

class _HomeLocationPickerDialogState extends State<_HomeLocationPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentCity != null && widget.currentState != null) {
      _searchController.text = '${widget.currentCity}, ${widget.currentState}';
    } else if (widget.currentZip != null) {
      _searchController.text = widget.currentZip!;
    }
  }

  Future<void> _searchLocations(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await LocationService.searchLocations(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error searching: $e')));
      }
    }
  }

  void _selectLocation(Map<String, String> location) {
    Navigator.of(context).pop({
      'city': location['city'] ?? '',
      'state': location['state'] ?? '',
      'zip': location['zip'] ?? '',
      'display': location['display'] ?? '',
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Set Home Location',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Search for your home city or enter a ZIP code',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Search Field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Enter city name or ZIP code',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onChanged: (value) {
                if (value.length >= 3) {
                  _searchLocations(value);
                } else {
                  setState(() {
                    _searchResults = [];
                  });
                }
              },
            ),

            // Search Results
            if (_searchController.text.length >= 3) ...[
              const SizedBox(height: 16),
              const Text(
                'Search Results:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _searchResults.isEmpty
                        ? const Center(
                            child: Text(
                              'No results found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final location = _searchResults[index];
                              return ListTile(
                                leading: const Icon(Icons.location_on),
                                title: Text(location['display']!),
                                subtitle: Text('ZIP: ${location['zip']}'),
                                onTap: () => _selectLocation(location),
                              );
                            },
                          ),
              ),
            ],

            // Action Buttons
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
