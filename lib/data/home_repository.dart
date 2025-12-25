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
    // Use last_known_zip_code instead of base_zip_code (which was removed)
    final row = await supa
        .from('users')
        .select('last_known_zip_code')
        .eq('id', userId)
        .maybeSingle();
    return row?['last_known_zip_code'] as String?;
  }

  Future<Map<String, String?>> getUserNameAndLocation(String userId) async {
    final row = await supa
        .from('users')
        .select('full_name, last_known_zip_code, photo_url')
        .eq('id', userId)
        .maybeSingle();
    final zipCode = row?['last_known_zip_code'] as String?;
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
    // Get invite details to check request_id
    final invite = await supa
        .from('instant_request_invites')
        .select('request_id, target_team_id, status')
        .eq('id', inviteId)
        .maybeSingle();
    
    if (invite == null) return;
    
    final requestId = invite['request_id'] as String?;
    if (requestId == null) return;
    
    // Update invite status to denied
    await supa
        .from('instant_request_invites')
        .update({'status': 'denied'})
        .eq('id', inviteId);
    
    // Check if all invited teams have denied
    final allInvites = await supa
        .from('instant_request_invites')
        .select('status')
        .eq('request_id', requestId);
    
    if (allInvites is List && allInvites.isNotEmpty) {
      final allDenied = allInvites.every((inv) => 
        (inv['status'] as String?)?.toLowerCase() == 'denied'
      );
      
      // If all teams denied, make the game public
      if (allDenied) {
        await supa
            .from('instant_match_requests')
            .update({
              'visibility': 'public',
              'is_public': true,
              'status': 'open', // Change to open so it appears in public games
            })
            .eq('id', requestId);
      }
    }
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
    
    // Get team notification preferences
    final teamNotificationRadii = <String, int>{};
    for (final team in adminTeams) {
      final teamId = team['id'] as String;
      // Fetch team notification radius from database
      final teamRow = await supa
          .from('teams')
          .select('notification_radius_miles')
          .eq('id', teamId)
          .maybeSingle();
      teamNotificationRadii[teamId] = (teamRow?['notification_radius_miles'] as int?) ?? 50;
    }

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

      // Check if within radius using team notification preferences
      final reqZip = req['zip_code'] as String?;
      final reqRadiusMiles = req['radius_miles'] as int? ?? 75;
      
      // Find matching admin team for this sport to get its notification radius
      final matchingTeam = adminTeams.firstWhere(
        (t) => (t['sport'] as String? ?? '').toLowerCase() == reqSport,
        orElse: () => <String, dynamic>{},
      );
      final teamNotificationRadius = matchingTeam.isNotEmpty 
          ? (teamNotificationRadii[matchingTeam['id'] as String] ?? 50)
          : 50; // Default 50 miles
      
      // For public games, use team notification radius
      // For non-public games, apply stricter radius check
      bool isWithinRadius;
      
      if (visibility == 'public' || isPublic) {
        // Public games: Check if within team's notification radius
        if (reqZip == null || userZipCode == null) {
          // If ZIP codes unavailable, use game's radius
          isWithinRadius = reqRadiusMiles >= teamNotificationRadius;
        } else {
          // If ZIP codes match (same area), definitely within range
          // Otherwise, check if game radius overlaps with team notification radius
          isWithinRadius = reqZip == userZipCode || reqRadiusMiles >= teamNotificationRadius;
        }
        if (kDebugMode) {
          print('[DEBUG] Request $reqId: Public game, teamNotificationRadius=$teamNotificationRadius, isWithinRadius=$isWithinRadius');
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
        // Otherwise, check if game radius overlaps with team notification radius
        isWithinRadius = reqZip == userZipCode || reqRadiusMiles >= teamNotificationRadius;
        if (kDebugMode) {
          print('[DEBUG] Request $reqId: Non-public, teamNotificationRadius=$teamNotificationRadius, isWithinRadius=$isWithinRadius (reqZip=$reqZip, userZipCode=$userZipCode, reqRadius=$reqRadiusMiles)');
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

    // Batch fetch user names (including creators)
    final allUserIds = <String>{};
    if (allAttendance is List) {
      for (final a in allAttendance) {
        final uid = a['user_id'] as String?;
        if (uid != null) allUserIds.add(uid);
      }
    }
    // Also add creator IDs
    for (final r in reqs) {
      final creatorId = r['created_by'] as String?;
      if (creatorId != null) allUserIds.add(creatorId);
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
    
    // Batch fetch team member roles (to mark admins)
    final teamMemberRoles = allTeamIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('team_members')
            .select('user_id, team_id, role')
            .inFilter('team_id', allTeamIds.toList());
    
    // Map: user_id + team_id => role
    final Map<String, String> roleByUserTeam = {};
    if (teamMemberRoles is List) {
      for (final tm in teamMemberRoles) {
        final uid = tm['user_id'] as String?;
        final tid = tm['team_id'] as String?;
        final role = (tm['role'] as String?)?.toLowerCase() ?? 'member';
        if (uid != null && tid != null) {
          roleByUserTeam['$uid-$tid'] = role;
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
      if (st1 is String) {
        final parsed = DateTime.tryParse(st1);
        startDt = parsed?.toLocal();
      }
      if (st2 is String) {
        final parsed = DateTime.tryParse(st2);
        endDt = parsed?.toLocal();
      }

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

        // Get role for this user in this team
        final role = roleByUserTeam['$uid-$tid'] ?? 'member';
        final isAdmin = role == 'admin';

        final item = {
          'user_id': uid,
          'name': userNameById[uid] ?? 'Player',
          'status': st,
          'role': role,
          'is_admin': isAdmin,
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
        'details': r['details'], // Game details/notes from organizer
        'can_switch_side': canSwitchSide,
        'created_by': createdBy,
        'creator_name': userNameById[createdBy] ?? 'Unknown', // Creator name
        'my_attendance_status': userAttendanceStatus, // 'accepted' or 'declined'
        'my_team_id': userTeamId,
        'status': matchStatus, // Match request status (e.g., 'cancelled', 'matched', etc.)
        'expected_players_per_team': r['expected_players_per_team'], // Match-specific expected players (can be null, falls back to sport default)
        'chat_enabled': r['chat_enabled'] as bool? ?? false,
        'chat_mode': r['chat_mode'] as String? ?? 'all_users',
        'show_team_a_roster': r['show_team_a_roster'] as bool? ?? false, // Team A admin controls this
        'show_team_b_roster': r['show_team_b_roster'] as bool? ?? false, // Team B admin controls this
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
        print('[DEBUG] No match requests found, returning empty list');
      }
      return [];
    }

    // Filter out cancelled matches AND games awaiting opponent confirmation
    // Games awaiting opponent confirmation (matched_team_id is null) should appear
    // in "Awaiting Opponent Confirmation" not "Pending Approval"
    // Also filter out games where the user's team is not the creating team or the matched team
    // (e.g., if Team B accepts, Team C members should not see it in "Pending Approval")
    final nonCancelledReqs = (reqs as List).where((r) {
      final status = (r['status'] as String?)?.toLowerCase();
      final matchedTeamId = r['matched_team_id'];
      final creatingTeamId = r['team_id'] as String?;
      
      // Exclude cancelled matches
      if (status == 'cancelled') return false;
      
      // Exclude games awaiting opponent confirmation (matched_team_id is null)
      // These games should only appear in "Awaiting Opponent Confirmation"
      if (matchedTeamId == null) return false;
      
      // Get the user's team ID for this game from attendance record
      final reqId = r['id'] as String?;
      final userTeamId = reqId != null ? myTeamByReqId[reqId] : null;
      
      // Only include if user's team is the creating team OR the matched team
      // This ensures that if Team B accepts, only Team A and Team B members see it
      // Team C members (who haven't accepted) should not see it
      if (userTeamId != null && matchedTeamId != null && creatingTeamId != null) {
        final isUserOnCreatingTeam = userTeamId == creatingTeamId;
        final isUserOnMatchedTeam = userTeamId == matchedTeamId;
        
        if (!isUserOnCreatingTeam && !isUserOnMatchedTeam) {
          if (kDebugMode) {
            print('[DEBUG] Filtering out game $reqId: userTeamId=$userTeamId, creatingTeamId=$creatingTeamId, matchedTeamId=$matchedTeamId');
          }
          return false; // User's team is neither creating team nor matched team
        }
      }
      
      return true;
    }).toList();

    if (kDebugMode) {
      final cancelledCount = (reqs as List).where((r) => (r['status'] as String?)?.toLowerCase() == 'cancelled').length;
      final awaitingCount = (reqs as List).where((r) => r['matched_team_id'] == null).length;
      if (cancelledCount > 0 || awaitingCount > 0) {
        print('[DEBUG] Filtered out $cancelledCount cancelled match(es) and $awaitingCount game(s) awaiting opponent confirmation');
      }
    }

    if (nonCancelledReqs.isEmpty) {
      if (kDebugMode) {
        print('[DEBUG] All matches were cancelled or awaiting opponent confirmation, returning empty list');
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
      if (st1 is String) {
        final parsed = DateTime.tryParse(st1);
        startDt = parsed?.toLocal();
      }
      if (st2 is String) {
        final parsed = DateTime.tryParse(st2);
        endDt = parsed?.toLocal();
      }

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
            'id, sport, mode, zip_code, team_id, matched_team_id, start_time_1, start_time_2, venue, details, status, created_by, creator_id, chat_enabled, chat_mode')
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

    // Batch fetch user names (including creators)
    final allUserIds = <String>{};
    if (allAttendance is List) {
      for (final a in allAttendance) {
        final uid = a['user_id'] as String?;
        if (uid != null) allUserIds.add(uid);
      }
    }
    // Also add creator IDs
    for (final r in reqs) {
      final creatorId = r['created_by'] as String?;
      if (creatorId != null) allUserIds.add(creatorId);
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
    
    // Batch fetch team member roles (to mark admins)
    final teamMemberRoles = allTeamIds.isEmpty
        ? <dynamic>[]
        : await supa
            .from('team_members')
            .select('user_id, team_id, role')
            .inFilter('team_id', allTeamIds.toList());
    
    // Map: user_id + team_id => role
    final Map<String, String> roleByUserTeam = {};
    if (teamMemberRoles is List) {
      for (final tm in teamMemberRoles) {
        final uid = tm['user_id'] as String?;
        final tid = tm['team_id'] as String?;
        final role = (tm['role'] as String?)?.toLowerCase() ?? 'member';
        if (uid != null && tid != null) {
          roleByUserTeam['$uid-$tid'] = role;
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
      if (st1 is String) {
        final parsed = DateTime.tryParse(st1);
        startDt = parsed?.toLocal();
      }
      if (st2 is String) {
        final parsed = DateTime.tryParse(st2);
        endDt = parsed?.toLocal();
      }

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

        // Get role for this user in this team
        final role = roleByUserTeam['$uid-$tid'] ?? 'member';
        final isAdmin = role == 'admin';

        final item = {
          'user_id': uid,
          'name': userNameById[uid] ?? 'Player',
          'status': st,
          'role': role,
          'is_admin': isAdmin,
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
        'details': r['details'], // Game details/notes from organizer
        'can_switch_side': canSwitchSide,
        'created_by': createdBy,
        'creator_name': userNameById[createdBy] ?? 'Unknown', // Creator name
        'chat_enabled': r['chat_enabled'] as bool? ?? false,
        'chat_mode': r['chat_mode'] as String? ?? 'all_users',
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

  /// Get team games awaiting opponent confirmation
  /// These include:
  /// 1. Games created by user's teams (all members, not just admins) where invites are still pending
  /// 2. Games where user's teams have pending invites (invited teams)
  /// Uses attendance records to ensure all members can see the games (bypasses RLS)
  Future<List<Map<String, dynamic>>> getAwaitingOpponentConfirmationGames(
      String userId, List<String> userTeamIds) async {
    if (userTeamIds.isEmpty) return [];

    try {
      // First, get all games where user has an attendance record (this ensures RLS allows access)
      // AND where matched_team_id is null (awaiting opponent confirmation)
      final userAttendance = await supa
          .from('team_match_attendance')
          .select('request_id, team_id')
          .eq('user_id', userId);
      
      final Set<String> gameIdsWithAttendance = {};
      final Map<String, String> userTeamIdByGameId = {}; // Map game ID to user's team ID in that game
      if (userAttendance is List) {
        for (final att in userAttendance) {
          final reqId = att['request_id'] as String?;
          final teamId = att['team_id'] as String?;
          if (reqId != null) {
            gameIdsWithAttendance.add(reqId);
            if (teamId != null) {
              userTeamIdByGameId[reqId] = teamId;
            }
          }
        }
      }
      
      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Found ${gameIdsWithAttendance.length} games with attendance');
        print('[DEBUG] User team mapping: $userTeamIdByGameId');
      }
      
      if (gameIdsWithAttendance.isEmpty) {
        if (kDebugMode) {
          print('[DEBUG] getAwaitingOpponentConfirmationGames: No attendance records found for user');
        }
        return [];
      }
      
      // Get all games where user has attendance records
      // Use RPC function to bypass RLS - this ensures all members (not just admins) can see games
      final allGamesResult = await supa.rpc(
        'get_match_requests_for_attendance',
        params: {
          'p_user_id': userId,
          'p_request_ids': gameIdsWithAttendance.toList(),
        },
      );
      
      final allGamesRaw = allGamesResult is List ? allGamesResult : <dynamic>[];
      
      // Filter to only team_vs_team games awaiting opponent confirmation
      // Exclude cancelled games explicitly
      final allGames = allGamesRaw.where((game) {
        final mode = (game['mode'] as String?)?.toLowerCase();
        final status = (game['status'] as String?)?.toLowerCase();
        final matchedTeamId = game['matched_team_id'];
        final isCancelled = status == 'cancelled';
        
        if (kDebugMode && isCancelled) {
          print('[DEBUG] Filtering out cancelled game: ${game['id']}, status=$status');
        }
        
        return mode == 'team_vs_team' &&
               !isCancelled && // Explicitly exclude cancelled games
               (status == 'open' || status == 'pending') &&
               matchedTeamId == null; // Only games awaiting opponent confirmation
      }).toList();
      
      if (allGames.isEmpty) {
        if (kDebugMode) {
          print('[DEBUG] getAwaitingOpponentConfirmationGames: No games found with attendance records after filtering');
          print('[DEBUG] Raw games from RPC: ${allGamesRaw.length}');
        }
        return [];
      }
      
      // Need to fetch additional fields (details, created_by, creator_id, visibility, is_public)
      // that aren't in the RPC function return
      // Since user has attendance records, RLS should allow access via the policy in migration 024
      final gameIdsForAdditionalFields = allGames.map<String>((g) => g['id'] as String).toList();
      
      Map<String, Map<String, dynamic>> additionalByGameId = {};
      try {
        final additionalFields = await supa
            .from('instant_match_requests')
            .select('id, details, created_by, creator_id, visibility, is_public')
            .inFilter('id', gameIdsForAdditionalFields);
        
        if (additionalFields is List) {
          for (final f in additionalFields) {
            final id = f['id'] as String?;
            if (id != null) {
              additionalByGameId[id] = {
                'details': f['details'],
                'created_by': f['created_by'],
                'creator_id': f['creator_id'],
                'visibility': f['visibility'],
                'is_public': f['is_public'],
              };
              if (kDebugMode) {
                print('[DEBUG] Fetched additional fields for game $id: created_by=${f['created_by']}, creator_id=${f['creator_id']}');
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ERROR] Failed to fetch additional fields for games: $e');
          print('[DEBUG] This might be an RLS issue. Will try to get creator from invites table.');
        }
        // Try to get creator_id from invites table as fallback
        try {
          final inviteRows = await supa
              .from('instant_request_invites')
              .select('request_id, created_by')
              .inFilter('request_id', gameIdsForAdditionalFields);
          
          if (inviteRows is List) {
            for (final inv in inviteRows) {
              final reqId = inv['request_id'] as String?;
              final createdBy = inv['created_by'] as String?;
              if (reqId != null && createdBy != null) {
                if (additionalByGameId[reqId] == null) {
                  additionalByGameId[reqId] = {};
                }
                additionalByGameId[reqId]!['created_by'] = createdBy;
                additionalByGameId[reqId]!['creator_id'] = createdBy;
                if (kDebugMode) {
                  print('[DEBUG] Got creator from invites table for game $reqId: $createdBy');
                }
              }
            }
          }
        } catch (e2) {
          if (kDebugMode) {
            print('[ERROR] Failed to fetch creator from invites table: $e2');
          }
        }
      }
      
      // Merge additional fields into games
      // Note: The RPC function now returns created_by and creator_id, so we can use those directly
      final enrichedGames = allGames.map((game) {
        final id = game['id'] as String;
        final additional = additionalByGameId[id] ?? {};
        return {
          ...game,
          'details': additional['details'] ?? game['details'],
          // Use RPC function's created_by/creator_id first, then fallback to additional fields
          'created_by': game['created_by'] ?? additional['created_by'],
          'creator_id': game['creator_id'] ?? additional['creator_id'] ?? game['created_by'],
          'visibility': additional['visibility'] ?? game['visibility'] ?? 'invited',
          'is_public': additional['is_public'] ?? game['is_public'] ?? false,
        };
      }).toList();
      
      final allGamesFinal = enrichedGames;
      
      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Found ${allGamesFinal.length} games via RPC');
      }
      
      // Get game IDs for invite lookup
      final gameIds = allGamesFinal.map<String>((g) => g['id'] as String).toList();
      
      // Get all invites for these games (including all statuses to determine if it's an open challenge)
      final invites = await supa
          .from('instant_request_invites')
          .select('request_id, target_team_id, status')
          .inFilter('request_id', gameIds);
      
      // Group invites by request_id
      final Map<String, List<Map<String, dynamic>>> invitesByRequestId = {};
      if (invites is List) {
        for (final inv in invites) {
          final reqId = inv['request_id'] as String?;
          if (reqId != null) {
            invitesByRequestId.putIfAbsent(reqId, () => []).add(inv);
          }
        }
        if (kDebugMode) {
          print('[DEBUG] Fetched ${invites.length} invites for ${gameIds.length} games');
          print('[DEBUG] Invites by request_id: ${invitesByRequestId.keys.length} games have invites');
          for (final entry in invitesByRequestId.entries.take(3)) {
            print('[DEBUG] Game ${entry.key.substring(0, 8)}: ${entry.value.length} invites');
            for (final inv in entry.value) {
              print('[DEBUG]   - Team ${inv['target_team_id']}, Status: ${inv['status']}');
            }
          }
        }
      } else {
        if (kDebugMode) {
          print('[DEBUG] No invites found or error fetching invites');
        }
      }
      
      // Since user has attendance records for these games, they should see all of them
      // Only filter out games where all invites have been accepted/denied (game is confirmed or cancelled)
      final filteredGames = <dynamic>[];
      for (final game in allGamesFinal) {
        final reqId = game['id'] as String;
        
        // Explicitly exclude cancelled games
        final status = (game['status'] as String?)?.toLowerCase();
        final isCancelled = status == 'cancelled';
        
        if (isCancelled) {
          if (kDebugMode) {
            print('[DEBUG] Filtering out cancelled game from awaiting confirmation: $reqId, status=$status');
          }
          continue; // Skip cancelled games - they should not appear in "Awaiting Opponent Confirmation"
        }
        
        final gameInvites = invitesByRequestId[reqId] ?? [];
        
        // Get the user's team ID for this game from attendance record
        final userTeamIdForThisGame = userTeamIdByGameId[reqId];
        
        // Check if the user's team has denied the invite
        // If so, exclude this game from the list (team members shouldn't see denied games)
        if (userTeamIdForThisGame != null && gameInvites.isNotEmpty) {
          // Find the invite for the user's team
          Map<String, dynamic>? userTeamInvite;
          for (final inv in gameInvites) {
            final targetTeamId = inv['target_team_id'] as String?;
            if (targetTeamId == userTeamIdForThisGame) {
              userTeamInvite = inv;
              break;
            }
          }
          
          if (userTeamInvite != null) {
            final userTeamInviteStatus = (userTeamInvite['status'] as String?)?.toLowerCase();
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: userTeamId=$userTeamIdForThisGame, inviteStatus=$userTeamInviteStatus');
            }
            if (userTeamInviteStatus == 'denied') {
              if (kDebugMode) {
                print('[DEBUG] Filtering out game where user team denied: $reqId, userTeamId=$userTeamIdForThisGame');
              }
              continue; // Skip games where the user's team has denied
            }
          } else if (kDebugMode) {
            print('[DEBUG] Game $reqId: No invite found for userTeamId=$userTeamIdForThisGame, allInvites=${gameInvites.map((i) => '${i['target_team_id']}:${i['status']}').join(', ')}');
          }
        }
        
        // Check if any invite is still pending
        final hasPendingInvite = gameInvites.any((inv) => 
          (inv['status'] as String?)?.toLowerCase() == 'pending'
        );
        final isOpenChallenge = gameInvites.isEmpty;
        
        // Include if:
        // 1. It's an open challenge (no invites), OR
        // 2. There are still pending invites (game still awaiting opponent confirmation)
        // Since user has attendance record, they're part of this game and should see it
        // BUT exclude if their team has denied (checked above)
        // Also exclude if user is on an invited team that has denied (already checked above)
        if (isOpenChallenge || hasPendingInvite) {
          // Double-check: if user is on an invited team and that team denied, don't include
          if (userTeamIdForThisGame != null) {
            final creatingTeamId = game['team_id'] as String?;
            final isUserOnCreatingTeam = creatingTeamId != null && userTeamIdForThisGame == creatingTeamId;
            
            // Only check denial if user is NOT on the creating team
            if (!isUserOnCreatingTeam) {
              final userTeamDenied = gameInvites.any((inv) {
                final targetTeamId = inv['target_team_id'] as String?;
                final status = (inv['status'] as String?)?.toLowerCase();
                return targetTeamId == userTeamIdForThisGame && status == 'denied';
              });
              
              if (userTeamDenied) {
                if (kDebugMode) {
                  print('[DEBUG] Final check: Filtering out game where user team denied: $reqId');
                }
                continue; // Skip games where the user's team has denied
              }
            }
          }
          
          filteredGames.add(game);
        }
      }
      
      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Filtered ${filteredGames.length} games from ${allGames.length} total games with attendance');
        print('[DEBUG] User team IDs: $userTeamIds');
        if (filteredGames.isNotEmpty) {
          for (final game in filteredGames.take(3)) {
            final reqId = game['id'] as String;
            final invites = invitesByRequestId[reqId] ?? [];
            print('[DEBUG] Game ${reqId.substring(0, 8)}: team_id=${game['team_id']}, invites=${invites.length}, pending=${invites.where((i) => (i['status'] as String?)?.toLowerCase() == 'pending').length}');
          }
        }
      }
      
      if (filteredGames.isEmpty) {
        if (kDebugMode) {
          print('[DEBUG] getAwaitingOpponentConfirmationGames: No games match criteria after filtering');
        }
        return [];
      }

      // Use filteredGames as the final list
      final finalGames = filteredGames;

      // Get team names - include all teams from games, invites, AND user's teams from attendance records
      final allTeamIds = <String>{};
      for (final g in finalGames) {
        final teamId = g['team_id'] as String?;
        if (teamId != null) allTeamIds.add(teamId);
      }
      if (invites is List) {
        for (final inv in invites) {
          final teamId = inv['target_team_id'] as String?;
          if (teamId != null) allTeamIds.add(teamId);
        }
      }
      // Add user's teams from attendance records to ensure we can look up their team names
      for (final teamId in userTeamIdByGameId.values) {
        allTeamIds.add(teamId);
      }
      
      if (kDebugMode) {
        print('[DEBUG] Fetching team names for ${allTeamIds.length} teams: $allTeamIds');
      }

      final teamNames = <String, String>{};
      if (allTeamIds.isNotEmpty) {
        final teamRows = await supa
            .from('teams')
            .select('id, name')
            .inFilter('id', allTeamIds.toList());
        if (teamRows is List) {
          for (final t in teamRows) {
            final id = t['id'] as String?;
            if (id != null) {
              teamNames[id] = (t['name'] as String?) ?? '';
            }
          }
        }
      }

      // Get creator names
      final creatorIds = finalGames
          .map<String?>((g) => g['created_by'] as String? ?? g['creator_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Creator IDs to fetch: $creatorIds');
      }

      final creatorNames = <String, String>{};
      if (creatorIds.isNotEmpty) {
        try {
          final userRows = await supa
              .from('users')
              .select('id, full_name')
              .inFilter('id', creatorIds);
          if (userRows is List) {
            for (final u in userRows) {
              final id = u['id'] as String?;
              if (id != null) {
                final name = u['full_name'] as String?;
                creatorNames[id] = name ?? 'Unknown';
                if (kDebugMode) {
                  print('[DEBUG] Creator $id: $name');
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[ERROR] Failed to fetch creator names: $e');
          }
          // Continue with empty creator names - will show "Unknown"
        }
      }

      // Build result list - only include games with pending invites or open challenge
      final result = <Map<String, dynamic>>[];
      for (final game in finalGames) {
        final reqId = game['id'] as String;
        final gameInvites = invitesByRequestId[reqId] ?? [];
        
        // Check if any invite is still pending
        final hasPendingInvite = gameInvites.any((inv) => 
          (inv['status'] as String?)?.toLowerCase() == 'pending'
        );

        // For open challenge, check if no invites exist or all are pending
        final isOpenChallenge = gameInvites.isEmpty || 
          gameInvites.every((inv) => (inv['status'] as String?)?.toLowerCase() == 'pending');

        // Only include if there are pending invites (specific teams) or it's an open challenge
        if (hasPendingInvite || isOpenChallenge) {
          final creatingTeamId = game['team_id'] as String?;
          final creatingTeamName = teamNames[creatingTeamId] ?? 'Unknown Team';
          
          // Get the user's team ID for this game from attendance record
          final userTeamIdForThisGame = userTeamIdByGameId[reqId];
          
          // Determine which team the user belongs to
          final isUserOnCreatingTeam = creatingTeamId != null && userTeamIdForThisGame == creatingTeamId;
          
          // Get opponent team names (for specific invites) or mark as "Open Challenge"
          // Include ALL invites (not just pending) to determine opponent teams
          // This ensures we show the correct opponent names even if some invites are accepted/denied
          final allInvitesForOpponentNames = gameInvites.toList();
          final pendingInvites = gameInvites.where((inv) => 
            (inv['status'] as String?)?.toLowerCase() == 'pending'
          ).toList();
          
          // Build opponent team names from ALL invites (to show all invited teams)
          // First, ensure all invited team names are fetched
          final opponentTeamIds = allInvitesForOpponentNames
              .map((inv) => inv['target_team_id'] as String?)
              .where((tid) => tid != null)
              .cast<String>()
              .toSet();
          
          // Fetch any missing team names before building opponentTeamNames
          final missingTeamIds = opponentTeamIds.where((tid) => 
            !teamNames.containsKey(tid) || teamNames[tid] == null || teamNames[tid]!.isEmpty
          ).toList();
          
          if (missingTeamIds.isNotEmpty) {
            try {
              final missingTeamRows = await supa
                  .from('teams')
                  .select('id, name')
                  .inFilter('id', missingTeamIds);
              if (missingTeamRows is List) {
                for (final t in missingTeamRows) {
                  final id = t['id'] as String?;
                  if (id != null) {
                    teamNames[id] = (t['name'] as String?) ?? '';
                  }
                }
                if (kDebugMode) {
                  print('[DEBUG] Fetched ${missingTeamRows.length} missing team names for opponent teams: $missingTeamIds');
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('[ERROR] Failed to fetch missing team names: $e');
              }
            }
          }
          
          final opponentTeamNames = allInvitesForOpponentNames
              .map((inv) => teamNames[inv['target_team_id'] as String?] ?? 'Unknown Team')
              .where((name) => name.isNotEmpty && name != 'Unknown Team')
              .toList();
          
          if (kDebugMode) {
            print('[DEBUG] Game $reqId: opponentTeamIds=$opponentTeamIds, opponentTeamNames=$opponentTeamNames, allInvitesForOpponentNames.length=${allInvitesForOpponentNames.length}');
          }
          
          // Determine user's team name and which team ID to use
          String myTeamName;
          List<String> otherTeamNames;
          String? myTeamId;
          
          if (isUserOnCreatingTeam) {
            // User is on the creating team
            myTeamName = creatingTeamName;
            myTeamId = creatingTeamId;
            otherTeamNames = opponentTeamNames;
          } else if (userTeamIdForThisGame != null) {
            // User is on an invited team - use the team ID from attendance record
            myTeamId = userTeamIdForThisGame;
            myTeamName = teamNames[myTeamId] ?? '';
            if (myTeamName.isEmpty) {
              // If team name not found, try to fetch it
              try {
                final teamRow = await supa
                    .from('teams')
                    .select('name')
                    .eq('id', myTeamId)
                    .maybeSingle();
                if (teamRow != null) {
                  myTeamName = (teamRow['name'] as String?) ?? 'My Team';
                  teamNames[myTeamId] = myTeamName; // Cache it
                } else {
                  myTeamName = 'My Team';
                }
              } catch (e) {
                if (kDebugMode) {
                  print('[ERROR] Failed to fetch team name for $myTeamId: $e');
                }
                myTeamName = 'My Team';
              }
            }
            // User is on an invited team - show creating team and other invited teams as opponents
            otherTeamNames = [creatingTeamName];
            // Add other invited teams (from ALL invites, not just pending)
            for (final inv in allInvitesForOpponentNames) {
              final tid = inv['target_team_id'] as String?;
              if (tid != null && tid != userTeamIdForThisGame && tid != creatingTeamId) {
                final name = teamNames[tid];
                if (kDebugMode) {
                  print('[DEBUG] Invited team member view: checking invite team $tid, name=$name, userTeamId=$userTeamIdForThisGame, creatingTeamId=$creatingTeamId');
                }
                if (name != null && name.isNotEmpty && !otherTeamNames.contains(name)) {
                  otherTeamNames.add(name);
                  if (kDebugMode) {
                    print('[DEBUG] Added opponent team: $name');
                  }
                } else if (name == null || name.isEmpty) {
                  // Try to fetch team name if not in cache
                  try {
                    final teamRow = await supa
                        .from('teams')
                        .select('name')
                        .eq('id', tid)
                        .maybeSingle();
                    if (teamRow != null) {
                      final fetchedName = (teamRow['name'] as String?) ?? '';
                      if (fetchedName.isNotEmpty) {
                        teamNames[tid] = fetchedName; // Cache it
                        if (!otherTeamNames.contains(fetchedName)) {
                          otherTeamNames.add(fetchedName);
                          if (kDebugMode) {
                            print('[DEBUG] Fetched and added opponent team: $fetchedName');
                          }
                        }
                      }
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      print('[ERROR] Failed to fetch team name for $tid: $e');
                    }
                  }
                }
              }
            }
            
            if (kDebugMode) {
              print('[DEBUG] Final otherTeamNames for invited team member: $otherTeamNames');
            }
          } else {
            // Fallback (shouldn't happen if attendance records are correct)
            myTeamName = creatingTeamName;
            myTeamId = creatingTeamId;
            otherTeamNames = opponentTeamNames;
          }

          final startTime1 = game['start_time_1'] as String?;
          final startTime2 = game['start_time_2'] as String?;
          DateTime? startDt;
          DateTime? endDt;
          if (startTime1 != null) {
            try {
              startDt = DateTime.parse(startTime1).toLocal();
            } catch (_) {}
          }
          if (startTime2 != null) {
            try {
              endDt = DateTime.parse(startTime2).toLocal();
            } catch (_) {}
          }

          final creatorId = game['created_by'] as String? ?? game['creator_id'] as String?;
          
          // Determine if it's an open challenge (no specific team invites)
          // It's an open challenge ONLY if there are no invites at all
          // If there are any invites (even if pending), it's NOT an open challenge
          final isOpenChallengeGame = gameInvites.isEmpty;
          
          if (kDebugMode) {
            print('[DEBUG] Game $reqId: gameInvites.length=${gameInvites.length}, isOpenChallenge=$isOpenChallengeGame');
            print('[DEBUG] Game $reqId: isUserOnCreatingTeam=$isUserOnCreatingTeam, creatingTeamId=$creatingTeamId, userTeamIdForThisGame=$userTeamIdForThisGame');
            print('[DEBUG] Game $reqId: opponentTeamNames=$opponentTeamNames, otherTeamNames=$otherTeamNames');
            print('[DEBUG] Game $reqId: allInvitesForOpponentNames=${allInvitesForOpponentNames.map((i) => '${i['target_team_id']}').join(', ')}');
          }
          
          // Fetch creator name if not already fetched
          String creatorName = creatorNames[creatorId] ?? 'Unknown';
          if (creatorName == 'Unknown' && creatorId != null) {
            try {
              final creatorRow = await supa
                  .from('users')
                  .select('full_name')
                  .eq('id', creatorId)
                  .maybeSingle();
              if (creatorRow != null) {
                creatorName = (creatorRow['full_name'] as String?) ?? 'Unknown';
                creatorNames[creatorId] = creatorName; // Cache it
              }
            } catch (e) {
              if (kDebugMode) {
                print('[ERROR] Failed to fetch creator name for $creatorId: $e');
              }
            }
          }
          
          result.add({
            'request_id': reqId,
            'sport': game['sport'],
            'team_id': creatingTeamId,
            'my_team_id': myTeamId,
            'team_name': myTeamName, // This should be the user's team name from attendance record
            'opponent_teams': otherTeamNames,
            // Only set is_open_challenge to true if there are NO opponent teams
            // If there are opponent teams, it's NOT an open challenge (even if gameInvites was empty)
            'is_open_challenge': isOpenChallengeGame && otherTeamNames.isEmpty,
            'start_time': startDt,
            'end_time': endDt,
            'venue': game['venue'],
            'details': game['details'],
            'creator_id': creatorId,
            'creator_name': creatorName,
            'status': game['status'],
            'visibility': game['visibility'],
            'is_public': game['is_public'] as bool? ?? false,
          });
          
          if (kDebugMode) {
            print('[DEBUG] Added game $reqId: myTeamName=$myTeamName, creatorName=$creatorName');
            print('[DEBUG] Added game $reqId: isOpenChallenge=$isOpenChallengeGame, otherTeamNames=$otherTeamNames, final is_open_challenge=${isOpenChallengeGame && otherTeamNames.isEmpty}');
          }
        }
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] getAwaitingOpponentConfirmationGames: $e');
      }
      return [];
    }
  }

  /// Get public games that match user's notification preferences
  /// Returns games within user's notification radius and matching sports
  Future<List<Map<String, dynamic>>> getPublicGamesForUser({
    required String userId,
    required String? userZipCode,
    required double? userLat,
    required double? userLng,
  }) async {
    try {
      // Get user's notification preferences
      final userRow = await supa
          .from('users')
          .select('notification_radius_miles, notification_sports')
          .eq('id', userId)
          .maybeSingle();

      final notificationRadius = (userRow?['notification_radius_miles'] as int?) ?? 25;
      final notificationSports = (userRow?['notification_sports'] as List<dynamic>?)?.map((s) => s.toString().toLowerCase()).toList() ?? [];
      final notifyAllSports = notificationSports.isEmpty;

      // Get all public games (individual and team)
      final publicGames = await supa
          .from('instant_match_requests')
          .select('id, sport, zip_code, mode, match_type, start_time_1, start_time_2, venue, status, created_by, creator_id, radius_miles, visibility, is_public, num_players, proficiency_level, details')
          .eq('is_public', true)
          .eq('visibility', 'public')
          .neq('status', 'cancelled')
          .neq('created_by', userId); // Exclude games created by user

      if (publicGames is! List || publicGames.isEmpty) {
        return [];
      }

      final matchingGames = <Map<String, dynamic>>[];

      for (final game in publicGames) {
        final gameSport = (game['sport'] as String? ?? '').toLowerCase();
        
        // Check sport filter
        if (!notifyAllSports && !notificationSports.contains(gameSport)) {
          continue;
        }

        // Check distance (if we have coordinates, use them; otherwise use ZIP)
        bool isWithinRadius = false;
        
        if (userLat != null && userLng != null) {
          // Use coordinates for distance calculation
          final gameZip = game['zip_code'] as String?;
          if (gameZip != null) {
            // For now, if ZIP codes match, consider within radius
            // TODO: Implement proper distance calculation using coordinates
            // For simplicity, if user has coordinates, we'll check ZIP match or use game's radius
            final gameRadius = game['radius_miles'] as int? ?? 75;
            // If game radius is large enough, include it
            if (gameRadius >= notificationRadius) {
              isWithinRadius = true;
            } else if (gameZip == userZipCode) {
              isWithinRadius = true;
            }
          }
        } else if (userZipCode != null) {
          // Use ZIP code matching
          final gameZip = game['zip_code'] as String?;
          final gameRadius = game['radius_miles'] as int? ?? 75;
          
          if (gameZip == userZipCode) {
            isWithinRadius = true;
          } else if (gameRadius >= notificationRadius) {
            // If game has a large radius, include it
            isWithinRadius = true;
          }
        }

        if (isWithinRadius) {
          // Get creator info
          final creatorId = game['created_by'] as String? ?? game['creator_id'] as String?;
          Map<String, dynamic>? creatorInfo;
          if (creatorId != null) {
            creatorInfo = await supa
                .from('users')
                .select('id, full_name, photo_url')
                .eq('id', creatorId)
                .maybeSingle() as Map<String, dynamic>?;
          }

          // Parse dates
          DateTime? startDt;
          DateTime? endDt;
          if (game['start_time_1'] != null) {
            try {
              startDt = DateTime.parse(game['start_time_1']).toLocal();
            } catch (_) {}
          }
          if (game['start_time_2'] != null) {
            try {
              endDt = DateTime.parse(game['start_time_2']).toLocal();
            } catch (_) {}
          }

          matchingGames.add({
            'request_id': game['id'],
            'sport': game['sport'],
            'mode': game['mode'],
            'match_type': game['match_type'],
            'start_time': startDt,
            'end_time': endDt,
            'venue': game['venue'],
            'details': game['details'],
            'creator_id': creatorId,
            'creator_name': creatorInfo?['full_name'] ?? 'Unknown',
            'creator_photo': creatorInfo?['photo_url'],
            'num_players': game['num_players'],
            'proficiency_level': game['proficiency_level'],
            'status': game['status'],
            'visibility': game['visibility'],
            'is_public': true,
          });
        }
      }

      // Sort by start time (newest first)
      matchingGames.sort((a, b) {
        final ad = a['start_time'] as DateTime?;
        final bd = b['start_time'] as DateTime?;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      return matchingGames;
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] getPublicGamesForUser: $e');
      }
      return [];
    }
  }
}
