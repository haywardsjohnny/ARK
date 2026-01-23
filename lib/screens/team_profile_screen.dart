import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'user_profile_screen.dart';
import 'teams_screen.dart';
import 'home_tabs/home_tabs_screen.dart';

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
  List<Map<String, dynamic>> _friendlyTeams = []; // Mutually following teams (approved)
  List<Map<String, dynamic>> _teamsToFollow = []; // Teams in same sport that can be followed
  List<Map<String, dynamic>> _followRequests = []; // Pending follow requests for this team
  Set<String> _localPendingRequests = {}; // Local cache of pending requests (for immediate UI updates)

  String? _currentUserId;
  bool _isMember = false;
  bool _hasPendingJoinRequest = false;
  bool _isFollowing = false;
  bool _loadingFriendlyTeams = false;
  bool _isAdminOfThisTeam = false; // Whether current user is admin of the team being viewed
  bool _isAdminOfAnyTeam = false; // Whether current user is admin of any team
  bool _isAdminOfTeamInSameSport = false; // Whether current user is admin of any team in the same sport as viewed team
  String? _adminTeamId; // The team ID where current user is admin (for following other teams)
  String? _adminTeamIdInSameSport; // The team ID where current user is admin in the same sport as viewed team

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
            'id, name, sport, description, proficiency_level, zip_code, base_city, team_number, created_by',
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

      // 3) Load user details for all member user_ids using RPC function for better display names
      final userIds = membersList.map((m) => m['user_id'] as String).toList();
      Map<String, Map<String, dynamic>> userById = {};

      if (userIds.isNotEmpty) {
        bool rpcSuccess = false;
        try {
          // Try using the RPC function first for better display names (includes email fallback)
          final displayNamesResult = await supa.rpc(
            'get_user_display_names',
            params: {'p_user_ids': userIds},
          );
          
          if (displayNamesResult is List && displayNamesResult.isNotEmpty) {
            rpcSuccess = true;
            if (kDebugMode) {
              print('[DEBUG] RPC returned ${displayNamesResult.length} user display names for ${userIds.length} requested users');
            }
            for (final u in displayNamesResult) {
              final uid = u['user_id'] as String?;
              final displayName = u['display_name'] as String?;
              if (uid != null && displayName != null) {
                userById[uid] = {
                  'full_name': displayName, // Use display_name from RPC (includes email fallback)
                  'photo_url': u['photo_url'] as String?,
                  'base_zip_code': null, // RPC doesn't return this, fetch separately if needed
                };
                if (kDebugMode) {
                  print('[DEBUG] User $uid: display_name = $displayName');
                }
              }
            }
          } else {
            if (kDebugMode) {
              print('[DEBUG] RPC returned empty or invalid result: $displayNamesResult');
            }
          }
        } catch (e) {
          // Log error for debugging
          if (kDebugMode) {
            print('[DEBUG] Failed to fetch user display names via RPC: $e');
            print('[DEBUG] RPC error details: ${e.toString()}');
          }
          // Fallback to regular query if RPC fails (will only return current user due to RLS)
        }
        
        // Fetch photo_url and base_zip_code for users we got from RPC
        // Only fetch for users we already have in userById
        final fetchedUserIds = userById.keys.toList();
        if (fetchedUserIds.isNotEmpty) {
          try {
        final usersRows = await supa
            .from('users')
            .select('id, full_name, photo_url, base_zip_code')
                .inFilter('id', fetchedUserIds);

        for (final u in usersRows as List) {
              final uid = u['id'] as String;
              if (userById.containsKey(uid)) {
                // Update with photo_url and base_zip_code
                userById[uid]!['photo_url'] = u['photo_url'];
                userById[uid]!['base_zip_code'] = u['base_zip_code'];
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('[DEBUG] Failed to fetch photo_url/base_zip_code: $e');
            }
          }
        }
        
        // For users not fetched by RPC, try direct query (will only work for current user due to RLS)
        final missingUserIds = userIds.where((id) => !userById.containsKey(id)).toList();
        if (missingUserIds.isNotEmpty) {
          try {
            final usersRows = await supa
                .from('users')
                .select('id, full_name, photo_url, base_zip_code')
                .inFilter('id', missingUserIds);

            for (final u in usersRows as List) {
              final uid = u['id'] as String;
              userById[uid] = {
            'full_name': u['full_name'],
            'photo_url': u['photo_url'],
            'base_zip_code': u['base_zip_code'],
          };
            }
          } catch (e) {
            if (kDebugMode) {
              print('[DEBUG] Failed to fetch missing users: $e');
            }
          }
        }
      }

      // 4) Combine member+user data
      final combinedMembers = <Map<String, dynamic>>[];
      for (final m in membersList) {
        final uid = m['user_id'] as String;
        final userInfo = userById[uid] ?? {};
        // Use display_name from RPC if available, otherwise use full_name, otherwise fallback
        String displayName = userInfo['full_name'] as String? ?? '';
        if (displayName.trim().isEmpty) {
          // Use a shorter, more readable user identifier as last resort
          displayName = 'User ${uid.substring(0, 8)}';
        }
        combinedMembers.add({
          'user_id': uid,
          'role': m['role'],
          'full_name': displayName,
          'photo_url': userInfo['photo_url'],
          'base_zip_code': userInfo['base_zip_code'],
        });
      }

      // 5) Determine current user info (admin? member?)
      String? currentUserId = user?.id;
      bool isAdmin = false;
      bool isMember = false;
      bool isAdminOfThisTeam = false;
      bool isAdminOfAnyTeam = false;
      bool isAdminOfTeamInSameSport = false;
      String? adminTeamId; // Declare outside if block so it's accessible later
      String? adminTeamIdInSameSport; // Declare outside if block so it's accessible later

      if (currentUserId != null) {
        for (final m in combinedMembers) {
          if (m['user_id'] == currentUserId) {
            isMember = true;
            final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
            if (role == 'admin') {
              isAdmin = true;
              isAdminOfThisTeam = true;
            }
          }
        }
        
        // Check if user is admin of ANY team (not just this one)
        try {
          final adminTeamsResult = await supa
              .from('team_members')
              .select('team_id')
              .eq('user_id', currentUserId)
              .eq('role', 'admin');
          isAdminOfAnyTeam = (adminTeamsResult as List).isNotEmpty;
          if (isAdminOfAnyTeam && (adminTeamsResult as List).isNotEmpty) {
            // Get the first admin team ID (or could let user choose)
            adminTeamId = (adminTeamsResult as List).first['team_id'] as String?;
          }
        } catch (e) {
          // If check fails, assume false
          isAdminOfAnyTeam = false;
          adminTeamId = null;
        }
        
        // Check if user is admin of ANY team in the SAME sport as the viewed team
        final viewedTeamSport = teamRow['sport'] as String?;
        if (viewedTeamSport != null && isAdminOfAnyTeam) {
          try {
            // Get all teams where user is admin
            final adminTeamsResult = await supa
                .from('team_members')
                .select('team_id')
                .eq('user_id', currentUserId)
                .eq('role', 'admin');
            
            if ((adminTeamsResult as List).isNotEmpty) {
              final adminTeamIds = (adminTeamsResult as List)
                  .map<String>((t) => t['team_id'] as String)
                  .toList();
              
              // Check which of these teams are in the same sport
              final teamsInSameSport = await supa
                  .from('teams')
                  .select('id')
                  .inFilter('id', adminTeamIds)
                  .eq('sport', viewedTeamSport);
              
              if ((teamsInSameSport as List).isNotEmpty) {
                isAdminOfTeamInSameSport = true;
                adminTeamIdInSameSport = (teamsInSameSport as List).first['id'] as String?;
              }
            }
          } catch (e) {
            // If check fails, assume false
            isAdminOfTeamInSameSport = false;
            adminTeamIdInSameSport = null;
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

      // Check if user is following this team
      bool isFollowing = false;
      if (currentUserId != null && !isMember) {
        try {
          final followRow = await supa
              .from('team_followers')
              .select('id')
              .eq('user_id', currentUserId)
              .eq('team_id', widget.teamId)
              .maybeSingle();
          isFollowing = followRow != null;
        } catch (_) {
          // If team_followers table doesn't exist yet, assume not following
          isFollowing = false;
        }
      }

      // Load friendly teams (only mutually following teams - both teams have approved follows)
      // Only show for own team - when viewing other teams, don't show friendly teams
      List<Map<String, dynamic>> friendlyTeams = [];
      if (isAdminOfThisTeam) {
        try {
          if (kDebugMode) {
            print('[DEBUG] Loading connected teams for team: ${widget.teamId}');
          }
          
          // Try RPC function first, but always verify with direct query
          try {
            final friendlyResult = await supa.rpc(
              'get_mutually_following_teams',
              params: {'team_id_param': widget.teamId},
            );
            if (kDebugMode) {
              print('[DEBUG] get_mutually_following_teams RPC result: $friendlyResult');
              print('[DEBUG] Result type: ${friendlyResult.runtimeType}');
            }
            if (friendlyResult is List) {
              if (kDebugMode) {
                print('[DEBUG] Found ${friendlyResult.length} connected teams via RPC');
              }
              friendlyTeams = friendlyResult.map<Map<String, dynamic>>((t) {
                return {
                  'id': t['team_id'] as String,
                  'name': t['team_name'] as String? ?? '',
                  'sport': t['sport'] as String? ?? '',
                  'base_city': t['base_city'] as String? ?? '',
                  'proficiency_level': t['proficiency_level'] as String? ?? '',
                };
              }).toList();
              if (kDebugMode) {
                print('[DEBUG] Processed ${friendlyTeams.length} connected teams from RPC');
              }
            } else {
              if (kDebugMode) {
                print('[DEBUG] RPC result is not a List: $friendlyResult');
              }
            }
          } catch (rpcError) {
            if (kDebugMode) {
              print('[DEBUG] RPC failed: $rpcError');
            }
          }
          
          // Always verify with direct query (especially if RPC returned empty)
          // This helps debug and ensures we catch any data that exists
          try {
            if (kDebugMode) {
              print('[DEBUG] Verifying with direct query to team_follows...');
            }
            
            // Get teams this team follows
            final followingRows = await supa
                .from('team_follows')
                .select('followed_team_id')
                .eq('follower_team_id', widget.teamId);
            
            if (kDebugMode) {
              print('[DEBUG] Direct query - teams this team follows: $followingRows');
            }
            
            if (followingRows is List && followingRows.isNotEmpty) {
              final followedTeamIds = followingRows
                  .map<String>((r) => r['followed_team_id'] as String)
                  .toList();
              
              if (kDebugMode) {
                print('[DEBUG] Followed team IDs: $followedTeamIds');
              }
              
              // For each followed team, check if they also follow this team back
              for (final followedTeamId in followedTeamIds) {
                final reverseFollow = await supa
                    .from('team_follows')
                    .select('follower_team_id')
                    .eq('follower_team_id', followedTeamId)
                    .eq('followed_team_id', widget.teamId)
                    .maybeSingle();
                
                if (kDebugMode) {
                  print('[DEBUG] Checking reverse follow for $followedTeamId: $reverseFollow');
                }
                
                if (reverseFollow != null) {
                  // Mutual follow found - get team details
                  final teamDetails = await supa
                      .from('teams')
                      .select('id, name, sport, base_city, proficiency_level')
                      .eq('id', followedTeamId)
                      .maybeSingle();
                  
                  if (teamDetails != null) {
                    // Check if already in list (from RPC)
                    final existingIndex = friendlyTeams.indexWhere((t) => t['id'] == followedTeamId);
                    if (existingIndex == -1) {
                      friendlyTeams.add({
                        'id': teamDetails['id'] as String,
                        'name': teamDetails['name'] as String? ?? '',
                        'sport': teamDetails['sport'] as String? ?? '',
                        'base_city': teamDetails['base_city'] as String? ?? '',
                        'proficiency_level': teamDetails['proficiency_level'] as String? ?? '',
                      });
                    }
                  }
                }
              }
              
              if (kDebugMode) {
                print('[DEBUG] Found ${friendlyTeams.length} total connected teams (RPC + direct query)');
              }
            } else {
              if (kDebugMode) {
                print('[DEBUG] Direct query returned empty or invalid result');
              }
            }
          } catch (directQueryError) {
            if (kDebugMode) {
              print('[DEBUG] Direct query failed: $directQueryError');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[DEBUG] Error loading friendly teams: $e');
            print('[DEBUG] Error type: ${e.runtimeType}');
          }
        }
      }

      // Load pending follow requests (only if current user is admin of this team)
      List<Map<String, dynamic>> followRequests = [];
      if (isAdminOfThisTeam) {
        try {
          if (kDebugMode) {
            print('[DEBUG] Loading follow requests for team: ${widget.teamId}');
          }
          
          // Use direct table query (bypasses RPC schema cache issues)
          final followReqRows = await supa
              .from('team_follow_requests')
              .select('id, requesting_team_id, target_team_id, created_at, status')
              .eq('target_team_id', widget.teamId)
              .eq('status', 'pending');
          
          if (kDebugMode) {
            print('[DEBUG] Follow requests query result: ${followReqRows is List ? (followReqRows as List).length : 'not a list'}');
            if (followReqRows is List && followReqRows.isNotEmpty) {
              print('[DEBUG] Found ${(followReqRows as List).length} pending follow requests');
              for (final r in followReqRows as List) {
                print('[DEBUG]   - Request ID: ${r['id']}, Requesting Team: ${r['requesting_team_id']}, Status: ${r['status']}');
              }
            }
          }
          
          if (followReqRows is List && followReqRows.isNotEmpty) {
            // Get team details for each requesting team
            final requestingTeamIds = (followReqRows as List)
                .map<String>((r) => r['requesting_team_id'] as String)
                .toList();
            
            if (kDebugMode) {
              print('[DEBUG] Fetching details for ${requestingTeamIds.length} requesting teams');
            }
            
            final teamDetails = await supa
                .from('teams')
                .select('id, name, sport, base_city')
                .inFilter('id', requestingTeamIds);
            
            final teamMap = <String, Map<String, dynamic>>{};
            if (teamDetails is List) {
              for (final team in teamDetails) {
                teamMap[team['id'] as String] = team;
              }
              if (kDebugMode) {
                print('[DEBUG] Loaded ${teamMap.length} team details');
              }
            }
            
            // Combine request data with team details
            followRequests = (followReqRows as List).map<Map<String, dynamic>>((r) {
              final requestingTeamId = r['requesting_team_id'] as String;
              final teamInfo = teamMap[requestingTeamId] ?? {};
              
              if (kDebugMode && teamInfo.isEmpty) {
                print('[DEBUG] WARNING: No team info found for requesting team: $requestingTeamId');
              }
              
              return {
                'request_id': r['id'] as String,
                'requesting_team_id': requestingTeamId,
                'requesting_team_name': teamInfo['name'] as String? ?? 'Unknown Team',
                'requesting_team_sport': teamInfo['sport'] as String? ?? '',
                'requesting_team_base_city': teamInfo['base_city'] as String? ?? '',
                'created_at': r['created_at'] as String? ?? '',
              };
            }).toList();
            
            if (kDebugMode) {
              print('[DEBUG] Final follow requests list: ${followRequests.length} requests');
            }
          } else {
            if (kDebugMode) {
              print('[DEBUG] No pending follow requests found for team ${widget.teamId}');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[DEBUG] Error loading follow requests: $e');
            print('[DEBUG] Error type: ${e.runtimeType}');
          }
          // If table not in cache, try to show a message or handle gracefully
          followRequests = [];
        }
      } else {
        if (kDebugMode) {
          print('[DEBUG] Not loading follow requests - user is not admin of this team');
        }
      }

      setState(() {
        _team = Map<String, dynamic>.from(teamRow);
        _members = combinedMembers;
        _isAdmin = isAdmin;
        _joinRequests = joinRequests;
        _followRequests = followRequests;
        _currentUserId = currentUserId;
        _isMember = isMember;
        _hasPendingJoinRequest = hasPendingJoinRequest;
        _isFollowing = isFollowing;
        _friendlyTeams = friendlyTeams;
        _isAdminOfThisTeam = isAdminOfThisTeam;
        _isAdminOfAnyTeam = isAdminOfAnyTeam;
        _isAdminOfTeamInSameSport = isAdminOfTeamInSameSport;
        _adminTeamId = adminTeamId;
        _adminTeamIdInSameSport = adminTeamIdInSameSport;
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
        label: Text('Admin', style: const TextStyle(color: Colors.white)),
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

  Future<void> _shareTeam() async {
    if (_team == null) return;
    
    final teamName = _team!['name'] as String? ?? 'Team';
    final shareText = 'Check out $teamName on SportsDug!';
    final shareLink = 'https://sportsdug.app/team/${widget.teamId}';
    
    try {
      await Share.share(
        '$shareText\n$shareLink',
        subject: '$teamName on SportsDug',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: $e')),
      );
    }
  }

  Future<void> _followTeam() async {
    if (_currentUserId == null) return;
    
    final supa = Supabase.instance.client;
    try {
      await supa.from('team_followers').insert({
        'user_id': _currentUserId,
        'team_id': widget.teamId,
      });
      
      setState(() {
        _isFollowing = true;
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Following team')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to follow team: $e')),
      );
    }
  }

  Future<void> _unfollowTeam() async {
    if (_currentUserId == null) return;
    
    final supa = Supabase.instance.client;
    final userId = _currentUserId!;
    try {
      await supa
          .from('team_followers')
          .delete()
          .eq('user_id', userId)
          .eq('team_id', widget.teamId);
      
      setState(() {
        _isFollowing = false;
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unfollowed team')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unfollow team: $e')),
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

  // Request to follow another team (admin only) - creates a request instead of direct follow
  Future<void> _requestToFollowTeam(String targetTeamId) async {
    if (_team == null || !_isAdminOfThisTeam) return;
    final supa = Supabase.instance.client;

    // Add to local cache immediately for UI responsiveness
    _localPendingRequests.add(targetTeamId);
    setState(() {}); // Update UI immediately

    try {
      if (kDebugMode) {
        print('[DEBUG] Creating follow request: requesting_team_id=${widget.teamId}, target_team_id=$targetTeamId');
      }
      
      // Use direct table INSERT instead of RPC to bypass PostgREST schema cache issues
      final insertResult = await supa
          .from('team_follow_requests')
          .insert({
            'requesting_team_id': widget.teamId,
            'target_team_id': targetTeamId,
            'status': 'pending',
          })
          .select();

      if (kDebugMode) {
        print('[DEBUG] Follow request insert result: $insertResult');
      }

      if (!mounted) return;
      
      // Request successfully created in database - remove from local cache (DB now has it)
      _localPendingRequests.remove(targetTeamId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request sent')),
      );
      
      // Reload teams to follow list to sync with database
      await _loadTeamsToFollow();
      
      // Reload team profile so admins of target team can see the new request
      await _loadTeamProfile();
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString();
      
      // If it's a duplicate/conflict error, that's okay - request already exists
      if (errorMsg.contains('duplicate') || errorMsg.contains('unique') || errorMsg.contains('already exists')) {
        // Request already exists in DB, keep it in local cache
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request already sent')),
        );
        await _loadTeamsToFollow();
      } else if (errorMsg.contains('schema cache') || errorMsg.contains('not found') || errorMsg.contains('PGRST')) {
        // Table/function not in cache yet - keep in local cache, will sync later
        // Don't show error - just keep the pending state locally
        // The request will be created when schema cache refreshes
        if (kDebugMode) {
          print('[DEBUG] Schema cache issue - keeping request in local state: $errorMsg');
        }
        // Try RPC as fallback, but don't show error if it fails
        try {
          await supa.rpc(
            'create_team_follow_request',
            params: {
              'requesting_team_id': widget.teamId,
              'target_team_id': targetTeamId,
            },
          );
          await _loadTeamsToFollow();
        } catch (rpcError) {
          // Silently keep in local cache - will sync when schema refreshes
          if (kDebugMode) {
            print('[DEBUG] RPC also failed, keeping in local cache: $rpcError');
          }
        }
      } else {
        // Real error - remove from local cache and show error
        _localPendingRequests.remove(targetTeamId);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send follow request: $e')),
        );
      }
    }
  }

  // Unfollow a team (admin only) - removes the follow relationship
  Future<void> _unfollowTeamAsTeam(String targetTeamId) async {
    if (_team == null || !_isAdminOfThisTeam) return;
    final supa = Supabase.instance.client;

    try {
      // Delete BOTH directions from team_follows (mutual follow relationship)
      // Direction 1: This team follows target team
      await supa
          .from('team_follows')
          .delete()
          .eq('follower_team_id', widget.teamId)
          .eq('followed_team_id', targetTeamId);

      // Direction 2: Target team follows this team (reverse direction)
      await supa
          .from('team_follows')
          .delete()
          .eq('follower_team_id', targetTeamId)
          .eq('followed_team_id', widget.teamId);

      // Also delete any pending requests (ignore if table not in cache yet)
      try {
        await supa
            .from('team_follow_requests')
            .delete()
            .eq('requesting_team_id', widget.teamId)
            .eq('target_team_id', targetTeamId)
            .eq('status', 'pending');
      } catch (e) {
        // Ignore if table not in PostgREST cache yet
        if (kDebugMode) {
          print('[DEBUG] Could not delete from team_follow_requests: $e');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unfollowed team')),
      );
      
      // Reload friendly teams
      await _loadTeamProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unfollow team: $e')),
      );
    }
  }

  // Approve a follow request (admin only)
  Future<void> _approveFollowRequest(Map<String, dynamic> request) async {
    if (_team == null || !_isAdminOfThisTeam) return;
    final supa = Supabase.instance.client;
    final requestId = request['request_id'] as String;

    try {
      // Use RPC function with simplified parameter name
      await supa.rpc(
        'approve_team_follow_request',
        params: {'request_id': requestId},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved follow request from ${request['requesting_team_name']}')),
      );

      await _loadTeamProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve request: $e')),
      );
    }
  }

  // Reject a follow request (admin only)
  Future<void> _rejectFollowRequest(Map<String, dynamic> request) async {
    if (_team == null || !_isAdminOfThisTeam) return;
    final supa = Supabase.instance.client;
    final requestId = request['request_id'] as String;

    try {
      // Use RPC function with simplified parameter name
      await supa.rpc(
        'reject_team_follow_request',
        params: {'request_id': requestId},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rejected follow request from ${request['requesting_team_name']}')),
      );

      await _loadTeamProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject request: $e')),
      );
    }
  }

  // Load teams in same sport that can be followed (excluding teams where user is admin)
  Future<void> _loadTeamsToFollow() async {
    if (_team == null || !_isAdminOfThisTeam) {
      if (kDebugMode) {
        print('[DEBUG] _loadTeamsToFollow: Cannot load - team=${_team != null}, isAdmin=${_isAdminOfThisTeam}');
      }
      return;
    }
    setState(() => _loadingFriendlyTeams = true);

    final supa = Supabase.instance.client;
    final sport = _team!['sport'] as String?;
    if (kDebugMode) {
      print('[DEBUG] _loadTeamsToFollow: sport=$sport, teamId=${widget.teamId}, currentUserId=$_currentUserId');
    }
    
    if (sport == null || sport.isEmpty || _currentUserId == null) {
      if (kDebugMode) {
        print('[DEBUG] _loadTeamsToFollow: Invalid sport or userId - sport=$sport, userId=$_currentUserId');
      }
      setState(() => _loadingFriendlyTeams = false);
      return;
    }

    try {
      // Get teams where user is admin (to exclude them)
      final adminTeamsResult = await supa
          .from('team_members')
          .select('team_id')
          .eq('user_id', _currentUserId!)
          .eq('role', 'admin');
      
      final adminTeamIds = (adminTeamsResult as List)
          .map<String>((t) => t['team_id'] as String)
          .toSet();

      // Get teams we're already following (approved requests)
      final followingResult = await supa
          .from('team_follows')
          .select('followed_team_id')
          .eq('follower_team_id', widget.teamId);
      
      // Get teams that follow us back (mutual follows - these should also be excluded)
      final followedByResult = await supa
          .from('team_follows')
          .select('follower_team_id')
          .eq('followed_team_id', widget.teamId);
      
      // Get pending requests to track which teams have pending requests
      // We'll use this to show "Pending Approval" button and exclude from list
      Map<String, String> pendingRequestIds = {}; // team_id -> request_id
      List<dynamic> pendingRequestsResult = [];
      try {
        pendingRequestsResult = await supa
            .from('team_follow_requests')
            .select('id, target_team_id')
            .eq('requesting_team_id', widget.teamId)
            .eq('status', 'pending') as List<dynamic>;
        
        if (pendingRequestsResult is List) {
          for (final r in pendingRequestsResult) {
            final targetId = r['target_team_id'] as String?;
            final requestId = r['id'] as String?;
            if (targetId != null && requestId != null) {
              pendingRequestIds[targetId] = requestId;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DEBUG] team_follow_requests table not available yet (PostgREST cache): $e');
        }
      }
      
      // Teams to exclude from the list:
      // 1. Teams we already follow (approved requests)
      // 2. Teams that follow us back (mutual follows - already connected)
      // Note: Teams with pending requests are NOT excluded - they stay in list with "Pending Approval" button
      final excludedTeamIds = <String>{};
      if (followingResult is List) {
        for (final f in followingResult) {
          excludedTeamIds.add(f['followed_team_id'] as String);
        }
      }
      if (followedByResult is List) {
        for (final f in followedByResult) {
          excludedTeamIds.add(f['follower_team_id'] as String);
        }
      }
      
      if (kDebugMode) {
        print('[DEBUG] Teams we follow: ${followingResult is List ? (followingResult as List).map((f) => f['followed_team_id']).toList() : []}');
        print('[DEBUG] Teams that follow us: ${followedByResult is List ? (followedByResult as List).map((f) => f['follower_team_id']).toList() : []}');
        print('[DEBUG] Total excluded teams (already connected): $excludedTeamIds');
      }

      if (kDebugMode) {
        print('[DEBUG] Loading teams to follow: sport=$sport, adminTeamIds=$adminTeamIds, excludedTeamIds=$excludedTeamIds');
      }

      // Get all teams in same sport (excluding ourselves, teams where user is admin, and teams we already follow/have requests for)
      // First, let's verify what teams exist in this sport
      if (kDebugMode) {
        final allTeamsInSport = await supa
            .from('teams')
            .select('id, name, sport')
            .eq('sport', sport);
        print('[DEBUG] All teams in sport "$sport": ${(allTeamsInSport as List).length}');
        for (final t in (allTeamsInSport as List)) {
          print('[DEBUG]   - ${t['name']} (${t['id']})');
        }
      }
      
      final teamsResult = await supa
          .from('teams')
          .select('id, name, sport, base_city, proficiency_level')
          .eq('sport', sport)
          .neq('id', widget.teamId);

      if (kDebugMode) {
        print('[DEBUG] Found ${(teamsResult as List).length} teams in sport "$sport" (excluding current team ${widget.teamId})');
        for (final t in (teamsResult as List)) {
          print('[DEBUG]   - ${t['name']} (${t['id']})');
        }
      }

      // Ensure teamsResult is a List
      final teamsList = teamsResult is List ? teamsResult : <dynamic>[];
      
      if (kDebugMode) {
        print('[DEBUG] Before filtering: ${teamsList.length} teams');
        print('[DEBUG] Admin team IDs to exclude: $adminTeamIds');
        print('[DEBUG] Excluded team IDs (already following): $excludedTeamIds');
      }
      
      final teams = teamsList
          .where((t) {
            final teamId = t['id'] as String?;
            if (teamId == null) return false;
            
            final isExcluded = adminTeamIds.contains(teamId) || excludedTeamIds.contains(teamId);
            if (kDebugMode) {
              if (isExcluded) {
                print('[DEBUG] Excluding team ${t['name']}: adminTeam=${adminTeamIds.contains(teamId)}, excluded=${excludedTeamIds.contains(teamId)}');
              } else {
                print('[DEBUG] Including team ${t['name']} (${teamId})');
              }
            }
            return !isExcluded;
          })
          .map<Map<String, dynamic>>((t) {
            final teamId = t['id'] as String;
            // Check both database and local cache for pending requests
            final hasPendingInDb = pendingRequestIds.containsKey(teamId);
            final hasPendingLocally = _localPendingRequests.contains(teamId);
            return {
              'id': teamId,
              'name': t['name'] as String? ?? '',
              'sport': t['sport'] as String? ?? '',
              'base_city': t['base_city'] as String? ?? '',
              'proficiency_level': t['proficiency_level'] as String? ?? '',
              'has_pending_request': hasPendingInDb || hasPendingLocally,
              'pending_request_id': pendingRequestIds[teamId],
            };
          }).toList();

      if (kDebugMode) {
        print('[DEBUG] Final teams to follow: ${teams.length} teams');
        for (final team in teams) {
          print('[DEBUG]   - ${team['name']} (${team['id']})');
        }
      }

      setState(() {
        _teamsToFollow = teams;
        _loadingFriendlyTeams = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('[DEBUG] Error loading teams to follow: $e');
        print('[DEBUG] Stack trace: ${StackTrace.current}');
      }
      setState(() => _loadingFriendlyTeams = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading teams: $e')),
      );
    }
  }

  // Get clean team name without ID (remove anything in parentheses at the end)
  String _getCleanTeamName(String? name) {
    if (name == null) return '';
    // Remove pattern like "(6)" at the end
    return name.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');
  }

  // Build statistics item widget
  Widget _buildStatItem({required IconData icon, required String label, required String value}) {
    return Column(
      children: [
        Icon(icon, color: Colors.green.shade700, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // Build about section item with bullet point
  Widget _buildAboutItem(String text) {
    const teal = Color(0xFF0E8E8E);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // Decreased spacing between lines
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 8, right: 8), // Adjusted top margin for larger font
            decoration: BoxDecoration(
              color: teal, // Light green bullet
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16, // Increased font size
                color: Color(0xFF0F2E2E), // Dark gray/black text
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamNameForTitle = _team != null 
        ? _getCleanTeamName(_team!['name'] as String?) 
        : _getCleanTeamName(widget.teamName);

    final userIsMember = _isMember;

    const teal = Color(0xFF0E8E8E);
    const tealDark = Color(0xFF0E7C7B);
    
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _team == null
              ? const Center(child: Text('Team not found'))
              : RefreshIndicator(
                  onRefresh: _loadTeamProfile,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final screenHeight = MediaQuery.of(context).size.height;
                      final topSectionHeight = screenHeight * 0.20;
                      return Stack(
                        children: [
                          Column(
                            children: [
                              // Top 20% green background section with gradient
                              Container(
                                height: topSectionHeight,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      tealDark, // Darker teal at top
                                      teal,     // Lighter teal at bottom
                                    ],
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Back button at top
                                      IconButton(
                                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                                        onPressed: () => Navigator.of(context).pop(),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // Team Logo (circular with initial or icon) - left side
                                          Container(
                                            width: 60,
                                            height: 60,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              _getCleanTeamName(_team!['name'] as String?)
                                                  .isNotEmpty
                                                  ? _getCleanTeamName(_team!['name'] as String?)[0].toUpperCase()
                                                  : 'T',
                                              style: TextStyle(
                                                color: tealDark,
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Name, Edit button, Share button on same row, Base City below
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Team name, Edit button, and Share button on same row
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      _getCleanTeamName(_team!['name'] as String?),
                                                      style: const TextStyle(
                                                        fontSize: 24,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // Edit button
                                                  if (_isAdmin)
                                                    InkWell(
                                                      onTap: () {
                                                        Navigator.of(context).push(
                                                          MaterialPageRoute(
                                                            builder: (_) => TeamManagementScreen(
                                                              teamId: widget.teamId,
                                                              teamName: widget.teamName,
                                                            ),
                                                          ),
                                                        ).then((_) {
                                                          _loadTeamProfile();
                                                        });
                                                      },
                                                      borderRadius: BorderRadius.circular(12),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: tealDark,
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.edit, size: 16, color: Colors.white),
                                                            SizedBox(width: 4),
                                                            Text(
                                                              'Edit',
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight: FontWeight.w600,
                                                                color: Colors.white,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  const SizedBox(width: 8),
                                                  // Share button
                                                  Container(
                                                    width: 40,
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      color: tealDark,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(Icons.share, color: Colors.white, size: 20),
                                                      onPressed: _shareTeam,
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // Base City below
                                              if (_team!['base_city'] != null && (_team!['base_city'] as String).isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.location_on, size: 16, color: Colors.white),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        _team!['base_city'] as String,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          color: Colors.white,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              // Join button or Request Admin Rights button below edit
                                              const SizedBox(height: 8),
                                              if (!_isAdmin && !userIsMember && _currentUserId != null)
                                                _hasPendingJoinRequest
                                                    ? OutlinedButton.icon(
                                                        onPressed: null,
                                                        icon: const Icon(Icons.hourglass_top, color: Colors.white, size: 16),
                                                        label: const Text(
                                                          'Join request pending',
                                                          style: TextStyle(color: Colors.white, fontSize: 12),
                                                        ),
                                                        style: OutlinedButton.styleFrom(
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                          side: const BorderSide(color: Colors.white),
                                                        ),
                                                      )
                                                    : ElevatedButton.icon(
                                                        onPressed: _sendJoinRequest,
                                                        icon: const Icon(Icons.group_add_outlined, color: Colors.white, size: 16),
                                                        label: const Text(
                                                          'Request to join team',
                                                          style: TextStyle(color: Colors.white, fontSize: 12),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: tealDark,
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                        ),
                                                      ),
                                              // Non-admin members can request admin rights
                                              if (!_isAdmin && userIsMember)
                                                TextButton.icon(
                                                  onPressed: _requestAdminRights,
                                                  icon: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white, size: 16),
                                                  label: const Text(
                                                    'Request admin rights',
                                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                                  ),
                                                  style: TextButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    ], // Close Column's children array (inside Container)
                                  ),
                                ),
                              ), // Close Container
                              // Spacer to account for overlapping chip
                              SizedBox(height: 50),
                              // Rest of content with white background
                              Expanded(
                                child: Container(
                                  color: Colors.white,
                                  child: ListView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.only(top: 466), // Padding to account for overlapping chip, About box, Connected Teams chip, and Members chip
                                    children: [
                                      // Join Requests (only visible to admins)
                                      if (_isAdmin && _joinRequests.isNotEmpty) ...[
                                        Container(
                                          color: Colors.white,
                                          margin: const EdgeInsets.only(top: 8),
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Join Requests',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              ..._joinRequests.map((r) {
                                                final name = r['full_name'] as String? ?? 'Unknown';
                                                final message = r['message'] as String?;

                                                return Card(
                                                  color: Colors.white,
                                                  margin: const EdgeInsets.only(bottom: 8),
                                                  child: ListTile(
                                                    title: Text(name),
                                                    subtitle: message != null && message.trim().isNotEmpty
                                                        ? Text(
                                                            message,
                                                            style: const TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.grey,
                                                            ),
                                                          )
                                                        : null,
                                                    trailing: Wrap(
                                                      spacing: 4,
                                                      children: [
                                                        TextButton(
                                                          onPressed: () => _rejectJoinRequest(r),
                                                          child: const Text('Reject'),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () => _approveJoinRequest(r),
                                                          child: const Text('Approve'),
                                                        ),
                                                      ],
                                                    ),
                                                    onTap: () {
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
                                          ),
                                        ),
                                      ],

                                      const SizedBox(height: 80), // Space for floating button
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                      // Stats chip section (Matches, Members, Connections) - positioned to overlap green background
                      Positioned(
                        top: topSectionHeight - 50, // Position so half overlaps (chip height is 100, so -50 puts it halfway)
                        left: 16,
                        right: 16,
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
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
                          child: Row(
                            children: [
                              // Matches
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(Icons.sports_cricket, size: 28, color: tealDark),
                                          const SizedBox(width: 8),
                                          Text(
                                            '0', // TODO: Get actual match count
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 28,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F2E2E),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Matches',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F2E2E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, color: Colors.grey.shade200),
                              // Members
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(Icons.people, size: 28, color: tealDark),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_members.length}',
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 28,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F2E2E),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Members',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F2E2E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Container(width: 1, color: Colors.grey.shade200),
                              // Connections
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(Icons.link, size: 28, color: tealDark),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_friendlyTeams.length}',
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 28,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F2E2E),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Connections',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F2E2E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // About section box - bigger than matches chip, positioned right below it
                      Positioned(
                        top: topSectionHeight - 50 + 100 + 16, // Below the stats chip (100px height + 16px spacing)
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About ${_getCleanTeamName(_team!['name'] as String?)}',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: tealDark,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Description
                              if (_team!['description'] != null && (_team!['description'] as String).trim().isNotEmpty)
                                _buildAboutItem(_team!['description'] as String),
                              // Proficiency Level
                              if (_team!['proficiency_level'] != null)
                                _buildAboutItem('${_team!['proficiency_level']} Level'),
                              // Open to league & friendly matches
                              _buildAboutItem('Open to league & friendly matches'),
                            ],
                          ),
                        ),
                      ),
                      // Connected Teams chip - similar to matches chip, positioned below About section
                      Positioned(
                        top: topSectionHeight - 50 + 100 + 16 + 150, // Below About section (estimated height ~150px)
                        left: 16,
                        right: 16,
                        child: Container(
                          height: 100, // Same height as matches chip
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Heading
                              Text(
                                'Connected Teams',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: tealDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Connected teams as small chips
                              if (_friendlyTeams.isEmpty)
                                const Text(
                                  'No connected teams',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                )
                              else
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _friendlyTeams.map((team) {
                                        final teamName = team['name'] as String? ?? '';
                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => TeamProfileScreen(
                                                  teamId: team['id'] as String,
                                                  teamName: teamName,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.only(right: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: teal.withOpacity(0.2), // Light green background
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              teamName,
                                              style: const TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 16, // Big font
                                                fontWeight: FontWeight.bold, // Bold
                                                color: Color(0xFF0F2E2E),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Members chip - similar to matches chip, positioned below Connected Teams
                      Positioned(
                        top: topSectionHeight - 50 + 100 + 16 + 150 + 100 + 16, // Below Connected Teams chip (100px height + 16px spacing)
                        left: 16,
                        right: 16,
                        child: Container(
                          height: 100, // Same height as matches chip
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Heading
                              Text(
                                'Members (${_members.length})',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: tealDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Members as small squares with names
                              if (_members.isEmpty)
                                const Text(
                                  'No members',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                )
                              else
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _members.map((m) {
                                        final name = m['full_name'] as String? ?? 'Unknown';
                                        final role = m['role'] as String? ?? 'member';
                                        final isAdminRole = role.toLowerCase() == 'admin';
                                        
                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => UserProfileScreen(
                                                  userId: m['user_id'] as String,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.only(right: 12),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Small square with rounded corners
                                                Container(
                                                  width: 50,
                                                  height: 50,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade200,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    Icons.person,
                                                    size: 30,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                // Member name in bold, matching matches chip style
                                                Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold, // Bold
                                                    color: isAdminRole ? Colors.blue : Color(0xFF0F2E2E), // Match matches chip color
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
      // Floating action button for admins to connect/follow other teams
      floatingActionButton: _isAdminOfThisTeam
          ? Container(
              margin: const EdgeInsets.only(bottom: 16, right: 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tealDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.link),
                label: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Connect Teams'),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
                onPressed: () async {
                // Load teams first, then show modal
                setState(() => _loadingFriendlyTeams = true);
                await _loadTeamsToFollow();
                if (!mounted) return;
                
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) {
                    return StatefulBuilder(
                      builder: (ctx, setSheetState) {
                        // Reload teams when modal opens to ensure fresh data
                        if (!_loadingFriendlyTeams && _teamsToFollow.isEmpty) {
                          // Try reloading once more
                          Future.microtask(() async {
                            await _loadTeamsToFollow();
                            if (mounted) {
                              setSheetState(() {});
                            }
                          });
                        }
                        
                        return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
                            mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                              Text(
                                'Connect with Teams in ${_team?['sport'] ?? 'Same Sport'}',
                                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
                              const Text(
                                'Request to follow other teams. Admins will need to approve your request.',
              style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
                              if (_loadingFriendlyTeams)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (_teamsToFollow.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'No other teams available to follow.',
                                        style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: () async {
                                          setSheetState(() {
                                            _loadingFriendlyTeams = true;
                                          });
                                          await _loadTeamsToFollow();
                                          if (mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                        child: const Text('Refresh'),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                SizedBox(
                                  height: 400,
                                  child: ListView.builder(
                                    itemCount: _teamsToFollow.length,
                                    itemBuilder: (ctx, idx) {
                                      final team = _teamsToFollow[idx];
                                      final teamId = team['id'] as String;
                                      // Check both database state and local cache
                                      final hasPendingInData = team['has_pending_request'] as bool? ?? false;
                                      final hasPendingLocally = _localPendingRequests.contains(teamId);
                                      final hasPendingRequest = hasPendingInData || hasPendingLocally;
                                      
                                      return Card(
                                        child: ListTile(
                                          title: Text(team['name'] as String? ?? ''),
                                          subtitle: Text(
                                            '${team['base_city'] ?? ''} • ${team['proficiency_level'] ?? ''}',
                                          ),
                                          trailing: hasPendingRequest
                                              ? OutlinedButton(
                                                  onPressed: null, // Disabled
                                                  child: const Text('Pending Approval'),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: Colors.grey,
                                                  ),
                                                )
                                              : ElevatedButton(
                                                  onPressed: () async {
                                                    // Immediately update UI in modal
                                                    setSheetState(() {
                                                      _localPendingRequests.add(teamId);
                                                      _teamsToFollow[idx]['has_pending_request'] = true;
                                                    });
                                                    
                                                    // Send the request in background
                                                    await _requestToFollowTeam(teamId);
                                                    
                                                    // Update the modal after request
                                                    if (mounted) {
                                                      setSheetState(() {});
                                                    }
                                                  },
                                                  child: const Text('Request'),
                                                ),
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => TeamProfileScreen(
                                                  teamId: teamId,
                                                  teamName: team['name'] as String? ?? '',
                                                ),
                                              ),
                                            );
                                          },
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
              },
            ),
          )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // Bottom Navigation Bar - matching home tabs style
  Widget _buildBottomNavBar() {
    const orange = Color(0xFFFF8A30); // Orange for active tab
    const white = Color(0xFFFFFFFF); // White for inactive tabs
    const teal = Color(0xFF0E8E8E); // Teal pill background
    
    return Container(
      height: 72, // Fixed height
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Floating pill with margin
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: teal, // Teal background for floating pill
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            icon: Icons.home_filled,
            label: 'Home',
            index: 0,
            activeColor: orange,
            inactiveColor: white,
          ),
          _buildNavItem(
            icon: Icons.sports_esports,
            label: 'My Games',
            index: 1,
            activeColor: orange,
            inactiveColor: white,
          ),
          _buildNavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            index: 2,
            activeColor: orange,
            inactiveColor: white,
          ),
          _buildNavItem(
            icon: Icons.person,
            label: 'Profile',
            index: 3,
            activeColor: orange,
            inactiveColor: white,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    // Team profile is not a tab, so no tab is selected
    final isSelected = false;
    
    return GestureDetector(
      onTap: () {
        // Navigate back to home tabs screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const HomeTabsScreen(),
          ),
          (route) => false, // Remove all previous routes
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : inactiveColor,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}
