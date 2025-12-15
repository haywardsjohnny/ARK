import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile_screen.dart';

class TeamProfileScreen extends StatefulWidget {
  final String teamId;
  final String teamName; // just for initial AppBar title

  const TeamProfileScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<TeamProfileScreen> createState() => _TeamProfileScreenState();
}

class _TeamProfileScreenState extends State<TeamProfileScreen> {
  bool _loading = false;
  Map<String, dynamic>? _team;
  List<Map<String, dynamic>> _members = [];
  bool _isAdmin = false; // admin or (legacy) captain
  List<Map<String, dynamic>> _joinRequests = [];

  String? _currentUserId;
  bool _isMember = false;
  bool _hasPendingJoinRequest = false;

  @override
  void initState() {
    super.initState();
    _loadTeamProfile();
  }

  Future<void> _loadTeamProfile() async {
    setState(() => _loading = true);

    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;

    try {
      // 1) Load team details
      final teamRow = await supa
          .from('teams')
          .select(
            'id, name, sport, description, proficiency_level, zip_code, team_number, created_by',
          )
          .eq('id', widget.teamId)
          .maybeSingle();

      if (teamRow == null) {
        setState(() {
          _team = null;
          _members = [];
          _joinRequests = [];
          _isAdmin = false;
          _currentUserId = null;
          _isMember = false;
          _hasPendingJoinRequest = false;
          _loading = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team not found')),
        );
        return;
      }

      // 2) Load team_members for this team
      final memberRows = await supa
          .from('team_members')
          .select('user_id, role')
          .eq('team_id', widget.teamId);

      final membersList =
          (memberRows as List).map<Map<String, dynamic>>((m) {
        return {
          'user_id': m['user_id'] as String,
          'role': m['role'] as String? ?? 'member',
        };
      }).toList();

      // 3) Load user details for all member user_ids
      final userIds = membersList.map((m) => m['user_id'] as String).toList();
      Map<String, Map<String, dynamic>> userById = {};

      if (userIds.isNotEmpty) {
        final usersRows = await supa
            .from('users')
            .select('id, full_name, photo_url, base_zip_code')
            .inFilter('id', userIds);

        for (final u in usersRows as List) {
          userById[u['id'] as String] = {
            'full_name': u['full_name'],
            'photo_url': u['photo_url'],
            'base_zip_code': u['base_zip_code'],
          };
        }
      }

      // 4) Combine member+user data
      final combinedMembers = <Map<String, dynamic>>[];
      for (final m in membersList) {
        final uid = m['user_id'] as String;
        final userInfo = userById[uid] ?? {};
        combinedMembers.add({
          'user_id': uid,
          'role': m['role'],
          'full_name': userInfo['full_name'] ?? 'Unknown',
          'photo_url': userInfo['photo_url'],
          'base_zip_code': userInfo['base_zip_code'],
        });
      }

      // 5) Determine current user info (admin? member?)
      String? currentUserId = user?.id;
      bool isAdmin = false;
      bool isMember = false;

      if (currentUserId != null) {
        for (final m in combinedMembers) {
          if (m['user_id'] == currentUserId) {
            isMember = true;
            final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
            if (role == 'admin') {
              isAdmin = true;
            }
          }
        }
      }

      // 6) Load pending join requests (only if current user is admin)
      List<Map<String, dynamic>> joinRequests = [];
      if (isAdmin) {
        try {
          final reqRows = await supa
              .from('team_join_requests')
              .select('id, user_id, message, created_at')
              .eq('team_id', widget.teamId)
              .eq('status', 'pending')
              .order('created_at', ascending: true);

          if (reqRows is List && reqRows.isNotEmpty) {
            final reqUserIds =
                reqRows.map<String>((r) => r['user_id'] as String).toList();

            final reqUsers = await supa
                .from('users')
                .select('id, full_name, photo_url, base_zip_code')
                .inFilter('id', reqUserIds);

            final Map<String, Map<String, dynamic>> reqUserById = {};
            for (final u in reqUsers as List) {
              reqUserById[u['id'] as String] =
                  Map<String, dynamic>.from(u);
            }

            for (final r in reqRows) {
              final uid = r['user_id'] as String;
              final u = reqUserById[uid];
              if (u != null) {
                joinRequests.add({
                  'request_id': r['id'] as String,
                  'user_id': uid,
                  'full_name': u['full_name'] as String? ?? 'Unknown',
                  'photo_url': u['photo_url'] as String?,
                  'base_zip_code': u['base_zip_code'] as String?,
                  'message': r['message'] as String?,
                });
              }
            }
          }
        } catch (_) {
          // If team_join_requests table not ready yet, ignore gracefully
          joinRequests = [];
        }
      }

      // 7) Check if current user already has a pending join request (for non-member)
      bool hasPendingJoinRequest = false;
      if (!isMember && currentUserId != null) {
        try {
          final pendingReq = await supa
              .from('team_join_requests')
              .select('id')
              .eq('team_id', widget.teamId)
              .eq('user_id', currentUserId)
              .eq('status', 'pending')
              .maybeSingle();

          if (pendingReq != null) {
            hasPendingJoinRequest = true;
          }
        } catch (_) {
          // ignore
        }
      }

      setState(() {
        _team = Map<String, dynamic>.from(teamRow);
        _members = combinedMembers;
        _isAdmin = isAdmin;
        _joinRequests = joinRequests;
        _currentUserId = currentUserId;
        _isMember = isMember;
        _hasPendingJoinRequest = hasPendingJoinRequest;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load team profile: $e')),
      );
    }
  }

  Widget? _buildRoleChip(String role) {
    final lower = role.toLowerCase();
    
    if (lower == 'admin') {
      return Chip(
        label: const Text('Admin', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue,
      );
    }
    return null; // Don't show chip for members
  }

  Future<void> _approveJoinRequest(Map<String, dynamic> req) async {
    if (_team == null) return;
    final supa = Supabase.instance.client;

    final teamId = _team!['id'] as String;
    final userId = req['user_id'] as String;
    final requestId = req['request_id'] as String;

    try {
      // 1) Add as member
      await supa.from('team_members').insert({
        'team_id': teamId,
        'user_id': userId,
        'role': 'member',
      });

      // 2) Mark request as approved
      await supa
          .from('team_join_requests')
          .update({'status': 'approved'}).eq('id', requestId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved join request for ${req['full_name']}')),
      );

      await _loadTeamProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve request: $e')),
      );
    }
  }

  Future<void> _rejectJoinRequest(Map<String, dynamic> req) async {
    final supa = Supabase.instance.client;
    final requestId = req['request_id'] as String;

    try {
      await supa
          .from('team_join_requests')
          .update({'status': 'rejected'}).eq('id', requestId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rejected join request for ${req['full_name']}')),
      );

      await _loadTeamProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject request: $e')),
      );
    }
  }

  Future<void> _requestAdminRights() async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null || _team == null) return;

    try {
      await supa.from('team_admin_requests').insert({
        'team_id': _team!['id'] as String,
        'user_id': user.id,
        'reason': 'User requested admin rights via app.',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Admin rights request sent. SPORTSDUG owner will review it.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request admin rights: $e')),
      );
    }
  }

  Future<void> _sendJoinRequest() async {
    if (_team == null || _currentUserId == null) return;
    final supa = Supabase.instance.client;

    try {
      await supa.from('team_join_requests').insert({
        'team_id': _team!['id'] as String,
        'user_id': _currentUserId!,
        // You can later add a message field with a text box if you want.
        'message': null,
      });

      if (!mounted) return;
      setState(() {
        _hasPendingJoinRequest = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request sent to team admins'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send join request: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamNameForTitle =
        _team != null ? (_team!['name'] as String? ?? widget.teamName) : widget.teamName;

    final userIsMember = _isMember;

    return Scaffold(
      appBar: AppBar(
        title: Text(teamNameForTitle),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                // You still manage edit in TeamsScreen/TeamManagementScreen.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Use "Manage Teams" from profile to edit.'),
                  ),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _team == null
              ? const Center(child: Text('Team not found'))
              : RefreshIndicator(
                  onRefresh: _loadTeamProfile,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Team summary card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _team!['name'] ?? '',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sport: ${_team!['sport'] ?? '-'}',
                              ),
                              Text(
                                'Proficiency: ${_team!['proficiency_level'] ?? '-'}',
                              ),
                              Text(
                                'ZIP: ${_team!['zip_code'] ?? '-'}',
                              ),
                              if (_team!['team_number'] != null)
                                Text(
                                  'Team ID: #${_team!['team_number']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              if ((_team!['description'] as String?)
                                      ?.trim()
                                      .isNotEmpty ==
                                  true)
                                Text(
                                  _team!['description'],
                                  style: const TextStyle(fontSize: 14),
                                ),

                              const SizedBox(height: 8),

                              // Join button for non-members
                              if (!_isAdmin &&
                                  !userIsMember &&
                                  _currentUserId != null)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _hasPendingJoinRequest
                                      ? OutlinedButton.icon(
                                          onPressed: null,
                                          icon: const Icon(
                                            Icons.hourglass_top,
                                          ),
                                          label: const Text(
                                            'Join request pending',
                                          ),
                                        )
                                      : ElevatedButton.icon(
                                          onPressed: _sendJoinRequest,
                                          icon: const Icon(
                                            Icons.group_add_outlined,
                                          ),
                                          label: const Text(
                                            'Request to join team',
                                          ),
                                        ),
                                ),

                              // Non-admin members can request admin rights
                              if (!_isAdmin && userIsMember)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _requestAdminRights,
                                      icon: const Icon(
                                        Icons.admin_panel_settings_outlined,
                                      ),
                                      label:
                                          const Text('Request admin rights'),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Join Requests (only visible to admins)
                      if (_isAdmin && _joinRequests.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Join Requests',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._joinRequests.map((r) {
                          final name =
                              r['full_name'] as String? ?? 'Unknown';
                          final photoUrl = r['photo_url'] as String?;
                          final zip = r['base_zip_code'] as String?;
                          final message = r['message'] as String?;

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
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (zip != null) Text('ZIP: $zip'),
                                  if (message != null &&
                                      message.trim().isNotEmpty)
                                    Text(
                                      message,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        _rejectJoinRequest(r),
                                    child: const Text('Reject'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _approveJoinRequest(r),
                                    child: const Text('Approve'),
                                  ),
                                ],
                              ),
                              onTap: () {
                                // Tapping join request avatar also opens user's profile
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                      userId: r['user_id'] as String,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      ],

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
                        const Text('No members found.')
                      else
                        ..._members.map((m) {
                          final name = m['full_name'] as String? ?? 'Unknown';
                          final zip = m['base_zip_code'] as String?;
                          final role = m['role'] as String? ?? 'member';
                          final photoUrl = m['photo_url'] as String?;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: (photoUrl != null &&
                                        (photoUrl as String).isNotEmpty)
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: (photoUrl == null ||
                                        (photoUrl as String).isEmpty)
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                      )
                                    : null,
                              ),
                              title: Text(name),
                              subtitle:
                                  zip != null ? Text('ZIP: $zip') : null,
                              trailing: _buildRoleChip(role),

                              // 👇 Tap member → open their profile
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                      userId: m['user_id'] as String,
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
