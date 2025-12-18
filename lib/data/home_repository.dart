// lib/data/home_repository.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeRepository {
  final SupabaseClient supa;
  HomeRepository(this.supa);

  // -------------------------
  // Basics
  // -------------------------

  Future<String?> getBaseZip(String userId) async {
    final row = await supa
        .from('users')
        .select('base_zip_code')
        .eq('id', userId)
        .maybeSingle();
    return row?['base_zip_code'] as String?;
  }

  Future<Map<String, String?>> getUserNameAndLocation(String userId) async {
    final row = await supa
        .from('users')
        .select('full_name, base_zip_code, photo_url')
        .eq('id', userId)
        .maybeSingle();
    final zipCode = row?['base_zip_code'] as String?;
    final cityName = zipCode != null ? await _getCityNameFromZip(zipCode) : null;
    
    return {
      'name': row?['full_name'] as String?,
      'location': cityName ?? zipCode ?? 'Location',
      'photo_url': row?['photo_url'] as String?,
    };
  }

  /// Convert ZIP code to city name using a free API
  Future<String?> _getCityNameFromZip(String zipCode) async {
    try {
      // Use a free ZIP code lookup API (ZIPCodeAPI - free tier available)
      // Alternative: Use zipcodebase.com or other free services
      final url = Uri.parse('https://api.zippopotam.us/us/$zipCode');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final place = places[0] as Map<String, dynamic>;
          final city = place['place name'] as String?;
          final state = place['state abbreviation'] as String?;
          if (city != null) {
            return state != null ? '$city, $state' : city;
          }
        }
      }
      
      // Fallback: return ZIP code if lookup fails
      return zipCode;
    } catch (e) {
      // If lookup fails, return ZIP code as fallback
      return zipCode;
    }
  }

  Future<List<String>> getUserSports(String userId) async {
    final rows =
        await supa.from('user_sports').select('sport').eq('user_id', userId);
    if (rows is! List) return [];
    return rows.map<String>((r) => r['sport'] as String).toList();
  }

  /// Admin teams for current user
  Future<List<Map<String, dynamic>>> getAdminTeams(String userId) async {
    final memberRows = await supa
        .from('team_members')
        .select('team_id, role')
        .eq('user_id', userId);

    final adminTeamIds = <String>[];
    if (memberRows is List) {
      for (final m in memberRows) {
        final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
        if (role == 'admin') {
          adminTeamIds.add(m['team_id'] as String);
        }
      }
    }
    if (adminTeamIds.isEmpty) return [];

    final teamRows = await supa
        .from('teams')
        .select('id, name, sport, zip_code')
        .inFilter('id', adminTeamIds);

    if (teamRows is! List) return [];
    return teamRows
        .map<Map<String, dynamic>>((t) => {
              'id': t['id'] as String,
              'name': t['name'] as String? ?? '',
              'sport': t['sport'] as String? ?? '',
              'zip_code': t['zip_code'] as String?,
            })
        .toList();
  }

  /// Get all teams user is member of but NOT admin
  Future<List<Map<String, dynamic>>> getNonAdminTeams(String userId) async {
    final memberRows = await supa
        .from('team_members')
        .select('team_id, role')
        .eq('user_id', userId);

    final nonAdminTeamIds = <String>[];
    if (memberRows is List) {
      for (final m in memberRows) {
        final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
        if (role != 'admin') {
          nonAdminTeamIds.add(m['team_id'] as String);
        }
      }
    }
    if (nonAdminTeamIds.isEmpty) return [];

    final teamRows = await supa
        .from('teams')
        .select('id, name, sport, zip_code')
        .inFilter('id', nonAdminTeamIds);

    if (teamRows is! List) return [];
    return teamRows
        .map<Map<String, dynamic>>((t) => {
              'id': t['id'] as String,
              'name': t['name'] as String? ?? '',
              'sport': t['sport'] as String? ?? '',
              'zip_code': t['zip_code'] as String?,
            })
        .toList();
  }

  // -------------------------
  // Invites
  // -------------------------

  /// Pending invites for my admin teams
  Future<List<Map<String, dynamic>>> getPendingInvitesForTeams(
      List<String> teamIds) async {
    if (teamIds.isEmpty) return [];

    final inviteRows = await supa
        .from('instant_request_invites')
        .select('id, request_id, target_team_id, status')
        .inFilter('target_team_id', teamIds)
        .eq('status', 'pending');

    if (inviteRows is! List) return [];

    final invites = <Map<String, dynamic>>[];

    // Batch fetch base requests
    final reqIds = inviteRows
        .map((r) => r['request_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final reqRows = reqIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('instant_match_requests')
            .select(
                'id, team_id, sport, zip_code, mode, start_time_1, start_time_2, venue, status, created_by, creator_id, matched_team_id')
            .inFilter('id', reqIds);

    final Map<String, Map<String, dynamic>> reqById = {};
    final Set<String> requestTeamIds = {};
    if (reqRows is List) {
      for (final r in reqRows) {
        final id = r['id'] as String?;
        if (id != null) {
          reqById[id] = Map<String, dynamic>.from(r);
          final teamId = r['team_id'] as String?;
          if (teamId != null) requestTeamIds.add(teamId);
        }
      }
    }

    // Fetch team names for request teams + target teams
    final allTeamIds = <String>{
      ...requestTeamIds,
      ...teamIds,
    };
    final Map<String, String> teamNameById = {};
    if (allTeamIds.isNotEmpty) {
      final teamRows = await supa
          .from('teams')
          .select('id, name')
          .inFilter('id', allTeamIds.toList());
      if (teamRows is List) {
        for (final t in teamRows) {
          final id = t['id'] as String?;
          if (id != null) teamNameById[id] = (t['name'] as String?) ?? '';
        }
      }
    }

    for (final inv in inviteRows) {
      final reqId = inv['request_id'] as String?;
      if (reqId == null) continue;

      final req = reqById[reqId];
      if (req == null) continue;

      // ignore cancelled requests
      final st = (req['status'] as String?)?.toLowerCase() ?? '';
      if (st == 'cancelled') continue;

      // Skip if another team has already been matched
      // (e.g., Team A invited Team B and Team C, Team B accepted, so Team C's invite should disappear)
      final matchedTeamId = req['matched_team_id'] as String?;
      final inviteTargetTeamId = inv['target_team_id'] as String?;
      if (matchedTeamId != null && matchedTeamId != inviteTargetTeamId) {
        continue; // Another team already accepted this game
      }

      invites.add({
        'id': inv['id'] as String,
        'request_id': reqId,
        'target_team_id': inv['target_team_id'] as String,
        'status': inv['status'] as String? ?? 'pending',
        'base_request': req,
        'request_team_name': teamNameById[req['team_id'] as String?] ?? '',
        'target_team_name':
            teamNameById[inv['target_team_id'] as String?] ?? '',
      });
    }

    return invites;
  }

  Future<void> denyInvite({
    required String inviteId,
    required String deniedBy,
  }) async {
    await supa
        .from('instant_request_invites')
        .update({'status': 'denied'})
        .eq('id', inviteId);
  }

  /// Accept a pending admin match by creating an invite for user's admin team
  /// Uses RPC function to bypass RLS policy
  Future<void> acceptPendingAdminMatch({
    required String requestId,
    required String myAdminTeamId,
    required String userId,
  }) async {
    await supa.rpc(
      'accept_pending_admin_match',
      params: {
        'p_request_id': requestId,
        'p_target_team_id': myAdminTeamId,
        'p_actor_user_id': userId,
      },
    );
  }

  Future<void> denyPendingAdminMatch({
    required String requestId,
    required String myAdminTeamId,
    required String userId,
  }) async {
    await supa.rpc(
      'deny_pending_admin_match',
      params: {
        'p_request_id': requestId,
        'p_target_team_id': myAdminTeamId,
        'p_actor_user_id': userId,
      },
    );
  }

  /// ✅ FIXED: Approve invite using RPC (so client does NOT write to team_match_attendance)
  ///
  /// IMPORTANT: Your RPC MUST accept the actor id:
  ///   approve_team_vs_team_invite(
  ///     p_invite_id uuid,
  ///     p_request_id uuid,
  ///     p_target_team_id uuid,
  ///     p_actor_user_id uuid
  ///   )
  ///
  /// Why: Team-B admin must be marked accepted too, otherwise My Games (accepted-only)
  /// will show zero games for that admin.
  Future<void> approveTeamVsTeamInvite({
    required String myUserId,
    required String inviteId,
    required String requestId,
    required String targetTeamId,
  }) async {
    await supa.rpc(
      'approve_team_vs_team_invite',
      params: {
        'p_invite_id': inviteId,
        'p_request_id': requestId,
        'p_target_team_id': targetTeamId,
        'p_actor_user_id': myUserId, // ✅ critical fix
      },
    );
  }

  // -------------------------
  // Hide / Unhide (My Games only)
  // -------------------------

  Future<List<String>> getHiddenRequestIds(String userId) async {
    final rows = await supa
        .from('user_hidden_games')
        .select('request_id')
        .eq('user_id', userId);

    if (rows is! List) return [];
    return rows.map<String>((r) => r['request_id'] as String).toList();
  }

  Future<void> hideGameForUser({
    required String userId,
    required String requestId,
  }) async {
    await supa.from('user_hidden_games').upsert(
      {'user_id': userId, 'request_id': requestId},
      onConflict: 'request_id,user_id',
    );
  }

  /// Get team match requests where user is admin and can approve
  /// (same sport, within 75 miles radius)
  Future<List<Map<String, dynamic>>> getPendingTeamMatchesForAdmin({
    required String userId,
    required List<Map<String, dynamic>> adminTeams,
    required String? userZipCode,
  }) async {
    if (kDebugMode) {
      print('[DEBUG] getPendingTeamMatchesForAdmin: userId=$userId, adminTeams=${adminTeams.length}, userZipCode=$userZipCode');
      for (final team in adminTeams) {
        print('[DEBUG] Admin team: ${team['id']}, sport=${team['sport']}, name=${team['name']}');
      }
    }
    
    if (adminTeams.isEmpty || userZipCode == null) {
      if (kDebugMode) {
        print('[DEBUG] getPendingTeamMatchesForAdmin: Returning empty - adminTeams.isEmpty=${adminTeams.isEmpty}, userZipCode==null=${userZipCode == null}');
      }
      return [];
    }

    final adminTeamIds = adminTeams.map((t) => t['id'] as String).toList();
    final adminSports = adminTeams.map((t) => (t['sport'] as String? ?? '').toLowerCase()).toSet();

    // Get all pending/open team match requests with same sport
    // Include public visibility for open challenges
    final requests = await supa
        .from('instant_match_requests')
        .select('id, team_id, sport, zip_code, mode, start_time_1, start_time_2, venue, status, created_by, creator_id, radius_miles, visibility, is_public')
        .eq('mode', 'team_vs_team')
        .inFilter('status', ['pending', 'open'])
        .neq('status', 'cancelled');

    if (kDebugMode) {
      print('[DEBUG] getPendingTeamMatchesForAdmin: Found ${requests is List ? requests.length : 0} total requests');
      if (requests is List && requests.isNotEmpty) {
        for (final req in requests.take(5)) {
          print('[DEBUG] Request: id=${req['id']}, sport=${req['sport']}, status=${req['status']}, visibility=${req['visibility']}, is_public=${req['is_public']}, team_id=${req['team_id']}');
        }
      }
    }

    if (requests is! List) return [];

    // Get existing invites for user's admin teams to filter them out
    final existingInvites = await supa
        .from('instant_request_invites')
        .select('request_id, target_team_id')
        .inFilter('target_team_id', adminTeamIds);
    
    final existingInviteKeys = <String>{};
    if (existingInvites is List) {
      for (final inv in existingInvites) {
        final reqId = inv['request_id'] as String?;
        final teamId = inv['target_team_id'] as String?;
        if (reqId != null && teamId != null) {
          existingInviteKeys.add('$reqId:$teamId');
        }
      }
    }

    final pendingMatches = <Map<String, dynamic>>[];

    for (final req in requests) {
      final reqId = req['id'] as String?;
      final reqTeamId = req['team_id'] as String?;
      final reqSport = (req['sport'] as String? ?? '').toLowerCase();
      final visibility = (req['visibility'] as String?)?.toLowerCase();
      final isPublic = req['is_public'] as bool? ?? false;
      
      if (kDebugMode) {
        print('[DEBUG] Processing request: id=$reqId, sport=$reqSport, visibility=$visibility, is_public=$isPublic, team_id=$reqTeamId');
      }
      
      if (reqTeamId == null) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: team_id is null');
        continue;
      }

      // Skip if this request is from one of user's admin teams
      if (adminTeamIds.contains(reqTeamId)) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: created by user\'s own team');
        continue;
      }

      if (!adminSports.contains(reqSport)) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: sport mismatch (reqSport=$reqSport, adminSports=$adminSports)');
        continue;
      }

      // Check if within radius (using radius_miles from request, default 75)
      final reqZip = req['zip_code'] as String?;
      final radiusMiles = req['radius_miles'] as int? ?? 75;
      
      // For public games, show to all admins of the same sport (radius check is less strict)
      // For non-public games, apply stricter radius check
      bool isWithinRadius;
      
      if (visibility == 'public' || isPublic) {
        // Public games: Show to all admins of same sport within the request's radius
        // Since it's public, we're more lenient - if radius is 75 miles (default), show it
        // For now, show all public games to admins of same sport (radius check happens at game creation)
        isWithinRadius = true; // Public games are discoverable by all admins of same sport
        if (kDebugMode) {
          print('[DEBUG] Request $reqId: Public game, isWithinRadius=true');
        }
      } else {
        // Non-public games: Apply radius check
        if (reqZip == null || userZipCode == null) {
          if (kDebugMode) {
            print('[DEBUG] Skipping request $reqId: Missing ZIP codes (reqZip=$reqZip, userZipCode=$userZipCode)');
          }
          continue; // Need ZIP codes for radius check
        }
        // If ZIP codes match (same area), definitely within range
        // If request has radius >= 75 (wide search), include it
        isWithinRadius = reqZip == userZipCode || radiusMiles >= 75;
        if (kDebugMode) {
          print('[DEBUG] Request $reqId: Non-public, isWithinRadius=$isWithinRadius (reqZip=$reqZip, userZipCode=$userZipCode, radius=$radiusMiles)');
        }
      }
      
      if (!isWithinRadius) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: Not within radius');
        continue;
      }
      
      // Find matching admin team for this sport
      final matchingAdminTeam = adminTeams.firstWhere(
        (t) => (t['sport'] as String? ?? '').toLowerCase() == reqSport,
        orElse: () => <String, dynamic>{},
      );
      
      if (matchingAdminTeam.isEmpty) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: No matching admin team found');
        continue;
      }
      
      final adminTeamId = matchingAdminTeam['id'] as String?;
      if (adminTeamId == null) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: adminTeamId is null');
        continue;
      }
      
      if (reqId == null) {
        if (kDebugMode) print('[DEBUG] Skipping request: reqId is null');
        continue;
      }
      
      // Skip if invite already exists for this request and admin team
      final inviteKey = '$reqId:$adminTeamId';
      if (existingInviteKeys.contains(inviteKey)) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: Invite already exists for adminTeamId=$adminTeamId');
        continue; // Skip - invite already exists
      }
      
      // Visibility check already done above - public games are included
      
      // Get team info
      final teamInfo = await supa
          .from('teams')
          .select('id, name, sport, zip_code')
          .eq('id', reqTeamId)
          .maybeSingle();

      if (teamInfo != null) {
        if (kDebugMode) {
          print('[DEBUG] ✓ Adding pending match: requestId=$reqId, teamName=${teamInfo['name']}, adminTeamId=$adminTeamId');
        }
        pendingMatches.add({
          'request': req,
          'team': teamInfo,
          'admin_team': matchingAdminTeam,
        });
      } else {
        if (kDebugMode) {
          print('[DEBUG] Skipping request $reqId: teamInfo is null');
        }
      }
    }
    
    if (kDebugMode) {
      print('[DEBUG] getPendingTeamMatchesForAdmin: Returning ${pendingMatches.length} pending matches');
    }
    
    return pendingMatches;
  }

  /// Get individual games from friends that are "friends_only"
  Future<List<Map<String, dynamic>>> getFriendsOnlyIndividualGames({
    required String userId,
  }) async {
    // Get user's friends
    final friendRows = await supa
        .from('friends')
        .select('friend_id')
        .eq('user_id', userId)
        .eq('status', 'accepted');

    if (friendRows is! List || friendRows.isEmpty) return [];

    final friendIds = friendRows.map<String>((r) => r['friend_id'] as String).toList();

    // Get individual games (pickup mode) created by friends
    // where visibility is friends_only or is_public is false
    final requests = await supa
        .from('instant_match_requests')
        .select('id, sport, mode, zip_code, start_time_1, start_time_2, venue, status, created_by, creator_id, num_players, proficiency_level, visibility, is_public')
        .eq('mode', 'pickup')
        .inFilter('created_by', friendIds)
        .inFilter('status', ['open', 'pending'])
        .neq('status', 'cancelled');

    if (requests is! List) return [];

    final friendsOnlyGames = <Map<String, dynamic>>[];

    for (final req in requests) {
      final visibility = req['visibility'] as String?;
      final isPublic = req['is_public'] as bool? ?? true;

      // Check if friends_only
      if (visibility == 'friends_only' || !isPublic) {
        final creatorId = req['created_by'] as String?;
        if (creatorId != null && friendIds.contains(creatorId)) {
          // Get creator info
          final creatorInfo = await supa
              .from('users')
              .select('id, full_name, photo_url')
              .eq('id', creatorId)
              .maybeSingle();

          friendsOnlyGames.add({
            'request': req,
            'creator': creatorInfo,
          });
        }
      }
    }

    return friendsOnlyGames;
  }

  Future<void> unhideGameForUser({
    required String userId,
    required String requestId,
  }) async {
    await supa
        .from('user_hidden_games')
        .delete()
        .eq('user_id', userId)
        .eq('request_id', requestId);
  }

  // -------------------------
  // Soft cancel
  // -------------------------

  Future<void> cancelGameSoft({
    required String requestId,
    required String cancelledBy,
  }) async {
    await supa.from('instant_match_requests').update({
      'status': 'cancelled',
      'cancelled_by': cancelledBy,
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      'last_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', requestId);
  }

  // -------------------------
  // Attendance
  // -------------------------

  /// ✅ update by (request_id, user_id) only
  Future<void> setMyAttendance({
    required String myUserId,
    required String requestId,
    required String teamId,
    required String status,
  }) async {
    await supa
        .from('team_match_attendance')
        .update({'status': status})
        .eq('request_id', requestId)
        .eq('user_id', myUserId);
  }

  Future<void> switchMyTeamForMatch({
    required String myUserId,
    required String requestId,
    required String newTeamId,
  }) async {
    await supa
        .from('team_match_attendance')
        .update({'team_id': newTeamId})
        .eq('request_id', requestId)
        .eq('user_id', myUserId);
  }

  // -------------------------
  // Loading Matches
  // -------------------------

  /// My Games = only games where I accepted.
  Future<List<Map<String, dynamic>>> loadMyAcceptedTeamMatches(
      String myUserId) async {
    // Use RPC function to bypass RLS and get confirmed matches
    final reqsResult = await supa.rpc(
      'get_confirmed_matches_for_user',
      params: {'p_user_id': myUserId},
    );

    final reqs = reqsResult is List ? reqsResult : <dynamic>[];

    if (kDebugMode) {
      print('[DEBUG] loadMyAcceptedTeamMatches: RPC returned ${reqs.length} confirmed matches');
    }

    if (reqs.isEmpty) return [];

    // Extract request IDs for fetching additional data
    final requestIds = reqs
        .map<String>((r) => r['id'] as String)
        .toSet()
        .toList();

    // Now fetch team names and attendance data (same as before)
    return _enrichTeamMatchesWithDetails(reqs, requestIds, myUserId);
  }

  /// Load all matches for user including cancelled ones
  Future<List<Map<String, dynamic>>> loadAllMatchesForUser(
      String myUserId) async {
    // Use RPC function to bypass RLS and get all matches (including cancelled)
    final reqsResult = await supa.rpc(
      'get_all_matches_for_user',
      params: {'p_user_id': myUserId},
    );

    final reqs = reqsResult is List ? reqsResult : <dynamic>[];

    if (kDebugMode) {
      print('[DEBUG] loadAllMatchesForUser: RPC returned ${reqs.length} matches');
      if (reqs.isNotEmpty) {
        final statuses = reqs.map((r) => r['status'] as String? ?? 'null').toList();
        print('[DEBUG] Status values from RPC: $statuses');
      }
    }

    if (reqs.isEmpty) return [];

    // Extract request IDs for fetching additional data
    final requestIds = reqs
        .map<String>((r) => r['id'] as String)
        .toSet()
        .toList();

    // Now fetch team names and attendance data (same as before)
    return _enrichTeamMatchesWithDetails(reqs, requestIds, myUserId);
  }

  // Helper function to enrich match requests with team names and attendance
  Future<List<Map<String, dynamic>>> _enrichTeamMatchesWithDetails(
    List<dynamic> reqs,
    List<String> requestIds,
    String myUserId,
  ) async {
    // Batch fetch team names
    final allTeamIds = <String>{};
    for (final r in reqs) {
      final a = r['team_id'] as String?;
      final b = r['matched_team_id'] as String?;
      if (a != null) allTeamIds.add(a);
      if (b != null) allTeamIds.add(b);
    }

    final teams = allTeamIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('teams')
            .select('id, name')
            .inFilter('id', allTeamIds.toList());

    final Map<String, String> teamNameById = {};
    if (teams is List) {
      for (final t in teams) {
        final id = t['id'] as String?;
        if (id != null) teamNameById[id] = (t['name'] as String?) ?? '';
      }
    }

    // Batch fetch attendance for those requestIds
    final allAttendance = await supa
        .from('team_match_attendance')
        .select('request_id, user_id, team_id, status')
        .inFilter('request_id', requestIds);

    // Batch fetch user names
    final allUserIds = <String>{};
    if (allAttendance is List) {
      for (final a in allAttendance) {
        final uid = a['user_id'] as String?;
        if (uid != null) allUserIds.add(uid);
      }
    }

    final users = allUserIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('users')
            .select('id, full_name')
            .inFilter('id', allUserIds.toList());

    final Map<String, String> userNameById = {};
    if (users is List) {
      for (final u in users) {
        final id = u['id'] as String?;
        if (id != null) {
          userNameById[id] = (u['full_name'] as String?) ?? 'Player';
        }
      }
    }

    // Group attendance by request_id
    final Map<String, List<Map<String, dynamic>>> attendanceByRequest = {};
    if (allAttendance is List) {
      for (final a in allAttendance) {
        final rid = a['request_id'] as String?;
        if (rid == null) continue;
        attendanceByRequest.putIfAbsent(rid, () => []);
        attendanceByRequest[rid]!.add(Map<String, dynamic>.from(a));
      }
    }

    final rows = <Map<String, dynamic>>[];

    for (final r in reqs) {
      final reqId = r['id'] as String?;
      if (reqId == null) continue;

      final teamAId = r['team_id'] as String?;
      final teamBId = r['matched_team_id'] as String?;
      if (teamAId == null || teamBId == null) continue;

      DateTime? startDt;
      DateTime? endDt;
      final st1 = r['start_time_1'];
      final st2 = r['start_time_2'];
      if (st1 is String) startDt = DateTime.tryParse(st1);
      if (st2 is String) endDt = DateTime.tryParse(st2);

      final venue = r['venue'] as String?;
      final createdBy =
          (r['created_by'] as String?) ?? (r['creator_id'] as String?);

      final teamAName = teamNameById[teamAId] ?? 'Team A';
      final teamBName = teamNameById[teamBId] ?? 'Team B';

      final attendees = attendanceByRequest[reqId] ?? [];

      final teamAPlayers = <Map<String, dynamic>>[];
      final teamBPlayers = <Map<String, dynamic>>[];

      for (final a in attendees) {
        final uid = a['user_id'] as String?;
        final tid = a['team_id'] as String?;
        final st = (a['status'] as String?)?.toLowerCase() ?? 'pending';
        if (uid == null || tid == null) continue;

        final item = {
          'user_id': uid,
          'name': userNameById[uid] ?? 'Player',
          'status': st,
        };

        if (tid == teamAId) teamAPlayers.add(item);
        if (tid == teamBId) teamBPlayers.add(item);
      }

      // can switch side if member of both teams
      bool canSwitchSide = false;
      final membershipRows = await supa
          .from('team_members')
          .select('team_id')
          .eq('user_id', myUserId)
          .inFilter('team_id', [teamAId, teamBId]);

      if (membershipRows is List && membershipRows.length >= 2) {
        canSwitchSide = true;
      }

      // Get user's attendance status from RPC result
      final userAttendanceStatus = (r['user_attendance_status'] as String?)?.toLowerCase() ?? 'accepted';
      final userTeamId = r['user_team_id'] as String?;
      // Get match request status (for filtering cancelled matches)
      final matchStatus = (r['status'] as String?)?.toLowerCase() ?? '';

      if (kDebugMode && matchStatus == 'cancelled') {
        print('[DEBUG] _enrichTeamMatchesWithDetails: Found cancelled match $reqId with status=$matchStatus');
      }

      rows.add({
        'request_id': reqId,
        'sport': r['sport'],
        'zip_code': r['zip_code'],
        'team_a_id': teamAId,
        'team_b_id': teamBId,
        'team_a_name': teamAName,
        'team_b_name': teamBName,
        'team_a_players': teamAPlayers,
        'team_b_players': teamBPlayers,
        'start_time': startDt,
        'end_time': endDt,
        'venue': venue,
        'can_switch_side': canSwitchSide,
        'created_by': createdBy,
        'my_attendance_status': userAttendanceStatus, // 'accepted' or 'declined'
        'my_team_id': userTeamId,
        'status': matchStatus, // Match request status (e.g., 'cancelled', 'matched', etc.)
        'expected_players_per_team': r['expected_players_per_team'], // Match-specific expected players (can be null, falls back to sport default)
      });
    }

    // Newest games on top
    rows.sort((a, b) {
      final ad = a['start_time'] as DateTime?;
      final bd = b['start_time'] as DateTime?;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    return rows;
  }

  Future<List<Map<String, dynamic>>> loadAllMyTeamMatches(
      String myUserId) async {
    return _loadTeamMatchesForUser(myUserId, onlyAccepted: false);
  }

  /// Team games where match is confirmed but MY attendance is still pending
  Future<List<Map<String, dynamic>>> loadMyPendingAvailabilityMatches(
      String myUserId) async {
    // 1) Get my attendance rows
    final attendRows = await supa
        .from('team_match_attendance')
        .select('request_id, team_id, status')
        .eq('user_id', myUserId);

    if (kDebugMode) {
      print('[DEBUG] loadMyPendingAvailabilityMatches for userId=$myUserId');
      print('[DEBUG] Step 1: attendance rows count=${attendRows is List ? attendRows.length : 0}');
      if (attendRows is List && attendRows.isNotEmpty) {
        print('[DEBUG] Attendance rows: $attendRows');
      }
    }

    if (attendRows is! List || attendRows.isEmpty) {
      if (kDebugMode) {
        print('[DEBUG] No attendance rows found, returning empty list');
      }
      return [];
    }

    final Map<String, String> myTeamByReqId = {};
    final Map<String, String> myStatusByReqId = {};
    int filteredOutCount = 0;

    for (final r in attendRows) {
      final reqId = r['request_id'] as String?;
      final teamId = r['team_id'] as String?;
      final st = (r['status'] as String?)?.toLowerCase() ?? 'pending';
      if (reqId == null || teamId == null) continue;

      // Only keep rows where I'm not already accepted/declined
      if (st == 'accepted' || st == 'declined') {
        filteredOutCount++;
        if (kDebugMode) {
          print('[DEBUG] Filtered out row: reqId=$reqId, status=$st');
        }
        continue;
      }

      myTeamByReqId[reqId] = teamId;
      myStatusByReqId[reqId] = st;
    }

    if (kDebugMode) {
      print('[DEBUG] Step 2: After filtering, pending count=${myTeamByReqId.length}, filteredOut=$filteredOutCount');
      print('[DEBUG] Pending requestIds: ${myTeamByReqId.keys.toList()}');
    }

    if (myTeamByReqId.isEmpty) {
      if (kDebugMode) {
        print('[DEBUG] No pending requests after filtering, returning empty list');
      }
      return [];
    }

    final requestIds = myTeamByReqId.keys.toList();

    if (kDebugMode) {
      print('[DEBUG] Step 3: Querying for ${requestIds.length} request IDs');
      print('[DEBUG] Request IDs: ${requestIds.take(5).toList()}...'); // Show first 5
    }

    // 2) Load match requests using RPC function (bypasses RLS)
    // This ensures users can see requests they have attendance records for,
    // even if RLS would normally block access
    final reqsResult = await supa.rpc(
      'get_match_requests_for_attendance',
      params: {
        'p_user_id': myUserId,
        'p_request_ids': requestIds,
      },
    );

    final reqs = reqsResult is List ? reqsResult : <dynamic>[];

    if (kDebugMode) {
      print('[DEBUG] Step 3: RPC query returned ${reqs.length} match requests out of ${requestIds.length} request IDs');
      if (reqs.isNotEmpty) {
        print('[DEBUG] Match requests: ${reqs.take(5).map((r) => {
          'id': r['id'], 
          'status': r['status'], 
          'mode': r['mode'],
          'matched_team_id': r['matched_team_id'],
          'is_confirmed': r['matched_team_id'] != null
        }).toList()}');
      }
      if (reqs.length < requestIds.length) {
        print('[DEBUG] NOTE: ${requestIds.length - reqs.length} request IDs not found in database (may have been deleted)');
      }
    }

    if (reqs is! List || reqs.isEmpty) {
      if (kDebugMode) {
        print('[DEBUG] No match requests found after filtering, returning empty list');
      }
      return [];
    }

    // Filter out cancelled matches (user doesn't need to respond to cancelled matches)
    final nonCancelledReqs = (reqs as List).where((r) {
      final status = (r['status'] as String?)?.toLowerCase();
      return status != 'cancelled';
    }).toList();

    if (kDebugMode) {
      final cancelledCount = (reqs as List).length - nonCancelledReqs.length;
      if (cancelledCount > 0) {
        print('[DEBUG] Filtered out $cancelledCount cancelled match(es)');
      }
    }

    if (nonCancelledReqs.isEmpty) {
      if (kDebugMode) {
        print('[DEBUG] All matches were cancelled, returning empty list');
      }
      return [];
    }

    // 3) Fetch team names
    final allTeamIds = <String>{};
    for (final r in nonCancelledReqs) {
      final a = r['team_id'] as String?;
      final b = r['matched_team_id'] as String?;
      if (a != null) allTeamIds.add(a);
      if (b != null) allTeamIds.add(b);
    }

    final teams = allTeamIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('teams')
            .select('id, name')
            .inFilter('id', allTeamIds.toList());

    final Map<String, String> teamNameById = {};
    if (teams is List) {
      for (final t in teams) {
        final id = t['id'] as String?;
        if (id != null) teamNameById[id] = (t['name'] as String?) ?? '';
      }
    }

    // 4) Build rows
    final rows = <Map<String, dynamic>>[];

    for (final r in nonCancelledReqs) {
      final reqId = r['id'] as String?;
      if (reqId == null) continue;

      if (!myTeamByReqId.containsKey(reqId)) continue;

      final teamAId = r['team_id'] as String?;
      final teamBId = r['matched_team_id'] as String?;
      if (teamAId == null) continue; // teamAId is required, but teamBId can be null for pending requests

      DateTime? startDt;
      DateTime? endDt;
      final st1 = r['start_time_1'];
      final st2 = r['start_time_2'];
      if (st1 is String) startDt = DateTime.tryParse(st1);
      if (st2 is String) endDt = DateTime.tryParse(st2);

      final venue = r['venue'] as String?;
      final isConfirmed = teamBId != null;

      rows.add({
        'request_id': reqId,
        'sport': r['sport'],
        'zip_code': r['zip_code'],
        'team_a_id': teamAId,
        'team_b_id': teamBId, // Can be null for pending requests
        'team_a_name': teamNameById[teamAId] ?? 'Team A',
        'team_b_name': teamBId != null ? (teamNameById[teamBId] ?? 'Team B') : null,
        'start_time': startDt,
        'end_time': endDt,
        'venue': venue,
        'my_team_id': myTeamByReqId[reqId],
        'my_status': myStatusByReqId[reqId] ?? 'pending',
        'is_confirmed': isConfirmed, // true if matched, false if pending
      });
    }

    // Newest games on top
    rows.sort((a, b) {
      final ad = a['start_time'] as DateTime?;
      final bd = b['start_time'] as DateTime?;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    if (kDebugMode) {
      print('[DEBUG] Step 4: Final rows count=${rows.length}');
      if (rows.isNotEmpty) {
        print('[DEBUG] Final rows: ${rows.map((r) => {'request_id': r['request_id'], 'sport': r['sport'], 'my_status': r['my_status']}).toList()}');
      }
    }

    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadTeamMatchesForUser(
    String myUserId, {
    required bool onlyAccepted,
  }) async {
    final attendQuery = supa
        .from('team_match_attendance')
        .select('request_id, team_id, status')
        .eq('user_id', myUserId);

    final attendRows = onlyAccepted
        ? await attendQuery.eq('status', 'accepted')
        : await attendQuery;

    if (kDebugMode && onlyAccepted) {
      print('[DEBUG] loadMyAcceptedTeamMatches: Found ${attendRows is List ? attendRows.length : 0} accepted attendance rows');
    }

    if (attendRows is! List || attendRows.isEmpty) return [];

    final requestIds = attendRows
        .map<String>((r) => r['request_id'] as String)
        .toSet()
        .toList();

    if (kDebugMode && onlyAccepted) {
      print('[DEBUG] loadMyAcceptedTeamMatches: Querying for ${requestIds.length} request IDs');
    }

    // ✅ DO NOT require status='matched'
    final reqs = await supa
        .from('instant_match_requests')
        .select(
            'id, sport, mode, zip_code, team_id, matched_team_id, start_time_1, start_time_2, venue, status, created_by, creator_id')
        .inFilter('id', requestIds)
        .eq('mode', 'team_vs_team')
        .neq('status', 'cancelled')
        .not('matched_team_id', 'is', null);

    if (kDebugMode && onlyAccepted) {
      print('[DEBUG] loadMyAcceptedTeamMatches: Found ${reqs is List ? reqs.length : 0} confirmed match requests');
      if (reqs is List && reqs.length < requestIds.length) {
        print('[DEBUG] WARNING: Only found ${reqs.length} out of ${requestIds.length} requests. Missing request IDs: ${requestIds.where((id) => !(reqs as List).any((r) => r['id'] == id)).toList()}');
      }
    }

    if (reqs is! List || reqs.isEmpty) return [];

    // Batch fetch team names
    final allTeamIds = <String>{};
    for (final r in reqs) {
      final a = r['team_id'] as String?;
      final b = r['matched_team_id'] as String?;
      if (a != null) allTeamIds.add(a);
      if (b != null) allTeamIds.add(b);
    }

    final teams = allTeamIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('teams')
            .select('id, name')
            .inFilter('id', allTeamIds.toList());

    final Map<String, String> teamNameById = {};
    if (teams is List) {
      for (final t in teams) {
        final id = t['id'] as String?;
        if (id != null) teamNameById[id] = (t['name'] as String?) ?? '';
      }
    }

    // Batch fetch attendance for those requestIds
    final allAttendance = await supa
        .from('team_match_attendance')
        .select('request_id, user_id, team_id, status')
        .inFilter('request_id', requestIds);

    // Batch fetch user names
    final allUserIds = <String>{};
    if (allAttendance is List) {
      for (final a in allAttendance) {
        final uid = a['user_id'] as String?;
        if (uid != null) allUserIds.add(uid);
      }
    }

    final users = allUserIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('users')
            .select('id, full_name')
            .inFilter('id', allUserIds.toList());

    final Map<String, String> userNameById = {};
    if (users is List) {
      for (final u in users) {
        final id = u['id'] as String?;
        if (id != null) {
          userNameById[id] = (u['full_name'] as String?) ?? 'Player';
        }
      }
    }

    // Group attendance by request_id
    final Map<String, List<Map<String, dynamic>>> attendanceByRequest = {};
    if (allAttendance is List) {
      for (final a in allAttendance) {
        final rid = a['request_id'] as String?;
        if (rid == null) continue;
        attendanceByRequest.putIfAbsent(rid, () => []);
        attendanceByRequest[rid]!.add(Map<String, dynamic>.from(a));
      }
    }

    final rows = <Map<String, dynamic>>[];

    for (final r in reqs) {
      final reqId = r['id'] as String;
      final teamAId = r['team_id'] as String?;
      final teamBId = r['matched_team_id'] as String?;
      if (teamAId == null || teamBId == null) continue;

      DateTime? startDt;
      DateTime? endDt;
      final st1 = r['start_time_1'];
      final st2 = r['start_time_2'];
      if (st1 is String) startDt = DateTime.tryParse(st1);
      if (st2 is String) endDt = DateTime.tryParse(st2);

      final venue = r['venue'] as String?;
      final createdBy =
          (r['created_by'] as String?) ?? (r['creator_id'] as String?);

      final teamAName = teamNameById[teamAId] ?? 'Team A';
      final teamBName = teamNameById[teamBId] ?? 'Team B';

      final attendees = attendanceByRequest[reqId] ?? [];

      final teamAPlayers = <Map<String, dynamic>>[];
      final teamBPlayers = <Map<String, dynamic>>[];

      for (final a in attendees) {
        final uid = a['user_id'] as String?;
        final tid = a['team_id'] as String?;
        final st = (a['status'] as String?)?.toLowerCase() ?? 'pending';
        if (uid == null || tid == null) continue;

        final item = {
          'user_id': uid,
          'name': userNameById[uid] ?? 'Player',
          'status': st,
        };

        if (tid == teamAId) teamAPlayers.add(item);
        if (tid == teamBId) teamBPlayers.add(item);
      }

      // can switch side if member of both teams
      bool canSwitchSide = false;
      final membershipRows = await supa
          .from('team_members')
          .select('team_id')
          .eq('user_id', myUserId)
          .inFilter('team_id', [teamAId, teamBId]);

      if (membershipRows is List && membershipRows.length >= 2) {
        canSwitchSide = true;
      }

      rows.add({
        'request_id': reqId,
        'sport': r['sport'],
        'zip_code': r['zip_code'],
        'team_a_id': teamAId,
        'team_b_id': teamBId,
        'team_a_name': teamAName,
        'team_b_name': teamBName,
        'team_a_players': teamAPlayers,
        'team_b_players': teamBPlayers,
        'start_time': startDt,
        'end_time': endDt,
        'venue': venue,
        'can_switch_side': canSwitchSide,
        'created_by': createdBy,
      });
    }

    // New games on top
    rows.sort((a, b) {
      final ad = a['start_time'] as DateTime?;
      final bd = b['start_time'] as DateTime?;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    return rows;
  }
}
