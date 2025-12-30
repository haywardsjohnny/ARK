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

    // Get invites where:
    // 1. User's teams are the target (invited teams) - existing logic
    // 2. User's teams are the creating team and other teams are joining (open challenge joins)
    //    - This is for open challenge games where other teams clicked "Join"
    
    // First, get invites where user's teams are the target (existing logic)
    // But exclude invites for games created by user's teams (those are handled separately)
    final inviteRows1 = await supa
        .from('instant_request_invites')
        .select('id, request_id, target_team_id, status')
        .inFilter('target_team_id', teamIds)
        .eq('status', 'pending');
    
    // Get games created by user's teams to filter them out
    final gamesCreatedByUserTeamsForFilter = await supa
        .from('instant_match_requests')
        .select('id')
        .inFilter('team_id', teamIds)
        .eq('mode', 'team_vs_team')
        .neq('status', 'cancelled');
    
    final gameIdsCreatedByUserTeamsForFilter = <String>[];
    if (gamesCreatedByUserTeamsForFilter is List) {
      for (final game in gamesCreatedByUserTeamsForFilter) {
        final gameId = game['id'] as String?;
        if (gameId != null) gameIdsCreatedByUserTeamsForFilter.add(gameId);
      }
    }
    
    // Filter out invites where:
    // 1. The game was created by user's team (these are handled in getPendingTeamMatchesForAdmin)
    // 2. The game is public AND user's team is the responding team (Team X clicked "Join")
    //    - For public games, if user's team is target_team_id, it means they clicked "Join"
    //    - These should only appear in Discover with status, NOT in "Pending Admin Approval"
    // 3. The game is invite-specific (non-public) - these should only appear in getPendingTeamMatchesForAdmin
    //    - This prevents duplicate entries where the same game appears in both pendingInvites and pendingAdminMatches
    
    // First, get all game details for invites in one query
    final inviteReqIds = <String>[];
    if (inviteRows1 is List) {
      for (final inv in inviteRows1) {
        final reqId = inv['request_id'] as String?;
        if (reqId != null && !gameIdsCreatedByUserTeamsForFilter.contains(reqId)) {
          inviteReqIds.add(reqId);
        }
      }
    }
    
    // Fetch game details for all invites
    final gameDetails = <String, Map<String, dynamic>>{};
    if (inviteReqIds.isNotEmpty) {
      final gameRows = await supa
          .from('instant_match_requests')
          .select('id, team_id, visibility, is_public')
          .inFilter('id', inviteReqIds);
      
      if (gameRows is List) {
        for (final game in gameRows) {
          final gameId = game['id'] as String?;
          if (gameId != null) {
            gameDetails[gameId] = Map<String, dynamic>.from(game);
          }
        }
      }
    }
    
    // Now filter invites
    final filteredInviteRows1 = <dynamic>[];
    if (inviteRows1 is List) {
      for (final inv in inviteRows1) {
        final reqId = inv['request_id'] as String?;
        if (reqId == null) continue;
        
        // Skip if the game was created by user's team
        if (gameIdsCreatedByUserTeamsForFilter.contains(reqId)) {
          continue;
        }
        
        // Check if this is a public game where user's team is the responding team
        final gameInfo = gameDetails[reqId];
        if (gameInfo != null) {
          final gameTeamId = gameInfo['team_id'] as String?;
          final visibility = (gameInfo['visibility'] as String?)?.toLowerCase();
          final isPublic = gameInfo['is_public'] as bool? ?? false;
          
          // If this is a public game and the game was NOT created by user's team,
          // then user's team is the responding team (they clicked "Join")
          // These should NOT appear in "Pending Admin Approval" - only in Discover
          if ((visibility == 'public' || isPublic) && 
              gameTeamId != null && 
              !teamIds.contains(gameTeamId)) {
            if (kDebugMode) {
              print('[DEBUG] Filtering out public game invite: reqId=$reqId, user\'s team is responding team (clicked Join)');
            }
            continue; // Skip public games where user's team is the responding team
          }
          
          // IMPORTANT: Filter out invite-specific (non-public) games
          // These should only appear in getPendingTeamMatchesForAdmin, not here
          // This prevents duplicate entries in "Pending Admin Approval"
          if (!(visibility == 'public' || isPublic)) {
            if (kDebugMode) {
              print('[DEBUG] Filtering out invite-specific game from getPendingInvitesForTeams: reqId=$reqId (will appear in getPendingTeamMatchesForAdmin instead)');
            }
            continue; // Skip invite-specific games - they're handled by getPendingTeamMatchesForAdmin
          }
        }
        
        // This is a valid invite where user's team is the target (invited)
        // Only public games should reach here
        filteredInviteRows1.add(inv);
      }
    }
    
    // DO NOT include invites for games created by user's teams here
    // Those are handled separately in getPendingTeamMatchesForAdmin
    // This keeps public game logic separate from invite-specific team logic
    
    // Use only filteredInviteRows1 (invites where user's team is the target, game NOT created by user's team)
    final allInviteRows = <dynamic>[];
    allInviteRows.addAll(filteredInviteRows1);
    
    // Remove duplicates based on invite ID
    final uniqueInviteIds = <String>{};
    final inviteRows = allInviteRows.where((inv) {
      final id = inv['id'] as String?;
      if (id == null) return false;
      if (uniqueInviteIds.contains(id)) return false;
      uniqueInviteIds.add(id);
      return true;
    }).toList();

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

  /// Request to join an open challenge team game
  /// Creates an invite from the joining team to the creating team
  Future<void> requestToJoinOpenChallengeTeamGame({
    required String requestId,
    required String joiningTeamId,
    required String userId,
  }) async {
    // Check if invite already exists
    final existingInvite = await supa
        .from('instant_request_invites')
        .select('id, status')
        .eq('request_id', requestId)
        .eq('target_team_id', joiningTeamId)
        .maybeSingle();
    
    if (existingInvite != null) {
      final status = (existingInvite['status'] as String?)?.toLowerCase();
      if (status == 'pending') {
        throw Exception('You have already requested to join this game');
      } else if (status == 'accepted') {
        throw Exception('Your team has already been accepted for this game');
      } else if (status == 'denied') {
        // Allow re-requesting if previously denied
      }
    }

    // Create new invite with pending status
    await supa
        .from('instant_request_invites')
        .insert({
          'request_id': requestId,
          'target_team_id': joiningTeamId,
          'status': 'pending',
          'target_type': 'team',  // Required field for team invites
        });
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
    
    if (adminTeams.isEmpty) {
      if (kDebugMode) {
        print('[DEBUG] getPendingTeamMatchesForAdmin: Returning empty - adminTeams.isEmpty=true');
      }
      return [];
    }
    
    // Note: userZipCode can be null - we'll handle it gracefully in radius checks
    // For invite-specific games, we'll skip radius checks if ZIP is null (since team was specifically invited)

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

      // Check if this request is from one of user's admin teams
      final isCreatedByUserTeam = adminTeamIds.contains(reqTeamId);
      
      // For public games created by user's team, we want to show them if another team has responded
      // For non-public games created by user's team, skip them (they're not pending admin approval)
      if (isCreatedByUserTeam && !(visibility == 'public' || isPublic)) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: created by user\'s own team (non-public game)');
        continue;
      }
      
      // For games NOT created by user's team, skip if sport doesn't match
      if (!isCreatedByUserTeam && !adminSports.contains(reqSport)) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: sport mismatch (reqSport=$reqSport, adminSports=$adminSports)');
        continue;
      }
      
      // For games created by user's team, ensure sport matches
      if (isCreatedByUserTeam && !adminSports.contains(reqSport)) {
        if (kDebugMode) print('[DEBUG] Skipping request $reqId: sport mismatch for user\'s own team (reqSport=$reqSport, adminSports=$adminSports)');
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
        // Non-public games (invite-specific): For invite-specific games, if ZIP is null,
        // assume within radius since the team was specifically invited
        if (reqZip == null || userZipCode == null) {
          if (kDebugMode) {
            print('[DEBUG] Request $reqId: Non-public game with missing ZIP codes (reqZip=$reqZip, userZipCode=$userZipCode) - assuming within radius for invite-specific game');
          }
          isWithinRadius = true; // Invite-specific games: assume within radius if ZIP unavailable
        } else {
          // If ZIP codes match (same area), definitely within range
          // Otherwise, check if game radius overlaps with team notification radius
          isWithinRadius = reqZip == userZipCode || reqRadiusMiles >= teamNotificationRadius;
        }
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
      
      // SEPARATE LOGIC: Public games vs Invite-specific teams
      if (isCreatedByUserTeam) {
        // PUBLIC GAME LOGIC: Only show if another team has responded (clicked "Join")
        if (!(visibility == 'public' || isPublic)) {
          if (kDebugMode) print('[DEBUG] Skipping request $reqId: Created by user\'s team but not public');
          continue;
        }
        
        // Check if there's a pending invite from another team (not the user's team)
        final gameInvites = await supa
            .from('instant_request_invites')
            .select('id, target_team_id, status')
            .eq('request_id', reqId);
        
        if (gameInvites is! List || gameInvites.isEmpty) {
          if (kDebugMode) print('[DEBUG] Skipping request $reqId: Public game created by user\'s team but no invites exist yet');
          continue;
        }
        
        // Find ALL pending invites from other teams (not the user's team)
        // This allows showing multiple teams (Team X, Team Y, etc.) that have requested to join
        final pendingInvitesFromOtherTeams = gameInvites.where((inv) {
          final targetTeamId = inv['target_team_id'] as String?;
          final status = (inv['status'] as String?)?.toLowerCase();
          return targetTeamId != null 
              && !adminTeamIds.contains(targetTeamId) 
              && status == 'pending';
        }).toList();
        
        if (pendingInvitesFromOtherTeams.isEmpty) {
          if (kDebugMode) print('[DEBUG] Skipping request $reqId: No pending invites from other teams');
          continue;
        }
        
        // Get team info (the creating team - Team A)
        final teamInfo = await supa
            .from('teams')
            .select('id, name, sport, zip_code')
            .eq('id', reqTeamId)
            .maybeSingle();

        if (teamInfo == null) {
          if (kDebugMode) print('[DEBUG] Skipping request $reqId: teamInfo is null');
          continue;
        }
        
        // Create a separate entry for EACH pending invite (Team X, Team Y, etc.)
        for (final pendingInvite in pendingInvitesFromOtherTeams) {
          final respondingTeamId = pendingInvite['target_team_id'] as String?;
          
          // Get responding team info (Team X, Team Y, etc.)
          Map<String, dynamic>? respondingTeamInfo;
          if (respondingTeamId != null) {
            respondingTeamInfo = await supa
                .from('teams')
                .select('id, name, sport')
                .eq('id', respondingTeamId)
                .maybeSingle();
          }
          
          if (kDebugMode) {
            print('[DEBUG] ✓ Adding pending match (PUBLIC GAME): requestId=$reqId, teamName=${teamInfo['name']}, respondingTeamName=${respondingTeamInfo?['name']}');
          }
          pendingMatches.add({
            'request': req,
            'team': teamInfo,
            'admin_team': matchingAdminTeam,
            'responding_team': respondingTeamInfo,
            'responding_team_id': respondingTeamId, // Add this for deny function
          });
        }
        continue; // Done with this public game
      } else {
        // INVITE-SPECIFIC TEAM LOGIC: Games NOT created by user's team
        // IMPORTANT: Public games should NOT appear here - they should only appear in Discover
        // Only invite-specific games (non-public) should appear in "Pending Admin Approval"
        if (visibility == 'public' || isPublic) {
          if (kDebugMode) print('[DEBUG] Skipping request $reqId: Public game NOT created by user\'s team - should only appear in Discover, not Pending Admin Approval');
          continue; // Public games should only appear in Discover, not in Pending Admin Approval
        }
        
        // Check if user's admin team is in the list of invited teams
        // Get all invites for this game to check if user's team is invited
        final gameInvites = await supa
            .from('instant_request_invites')
            .select('target_team_id, status')
            .eq('request_id', reqId);
        
        if (gameInvites is! List || gameInvites.isEmpty) {
          if (kDebugMode) print('[DEBUG] Skipping request $reqId: No invites found for this game');
          continue;
        }
        
        // Check if user's admin team is one of the invited teams
        // IMPORTANT: Show to ALL invited team admins, regardless of invite status
        // (pending, accepted, denied - admins should see it if their team was invited)
        final isUserTeamInvited = gameInvites.any((inv) {
          final targetTeamId = inv['target_team_id'] as String?;
          return targetTeamId == adminTeamId;
        });
        
        if (!isUserTeamInvited) {
          if (kDebugMode) print('[DEBUG] Skipping request $reqId: User\'s admin team $adminTeamId is not in the invited teams list');
          continue;
        }
        
        // Check invite status - only show if status is 'pending' (not accepted/denied)
        final userTeamInvite = gameInvites.firstWhere(
          (inv) => inv['target_team_id'] == adminTeamId,
          orElse: () => <String, dynamic>{},
        );
        
        final inviteStatus = (userTeamInvite['status'] as String?)?.toLowerCase();
        if (inviteStatus != 'pending') {
          if (kDebugMode) {
            print('[DEBUG] Skipping request $reqId: Invite status is $inviteStatus (not pending)');
          }
          continue; // Only show pending invites in "Pending Admin Approval"
        }
        
        // Get team info (the creating team)
        final teamInfo = await supa
            .from('teams')
            .select('id, name, sport, zip_code')
            .eq('id', reqTeamId)
            .maybeSingle();

        if (teamInfo != null) {
          if (kDebugMode) {
            print('[DEBUG] ✓ Adding pending match (INVITE-SPECIFIC): requestId=$reqId, teamName=${teamInfo['name']}, adminTeamId=$adminTeamId');
          }
          pendingMatches.add({
            'request': req,
            'team': teamInfo,
            'admin_team': matchingAdminTeam,
            'responding_team': null,  // No responding team for invite-specific games
          });
        }
        continue; // Done with this invite-specific game
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

    // Deduplicate by request_id to prevent duplicates when user switches teams
    // (e.g., if user is creator and has attendance record, RPC might return both)
    final seenRequestIds = <String>{};
    final deduplicatedReqs = <dynamic>[];
    for (final req in reqs) {
      final reqId = req['id'] as String?;
      if (reqId != null && !seenRequestIds.contains(reqId)) {
        seenRequestIds.add(reqId);
        deduplicatedReqs.add(req);
      } else if (reqId != null && kDebugMode) {
        print('[DEBUG] loadAllMatchesForUser: Filtered out duplicate game $reqId');
      }
    }

    if (kDebugMode && deduplicatedReqs.length < reqs.length) {
      print('[DEBUG] loadAllMatchesForUser: Deduplicated ${reqs.length} matches to ${deduplicatedReqs.length} unique games');
    }

    // Extract request IDs for fetching additional data
    final requestIds = deduplicatedReqs
        .map<String>((r) => r['id'] as String)
        .toSet()
        .toList();

    // Now fetch team names and attendance data (same as before)
    // Use deduplicatedReqs to prevent processing duplicates
    return _enrichTeamMatchesWithDetails(deduplicatedReqs, requestIds, myUserId);
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

    final Map<String, String> userNameById = {};
    if (allUserIds.isNotEmpty) {
      try {
        // Use RPC function to get display names (bypasses RLS and includes email fallback)
        final displayNamesResult = await supa.rpc(
          'get_user_display_names',
          params: {'p_user_ids': allUserIds.toList()},
        );
        
        if (displayNamesResult is List) {
          for (final u in displayNamesResult) {
            final id = u['user_id'] as String?;
            final displayName = u['display_name'] as String?;
            if (id != null && displayName != null) {
              userNameById[id] = displayName;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DEBUG] Failed to fetch user display names via RPC: $e');
        }
        // Fallback to direct query (will only return current user due to RLS)
        final users = await supa
            .from('users')
            .select('id, full_name')
            .inFilter('id', allUserIds.toList());

    if (users is List) {
      for (final u in users) {
        final id = u['id'] as String?;
        if (id != null) {
          userNameById[id] = (u['full_name'] as String?) ?? 'Player';
            }
          }
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

      // Get ALL members of both teams (not just those with attendance records)
      final allTeamAMembers = await supa
          .from('team_members')
          .select('user_id, role')
          .eq('team_id', teamAId);
      
      final allTeamBMembers = await supa
          .from('team_members')
          .select('user_id, role')
          .eq('team_id', teamBId);
      
      // Build a map of all user IDs in both teams
      final allUserIdsInBothTeams = <String>{};
      final Map<String, String> userRoleInTeamA = {};
      final Map<String, String> userRoleInTeamB = {};
      
      if (allTeamAMembers is List) {
        for (final m in allTeamAMembers) {
          final uid = m['user_id'] as String?;
          final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
          if (uid != null) {
            allUserIdsInBothTeams.add(uid);
            userRoleInTeamA[uid] = role;
          }
        }
      }
      
      if (allTeamBMembers is List) {
        for (final m in allTeamBMembers) {
          final uid = m['user_id'] as String?;
          final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
          if (uid != null) {
            allUserIdsInBothTeams.add(uid);
            userRoleInTeamB[uid] = role;
          }
        }
      }
      
      // Build initial rosters from attendance records (preserve existing data)
      final teamAPlayers = <Map<String, dynamic>>[];
      final teamBPlayers = <Map<String, dynamic>>[];
      
      // Map attendance status by user_id and team_id
      final Map<String, String> attendanceStatusByUserTeam = {};
      for (final a in attendees) {
        final uid = a['user_id'] as String?;
        final tid = a['team_id'] as String?;
        final st = (a['status'] as String?)?.toLowerCase() ?? 'pending';
        if (uid != null && tid != null) {
          attendanceStatusByUserTeam['$uid-$tid'] = st;
          
          // Get role for this user in this team
          final role = roleByUserTeam['$uid-$tid'] ?? 'member';
          final isAdmin = (role == 'admin' || role == 'captain');
          
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
      }

      // Apply roster assignment rules for ALL users
      for (final userId in allUserIdsInBothTeams) {
        final roleInTeamA = userRoleInTeamA[userId];
        final roleInTeamB = userRoleInTeamB[userId];
        final isAdminOfTeamA = (roleInTeamA == 'admin' || roleInTeamA == 'captain');
        final isAdminOfTeamB = (roleInTeamB == 'admin' || roleInTeamB == 'captain');
        final isMemberOfTeamA = roleInTeamA != null;
        final isMemberOfTeamB = roleInTeamB != null;
        
        // Get attendance status (prefer Team A, then Team B, then 'pending')
        String attendanceStatus = attendanceStatusByUserTeam['$userId-$teamAId'] ?? 
                                  attendanceStatusByUserTeam['$userId-$teamBId'] ?? 
                                  'pending';
        
        // Find existing entry in rosters (if any)
        final existingInTeamA = teamAPlayers.indexWhere((p) => p['user_id'] == userId);
        final existingInTeamB = teamBPlayers.indexWhere((p) => p['user_id'] == userId);
        
        // Rule 1: Admin always stays on the side where they are admin
        if (isAdminOfTeamA) {
          // User is admin of Team A - MUST be in Team A roster
          if (existingInTeamB >= 0) {
            teamBPlayers.removeAt(existingInTeamB);
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Removed user $userId from Team B (admin of Team A)');
            }
          }
          if (existingInTeamA < 0) {
            // Not in Team A roster - add them
            teamAPlayers.add({
              'user_id': userId,
              'name': userNameById[userId] ?? 'Player',
              'status': attendanceStatus,
              'role': roleInTeamA ?? 'member',
              'is_admin': true,
            });
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Added user $userId to Team A (admin of Team A)');
            }
          } else {
            // Update existing entry to ensure admin flag is set
            teamAPlayers[existingInTeamA]['is_admin'] = true;
            teamAPlayers[existingInTeamA]['role'] = roleInTeamA ?? 'member';
          }
        } else if (isAdminOfTeamB) {
          // User is admin of Team B - MUST be in Team B roster
          if (existingInTeamA >= 0) {
            teamAPlayers.removeAt(existingInTeamA);
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Removed user $userId from Team A (admin of Team B)');
            }
          }
          if (existingInTeamB < 0) {
            // Not in Team B roster - add them
            teamBPlayers.add({
              'user_id': userId,
              'name': userNameById[userId] ?? 'Player',
              'status': attendanceStatus,
              'role': roleInTeamB ?? 'member',
              'is_admin': true,
            });
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Added user $userId to Team B (admin of Team B)');
            }
          } else {
            // Update existing entry to ensure admin flag is set
            teamBPlayers[existingInTeamB]['is_admin'] = true;
            teamBPlayers[existingInTeamB]['role'] = roleInTeamB ?? 'member';
          }
        }
        // Rule 2: If user is member of both teams (and not admin of either), prioritize creating team (Team A)
        else if (isMemberOfTeamA && isMemberOfTeamB) {
          // User is member of both teams - put them in Team A (creating team)
          if (existingInTeamB >= 0) {
            teamBPlayers.removeAt(existingInTeamB);
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Removed user $userId from Team B (member of both teams, prioritizing Team A)');
            }
          }
          if (existingInTeamA < 0) {
            // Not in Team A roster - add them
            teamAPlayers.add({
              'user_id': userId,
              'name': userNameById[userId] ?? 'Player',
              'status': attendanceStatus,
              'role': roleInTeamA ?? 'member',
              'is_admin': false,
            });
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Added user $userId to Team A (member of both teams, prioritizing creating team)');
            }
          }
        }
        // Rule 3: If user is only a member of one team, put them in that team's roster
        else if (isMemberOfTeamA && !isMemberOfTeamB) {
          if (existingInTeamB >= 0) {
            teamBPlayers.removeAt(existingInTeamB);
          }
          if (existingInTeamA < 0) {
            teamAPlayers.add({
              'user_id': userId,
              'name': userNameById[userId] ?? 'Player',
              'status': attendanceStatus,
              'role': roleInTeamA ?? 'member',
              'is_admin': false,
            });
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Added user $userId to Team A (only member of Team A)');
            }
          }
        } else if (isMemberOfTeamB && !isMemberOfTeamA) {
          if (existingInTeamA >= 0) {
            teamAPlayers.removeAt(existingInTeamA);
          }
          if (existingInTeamB < 0) {
            teamBPlayers.add({
              'user_id': userId,
              'name': userNameById[userId] ?? 'Player',
              'status': attendanceStatus,
              'role': roleInTeamB ?? 'member',
              'is_admin': false,
            });
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: Added user $userId to Team B (only member of Team B)');
            }
          }
        }
      }
      
      // Get current user's team ID for can_switch_side and my_team_id
      bool canSwitchSide = false;
      final isCurrentUserMemberOfTeamA = userRoleInTeamA.containsKey(myUserId);
      final isCurrentUserMemberOfTeamB = userRoleInTeamB.containsKey(myUserId);
      
      if (isCurrentUserMemberOfTeamA && isCurrentUserMemberOfTeamB) {
        canSwitchSide = true;
      }
      
      // Determine current user's team ID
      var userTeamId = r['user_team_id'] as String?;
      
      // Override based on admin status
      if (userRoleInTeamA[myUserId] == 'admin' || userRoleInTeamA[myUserId] == 'captain') {
        userTeamId = teamAId;
      } else if (userRoleInTeamB[myUserId] == 'admin' || userRoleInTeamB[myUserId] == 'captain') {
        userTeamId = teamBId;
      } else if (isCurrentUserMemberOfTeamA) {
        userTeamId = teamAId;
      } else if (isCurrentUserMemberOfTeamB) {
        userTeamId = teamBId;
      }
      
      // Get user's attendance status
      final userAttendanceStatus = (r['user_attendance_status'] as String?)?.toLowerCase() ?? 
                                  attendanceStatusByUserTeam['$myUserId-$userTeamId'] ?? 
                                  'accepted';
      
      if (kDebugMode) {
        print('[DEBUG] Game $reqId: Final rosters - Team A: ${teamAPlayers.length} players, Team B: ${teamBPlayers.length} players');
        print('[DEBUG] Game $reqId: Current user $myUserId -> userTeamId=$userTeamId');
      }
      
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
    // NEW LOGIC: After acceptance, all Team A admins/members should get pending approval
    // (except if they're admin on the accepting team - they see it under that team)
    // All accepting team members should also get pending approval
    
    // First, check admin status for all matched teams to optimize queries
    final matchedTeamIds = reqs
        .map((r) => r['matched_team_id'] as String?)
        .whereType<String>()
        .toSet();
    
    final Map<String, bool> userAdminStatusByTeamId = {};
    if (matchedTeamIds.isNotEmpty) {
      try {
        final adminChecks = await supa
            .from('team_members')
            .select('team_id, role')
            .eq('user_id', myUserId)
            .inFilter('team_id', matchedTeamIds.toList());
        
        if (adminChecks is List) {
          for (final check in adminChecks) {
            final teamId = check['team_id'] as String?;
            final role = (check['role'] as String?)?.toLowerCase();
            if (teamId != null) {
              userAdminStatusByTeamId[teamId] = role == 'admin' || role == 'captain';
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ERROR] Failed to check admin status for matched teams: $e');
        }
      }
    }
    
    final nonCancelledReqs = <dynamic>[];
    for (final r in reqs) {
      final status = (r['status'] as String?)?.toLowerCase();
      final matchedTeamId = r['matched_team_id'] as String?;
      final creatingTeamId = r['team_id'] as String?;
      
      // Exclude cancelled matches
      if (status == 'cancelled') continue;
      
      // Exclude games awaiting opponent confirmation (matched_team_id is null)
      // These games should only appear in "Awaiting Opponent Confirmation"
      if (matchedTeamId == null) continue;
      
      // Get the user's team ID for this game from attendance record
      final reqId = r['id'] as String?;
      final userTeamId = reqId != null ? myTeamByReqId[reqId] : null;
      
      // Only include if user's team is the creating team OR the matched team
      // This ensures that if Team B accepts, only Team A and Team B members see it
      // Team C members (who haven't accepted) should not see it
      if (userTeamId != null && matchedTeamId != null && creatingTeamId != null) {
        final isUserOnCreatingTeam = userTeamId == creatingTeamId;
        final isUserOnMatchedTeam = userTeamId == matchedTeamId;
        
        // Check if user is admin of the accepting team (matched team)
        final isUserAdminOfAcceptingTeam = userAdminStatusByTeamId[matchedTeamId] ?? false;
        
        // Include if:
        // 1. User is on creating team (Team A) - all members/admins should see it
        // 2. User is on matched team (Team Y) - all members should see it
        // EXCEPT: If user is admin of accepting team AND also member of creating team,
        // they should see it under the accepting team (update myTeamByReqId)
        if (!isUserOnCreatingTeam && !isUserOnMatchedTeam) {
          if (kDebugMode) {
            print('[DEBUG] Filtering out game $reqId: userTeamId=$userTeamId, creatingTeamId=$creatingTeamId, matchedTeamId=$matchedTeamId');
          }
          continue; // User's team is neither creating team nor matched team
        }
        
        // Additional check: If user is admin of accepting team and also member of creating team,
        // they should see it under the accepting team (not the creating team)
        if (isUserAdminOfAcceptingTeam && isUserOnCreatingTeam) {
          if (kDebugMode) {
            print('[DEBUG] User is admin of accepting team ($matchedTeamId) and member of creating team ($creatingTeamId) - showing under accepting team');
          }
          // Update userTeamId to the accepting team for this game
          // This ensures they see it under the accepting team
          if (reqId != null) {
            myTeamByReqId[reqId] = matchedTeamId;
          }
        }
      }
      
      nonCancelledReqs.add(r);
    }

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

    // 4) Get invites for all games to determine if they're open challenges
    final allRequestIds = nonCancelledReqs
        .map((r) => r['id'] as String?)
        .where((id) => id != null)
        .cast<String>()
        .toList();
    
    final Map<String, bool> isOpenChallengeByReqId = {};
    if (allRequestIds.isNotEmpty) {
      final invites = await supa
          .from('instant_request_invites')
          .select('request_id, status')
          .inFilter('request_id', allRequestIds);
      
      if (invites is List) {
        final invitesByReqId = <String, List<dynamic>>{};
        for (final inv in invites) {
          final reqId = inv['request_id'] as String?;
          if (reqId != null) {
            invitesByReqId.putIfAbsent(reqId, () => []).add(inv);
          }
        }
        
        // A game is an open challenge if it has no invites at all
        for (final reqId in allRequestIds) {
          final gameInvites = invitesByReqId[reqId] ?? [];
          isOpenChallengeByReqId[reqId] = gameInvites.isEmpty;
        }
      } else {
        // If query fails, assume all are open challenges
        for (final reqId in allRequestIds) {
          isOpenChallengeByReqId[reqId] = true;
        }
      }
    }

    // 5) Build rows
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
      final isOpenChallenge = isOpenChallengeByReqId[reqId] ?? true;

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
        'is_open_challenge': isOpenChallenge,
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

    final Map<String, String> userNameById = {};
    if (allUserIds.isNotEmpty) {
      try {
        // Use RPC function to get display names (bypasses RLS and includes email fallback)
        final displayNamesResult = await supa.rpc(
          'get_user_display_names',
          params: {'p_user_ids': allUserIds.toList()},
        );
        
        if (displayNamesResult is List) {
          for (final u in displayNamesResult) {
            final id = u['user_id'] as String?;
            final displayName = u['display_name'] as String?;
            if (id != null && displayName != null) {
              userNameById[id] = displayName;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DEBUG] Failed to fetch user display names via RPC: $e');
        }
        // Fallback to direct query (will only return current user due to RLS)
        final users = await supa
            .from('users')
            .select('id, full_name')
            .inFilter('id', allUserIds.toList());

    if (users is List) {
      for (final u in users) {
        final id = u['id'] as String?;
        if (id != null) {
          userNameById[id] = (u['full_name'] as String?) ?? 'Player';
            }
          }
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

    // Define variables outside try block so we can use them in catch block
    final result = <Map<String, dynamic>>[];
    List<dynamic> allGamesFinal = [];
    final teamNames = <String, String>{};
    final userTeamIdByGameId = <String, String>{};

    try {
      // First, get all games where user has an attendance record (this ensures RLS allows access)
      // AND where matched_team_id is null (awaiting opponent confirmation)
      final userAttendance = await supa
          .from('team_match_attendance')
          .select('request_id, team_id')
          .eq('user_id', userId);
      
      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Raw attendance query returned ${userAttendance is List ? userAttendance.length : 0} records');
        if (userAttendance is List) {
          for (final att in userAttendance) {
            print('[DEBUG]   - request_id: ${att['request_id']}, team_id: ${att['team_id']}');
          }
        }
      }
      
      final Set<String> gameIdsWithAttendance = {};
      // userTeamIdByGameId is already defined outside try block
      final Map<String, List<String>> allUserTeamsByGameId = {}; // Map game ID to all user's team IDs in that game
      
      if (userAttendance is List) {
        // First pass: collect all attendance records
        for (final att in userAttendance) {
          final reqId = att['request_id'] as String?;
          final teamId = att['team_id'] as String?;
          if (reqId != null) {
            gameIdsWithAttendance.add(reqId);
            if (teamId != null) {
              allUserTeamsByGameId.putIfAbsent(reqId, () => []).add(teamId);
            }
          }
        }
        
        if (kDebugMode) {
          print('[DEBUG] Collected attendance: gameIdsWithAttendance=$gameIdsWithAttendance, allUserTeamsByGameId=$allUserTeamsByGameId');
        }
        
        // Second pass: prioritize creating team over invited teams
        // Get creating team IDs for all games
        if (gameIdsWithAttendance.isNotEmpty) {
          final gameRows = await supa
              .from('instant_match_requests')
              .select('id, team_id')
              .inFilter('id', gameIdsWithAttendance.toList());
          
          final Map<String, String> creatingTeamIdByGameId = {};
          if (gameRows is List) {
            for (final game in gameRows) {
              final gameId = game['id'] as String?;
              final creatingTeamId = game['team_id'] as String?;
              if (gameId != null && creatingTeamId != null) {
                creatingTeamIdByGameId[gameId] = creatingTeamId;
              }
            }
          }
          
          // Now determine user's team for each game, prioritizing creating team
          for (final reqId in gameIdsWithAttendance) {
            final userTeamsForGame = allUserTeamsByGameId[reqId] ?? [];
            final creatingTeamId = creatingTeamIdByGameId[reqId];
            
            if (kDebugMode) {
              print('[DEBUG] Game $reqId: userTeamsForGame=$userTeamsForGame, creatingTeamId=$creatingTeamId');
            }
            
            // Priority: If user is a member of the creating team, use that
            // Otherwise, use the first team found (for invited teams)
            if (creatingTeamId != null && userTeamsForGame.contains(creatingTeamId)) {
              userTeamIdByGameId[reqId] = creatingTeamId;
              if (kDebugMode) {
                print('[DEBUG] ✓ Game $reqId: User is on creating team $creatingTeamId (prioritized over ${userTeamsForGame.where((t) => t != creatingTeamId).join(', ')})');
              }
            } else if (userTeamsForGame.isNotEmpty) {
              // User is only on invited teams according to attendance records
              // BUT: If creatingTeamId exists, verify if user is actually a member of creating team
              // This handles the case where attendance record might be missing due to RLS or timing
              if (creatingTeamId != null && !userTeamsForGame.contains(creatingTeamId)) {
                // Double-check: verify if user is actually a member of the creating team
                try {
                  final isMemberOfCreatingTeam = await supa
                      .from('team_members')
                      .select('user_id')
                      .eq('team_id', creatingTeamId)
                      .eq('user_id', userId)
                      .maybeSingle();
                  
                  if (isMemberOfCreatingTeam != null) {
                    // User IS a member of creating team, but attendance record is missing
                    // Use creating team ID anyway (prioritize creating team)
                    userTeamIdByGameId[reqId] = creatingTeamId;
                    if (kDebugMode) {
                      print('[WARNING] Game $reqId: User IS a member of creating team $creatingTeamId, but attendance record is missing!');
                      print('[WARNING] Using creating team ID anyway (prioritizing creating team over invited teams)');
                    }
                  } else {
                    // User is NOT a member of creating team, use first invited team
                    userTeamIdByGameId[reqId] = userTeamsForGame.first;
                    if (kDebugMode) {
                      print('[WARNING] Game $reqId: User is NOT a member of creating team $creatingTeamId, using first invited team: ${userTeamsForGame.first}');
                    }
                  }
                } catch (e) {
                  // If check fails, fall back to first invited team
                  userTeamIdByGameId[reqId] = userTeamsForGame.first;
                  if (kDebugMode) {
                    print('[ERROR] Failed to verify team membership for game $reqId: $e');
                    print('[DEBUG] Using first invited team: ${userTeamsForGame.first}');
                  }
                }
              } else {
                userTeamIdByGameId[reqId] = userTeamsForGame.first;
                if (kDebugMode) {
                  print('[DEBUG] Game $reqId: User is on invited team(s) ${userTeamsForGame.join(', ')}, using first: ${userTeamsForGame.first}');
                }
              }
            } else if (kDebugMode) {
              print('[WARNING] Game $reqId: No user teams found for this game');
            }
          }
        }
      }
      
      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Found ${gameIdsWithAttendance.length} games with attendance');
        print('[DEBUG] User team mapping: $userTeamIdByGameId');
      }
      
      // ALSO get games created by user's teams (even if no attendance record exists yet)
      // This ensures newly created games (public or invite-specific) appear immediately
      // Use RPC function to bypass RLS - get_all_matches_for_user returns games created by user
      List<dynamic> gamesCreatedByUserTeams = [];
      try {
        // Get all games for user via RPC (includes games created by user)
        final allUserGamesResult = await supa.rpc(
          'get_all_matches_for_user',
          params: {'p_user_id': userId},
        );
        
        if (allUserGamesResult is List) {
          // Filter to only games awaiting opponent confirmation (created by user's teams)
          gamesCreatedByUserTeams = allUserGamesResult.where((game) {
            final mode = (game['mode'] as String?)?.toLowerCase();
            final status = (game['status'] as String?)?.toLowerCase();
            final matchedTeamId = game['matched_team_id'];
            final teamId = game['team_id'] as String?;
            
            return mode == 'team_vs_team' &&
                   status != 'cancelled' &&
                   (status == 'open' || status == 'pending') &&
                   matchedTeamId == null &&
                   teamId != null &&
                   userTeamIds.contains(teamId);
          }).toList();
          
          if (kDebugMode) {
            print('[DEBUG] Found ${gamesCreatedByUserTeams.length} games created by user\'s teams via get_all_matches_for_user RPC');
            for (final game in gamesCreatedByUserTeams) {
              print('[DEBUG]   - Game ${game['id']}: status=${game['status']}, team_id=${game['team_id']}');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ERROR] Failed to get games via get_all_matches_for_user RPC: $e');
        }
      }
      
      final Set<String> allGameIds = gameIdsWithAttendance.toSet();
      if (gamesCreatedByUserTeams is List) {
        for (final game in gamesCreatedByUserTeams) {
          final gameId = game['id'] as String?;
          final teamId = game['team_id'] as String?;
          if (gameId != null && teamId != null) {
            allGameIds.add(gameId);
            // If user doesn't have attendance record for this game, add it to the mapping
            if (!gameIdsWithAttendance.contains(gameId)) {
              userTeamIdByGameId[gameId] = teamId;
              if (kDebugMode) {
                print('[DEBUG] Added game $gameId created by user\'s team $teamId (no attendance record yet)');
              }
            }
          }
        }
      }
      
      if (allGameIds.isEmpty) {
        if (kDebugMode) {
          print('[DEBUG] getAwaitingOpponentConfirmationGames: No games found (no attendance records and no games created by user\'s teams)');
        }
        return [];
      }
      
      // Get games with attendance records via RPC (for games where user has attendance)
      final gamesWithAttendanceIds = gameIdsWithAttendance.toList();
      List<dynamic> allGamesRaw = [];
      
      if (gamesWithAttendanceIds.isNotEmpty) {
        final allGamesResult = await supa.rpc(
          'get_match_requests_for_attendance',
          params: {
            'p_user_id': userId,
            'p_request_ids': gamesWithAttendanceIds,
          },
        );
        allGamesRaw = allGamesResult is List ? allGamesResult : <dynamic>[];
      }
      
      // Also add games created by user's teams from RPC results (even without attendance records)
      // These games are already in the correct format from get_all_matches_for_user RPC
      final gamesCreatedByTeamsIds = allGameIds
          .where((id) => !gameIdsWithAttendance.contains(id))
          .toList();
      
      if (gamesCreatedByTeamsIds.isNotEmpty && gamesCreatedByUserTeams.isNotEmpty) {
        // Add games from RPC results that match the IDs we need
        for (final game in gamesCreatedByUserTeams) {
          final gameId = game['id'] as String?;
          if (gameId != null && gamesCreatedByTeamsIds.contains(gameId)) {
            // Convert to same format as RPC function returns
            allGamesRaw.add({
              'id': game['id'],
              'sport': game['sport'],
              'mode': game['mode'],
              'zip_code': game['zip_code'],
              'team_id': game['team_id'],
              'matched_team_id': game['matched_team_id'],
              'start_time_1': game['start_time_1'],
              'start_time_2': game['start_time_2'],
              'venue': game['venue'],
              'status': game['status'],
              'expected_players_per_team': game['expected_players_per_team'],
              'created_by': game['created_by'],
              'creator_id': game['creator_id'],
              'show_team_a_roster': game['show_team_a_roster'],
              'show_team_b_roster': game['show_team_b_roster'],
            });
          }
        }
        if (kDebugMode) {
          print('[DEBUG] Added ${gamesCreatedByUserTeams.length} games created by user\'s teams from RPC results (no attendance records)');
        }
      }
      
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
      
      // RPC function already returns: details, created_by, creator_id
      // We only need to fetch: visibility, is_public (if not already in RPC result)
      // Try to get these from invites table or use defaults
      final gameIdsForAdditionalFields = allGames.map<String>((g) => g['id'] as String).toList();
      
      Map<String, Map<String, dynamic>> additionalByGameId = {};
      
      // Try to get visibility and is_public from invites table (safer than direct table query)
      try {
        // For invite-specific games, visibility is 'invited' and is_public is false
        // For public games, visibility is 'public' and is_public is true
        // We can infer this from whether there are specific team invites or not
        // Use RPC function or direct query with explicit column selection to avoid RLS issues
        final inviteRows = await supa
            .from('instant_request_invites')
            .select('request_id')
            .inFilter('request_id', gameIdsForAdditionalFields.isEmpty ? ['00000000-0000-0000-0000-000000000000'] : gameIdsForAdditionalFields);
        
        final Set<String> gamesWithInvites = {};
        if (inviteRows is List) {
          for (final inv in inviteRows) {
            final reqId = inv['request_id'] as String?;
            if (reqId != null) {
              gamesWithInvites.add(reqId);
            }
          }
        }
        
        // Set defaults based on whether game has invites
        for (final gameId in gameIdsForAdditionalFields) {
          if (gamesWithInvites.contains(gameId)) {
            // Has specific invites = invite-specific game
            additionalByGameId[gameId] = {
              'visibility': 'invited',
              'is_public': false,
            };
          } else {
            // No specific invites = public/open challenge game
            additionalByGameId[gameId] = {
              'visibility': 'public',
              'is_public': true,
            };
          }
        }
        
        if (kDebugMode) {
          print('[DEBUG] Set visibility/is_public for ${additionalByGameId.length} games based on invites');
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ERROR] Failed to determine visibility from invites: $e');
          print('[DEBUG] Using defaults: visibility=invited, is_public=false');
        }
        // Default to invite-specific if we can't determine
        for (final gameId in gameIdsForAdditionalFields) {
          additionalByGameId[gameId] = {
            'visibility': 'invited',
            'is_public': false,
          };
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
      
      allGamesFinal = enrichedGames;
      
      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Found ${allGamesFinal.length} games via RPC');
      }
      
      // Get game IDs for invite lookup
      final gameIds = allGamesFinal.map<String>((g) => g['id'] as String).toList();
      
      // Get all invites for these games (including all statuses to determine if it's an open challenge)
      // Wrap in try-catch to handle RLS policy errors
      final Map<String, List<Map<String, dynamic>>> invitesByRequestId = {};
      try {
        final invites = await supa
            .from('instant_request_invites')
            .select('request_id, target_team_id, status')
            .inFilter('request_id', gameIds.isEmpty ? ['00000000-0000-0000-0000-000000000000'] : gameIds);
        
        // Group invites by request_id
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
      } catch (e) {
        if (kDebugMode) {
          print('[ERROR] Failed to fetch invites (RLS or column error): $e');
          print('[DEBUG] Continuing without invite data - will use defaults');
        }
        // Continue without invite data - we'll use defaults
      }
      
      // Filter games: Include all games awaiting opponent confirmation
      // For newly created games, they should appear immediately even if invites query failed
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
          continue; // Skip cancelled games
        }
        
        final gameInvites = invitesByRequestId[reqId] ?? [];
        final userTeamIdForThisGame = userTeamIdByGameId[reqId];
        final creatingTeamId = game['team_id'] as String?;
        final isUserOnCreatingTeam = creatingTeamId != null && userTeamIdForThisGame == creatingTeamId;
        
        // If user is on creating team, always include (they created it or are part of creating team)
        if (isUserOnCreatingTeam) {
          filteredGames.add(game);
          if (kDebugMode) {
            print('[DEBUG] Including game $reqId: User is on creating team');
          }
          continue;
        }
        
        // If user is on invited team, check if that team denied
        if (userTeamIdForThisGame != null && gameInvites.isNotEmpty) {
          final userTeamDenied = gameInvites.any((inv) {
            final targetTeamId = inv['target_team_id'] as String?;
            final invStatus = (inv['status'] as String?)?.toLowerCase();
            return targetTeamId == userTeamIdForThisGame && invStatus == 'denied';
          });
          
          if (userTeamDenied) {
            if (kDebugMode) {
              print('[DEBUG] Filtering out game where user team denied: $reqId');
            }
            continue; // Skip games where the user's team has denied
          }
        }
        
        // Check if any invite is still pending or it's an open challenge
        final hasPendingInvite = gameInvites.any((inv) => 
          (inv['status'] as String?)?.toLowerCase() == 'pending'
        );
        final isOpenChallenge = gameInvites.isEmpty;
        
        // Include if open challenge or has pending invites
        if (isOpenChallenge || hasPendingInvite) {
          filteredGames.add(game);
        }
      }
      
      if (kDebugMode) {
        print('[DEBUG] getAwaitingOpponentConfirmationGames: Filtered ${filteredGames.length} games from ${allGamesFinal.length} total games');
        if (filteredGames.isEmpty && allGamesFinal.isNotEmpty) {
          print('[WARNING] All games were filtered out - this might indicate an issue');
        }
      }
      
      // IMPORTANT: If we have games but filteredGames is empty (due to invite query failure),
      // include all games anyway - they're newly created and should appear
      final finalGames = filteredGames.isNotEmpty ? filteredGames : allGamesFinal;
      
      if (kDebugMode && filteredGames.isEmpty && allGamesFinal.isNotEmpty) {
        print('[WARNING] Using allGamesFinal (${allGamesFinal.length} games) because filteredGames is empty - invites query may have failed');
      }

      // Get team names - include all teams from games, invites, AND user's teams from attendance records
      final allTeamIds = <String>{};
      for (final g in finalGames) {
        final teamId = g['team_id'] as String?;
        if (teamId != null) allTeamIds.add(teamId);
      }
      // Add team IDs from invites (using invitesByRequestId which is available outside try-catch)
      for (final invitesList in invitesByRequestId.values) {
        for (final inv in invitesList) {
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
      // NEW LOGIC: Determine team assignments based on admin roles and team memberships
      for (final game in finalGames) {
        try {
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
          
          // Get ALL invited team IDs from invites
          final allInvitedTeamIds = gameInvites
              .map((inv) => inv['target_team_id'] as String?)
              .whereType<String>()
              .toSet();
          
          // Check if user is admin of any invited team
          String? userAdminTeamId;
          if (allInvitedTeamIds.isNotEmpty) {
            try {
              final adminCheck = await supa
                  .from('team_members')
                  .select('team_id')
                  .eq('user_id', userId)
                  .inFilter('team_id', allInvitedTeamIds.toList())
                  .inFilter('role', ['admin', 'captain']);
              
              if (adminCheck is List && adminCheck.isNotEmpty) {
                // User is admin of at least one invited team - use the first one
                userAdminTeamId = adminCheck.first['team_id'] as String?;
                if (kDebugMode) {
                  print('[DEBUG] User $userId is admin of invited team: $userAdminTeamId');
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('[ERROR] Failed to check admin status: $e');
              }
            }
          }
          
          // Check if user is member of creating team
          bool isUserMemberOfCreatingTeam = false;
          if (creatingTeamId != null) {
            try {
              final memberCheck = await supa
                  .from('team_members')
                  .select('user_id')
                  .eq('team_id', creatingTeamId)
                  .eq('user_id', userId)
                  .maybeSingle();
              isUserMemberOfCreatingTeam = memberCheck != null;
            } catch (e) {
              if (kDebugMode) {
                print('[ERROR] Failed to check creating team membership: $e');
              }
            }
          }
          
          // Determine user's team assignment based on new rules:
          // 1. If user is admin of an invited team → show that admin team as "Your Team"
          // 2. If user is member of creating team (and NOT admin of any invited team) → show creating team as "Your Team"
          // 3. If user is member of invited team (and not admin, and not member of creating team) → show their invited team as "Your Team"
          // 4. If user is member of both creating team and invited team (and not admin of invited team) → show creating team as "Your Team"
          
          String myTeamName;
          List<String> otherTeamNames;
          String? myTeamId;
          
          if (userAdminTeamId != null) {
            // Rule 1: User is admin of an invited team → show that team as "Your Team", created team as "Opponent"
            myTeamId = userAdminTeamId;
            myTeamName = teamNames[myTeamId] ?? '';
            if (myTeamName.isEmpty) {
              try {
                final teamRow = await supa
                    .from('teams')
                    .select('name')
                    .eq('id', myTeamId)
                    .maybeSingle();
                if (teamRow != null) {
                  myTeamName = (teamRow['name'] as String?) ?? 'My Team';
                  teamNames[myTeamId] = myTeamName;
                } else {
                  myTeamName = 'My Team';
                }
              } catch (e) {
                myTeamName = 'My Team';
              }
            }
            // Opponent is the creating team
            otherTeamNames = [creatingTeamName];
            if (kDebugMode) {
              print('[DEBUG] User is admin of invited team $myTeamId: showing as "Your Team", created team as opponent');
            }
          } else if (isUserMemberOfCreatingTeam) {
            // Rule 2 & 4: User is member of creating team (and not admin of any invited team)
            // Show creating team as "Your Team", all invited teams as "Opponent"
            myTeamId = creatingTeamId;
            myTeamName = creatingTeamName;
            
            // Build opponent team names from ALL invites
            final opponentTeamIds = allInvitedTeamIds.toList();
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
                }
              } catch (e) {
                if (kDebugMode) {
                  print('[ERROR] Failed to fetch missing team names: $e');
                }
              }
            }
            
            otherTeamNames = opponentTeamIds
                .map((tid) => teamNames[tid] ?? 'Unknown Team')
                .where((name) => name.isNotEmpty && name != 'Unknown Team')
                .toList();
            
            if (kDebugMode) {
              print('[DEBUG] User is member of creating team: showing as "Your Team", invited teams as opponents: $otherTeamNames');
            }
          } else if (userTeamIdForThisGame != null && allInvitedTeamIds.contains(userTeamIdForThisGame)) {
            // Rule 3: User is member of invited team (and not admin, and not member of creating team)
            // Show their invited team as "Your Team", created team as "Opponent"
            myTeamId = userTeamIdForThisGame;
            myTeamName = teamNames[myTeamId] ?? '';
            if (myTeamName.isEmpty) {
              try {
                final teamRow = await supa
                    .from('teams')
                    .select('name')
                    .eq('id', myTeamId)
                    .maybeSingle();
                if (teamRow != null) {
                  myTeamName = (teamRow['name'] as String?) ?? 'My Team';
                  teamNames[myTeamId] = myTeamName;
                } else {
                  myTeamName = 'My Team';
                }
              } catch (e) {
                myTeamName = 'My Team';
              }
            }
            // Opponent is the creating team
            otherTeamNames = [creatingTeamName];
            if (kDebugMode) {
              print('[DEBUG] User is member of invited team (not admin, not member of creating team): showing as "Your Team", created team as opponent');
            }
          } else {
            // Fallback: Use existing logic
            final isUserOnCreatingTeam = creatingTeamId != null && userTeamIdForThisGame == creatingTeamId;
            if (isUserOnCreatingTeam) {
              myTeamName = creatingTeamName;
              myTeamId = creatingTeamId;
              otherTeamNames = allInvitedTeamIds
                  .map((tid) => teamNames[tid] ?? 'Unknown Team')
                  .where((name) => name.isNotEmpty && name != 'Unknown Team')
                  .toList();
            } else if (userTeamIdForThisGame != null) {
              myTeamId = userTeamIdForThisGame;
              myTeamName = teamNames[myTeamId] ?? 'My Team';
              otherTeamNames = [creatingTeamName];
            } else {
              myTeamName = creatingTeamName;
              myTeamId = creatingTeamId;
              otherTeamNames = [];
            }
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
            print('[DEBUG] Game $reqId: creatingTeamId=$creatingTeamId, userTeamIdForThisGame=$userTeamIdForThisGame');
            print('[DEBUG] Game $reqId: myTeamName=$myTeamName, myTeamId=$myTeamId, otherTeamNames=$otherTeamNames');
            print('[DEBUG] Game $reqId: allInvitedTeamIds=${allInvitedTeamIds.toList()}');
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
            'creating_team_name': creatingTeamName, // The team that created the game
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
        } // End of if (hasPendingInvite || isOpenChallenge)
        } catch (e) {
          // If processing one game fails, log and continue with next game
          if (kDebugMode) {
            print('[ERROR] Failed to process game ${game['id']}: $e');
          }
          // Continue to next game
        }
      }

      return result;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[ERROR] getAwaitingOpponentConfirmationGames: $e');
        print('[ERROR] Stack trace: $stackTrace');
      }
      // If we have partial results, return them instead of empty list
      if (result.isNotEmpty) {
        if (kDebugMode) {
          print('[WARNING] Returning ${result.length} partial results despite error');
        }
        return result;
      }
      // If we have games but no results built yet, try to build basic results
      // This handles the case where error happens before result building loop
      try {
        if (allGamesFinal.isNotEmpty) {
          if (kDebugMode) {
            print('[WARNING] Error occurred but we have ${allGamesFinal.length} games - building basic results');
          }
          
          // Fetch team names if not already fetched
          final teamIdsToFetch = <String>{};
          for (final game in allGamesFinal) {
            final creatingTeamId = game['team_id'] as String?;
            final userTeamIdForThisGame = userTeamIdByGameId[game['id'] as String] ?? creatingTeamId;
            if (creatingTeamId != null) teamIdsToFetch.add(creatingTeamId);
            if (userTeamIdForThisGame != null) teamIdsToFetch.add(userTeamIdForThisGame);
          }
          
          // Fetch missing team names
          final missingTeamIds = teamIdsToFetch.where((tid) => !teamNames.containsKey(tid) || teamNames[tid]?.isEmpty == true).toList();
          if (missingTeamIds.isNotEmpty) {
            try {
              final teamRows = await supa
                  .from('teams')
                  .select('id, name')
                  .inFilter('id', missingTeamIds);
              if (teamRows is List) {
                for (final t in teamRows) {
                  final id = t['id'] as String?;
                  if (id != null) {
                    teamNames[id] = (t['name'] as String?) ?? '';
                  }
                }
              }
            } catch (e2) {
              if (kDebugMode) {
                print('[ERROR] Failed to fetch team names in catch block: $e2');
              }
            }
          }
          
          // Build basic results without invite data
          for (final game in allGamesFinal) {
            final reqId = game['id'] as String;
            final creatingTeamId = game['team_id'] as String?;
            final userTeamIdForThisGame = userTeamIdByGameId[reqId] ?? creatingTeamId;
            final creatingTeamName = teamNames[creatingTeamId] ?? 'Unknown Team';
            final myTeamName = teamNames[userTeamIdForThisGame] ?? 'My Team';
            
            // Determine if it's an open challenge (no invites = open challenge)
            // Since invites query failed, assume it's an open challenge for newly created games
            final isOpenChallenge = true; // Default to open challenge if we can't determine
            
            result.add({
              'request_id': reqId,
              'sport': game['sport'],
              'team_id': creatingTeamId,
              'my_team_id': userTeamIdForThisGame,
              'team_name': myTeamName,
              'creating_team_name': creatingTeamName,
              'opponent_teams': [],
              'is_open_challenge': isOpenChallenge,
              'start_time': null,
              'end_time': null,
              'venue': game['venue'],
              'details': game['details'],
              'creator_id': game['created_by'] ?? game['creator_id'],
              'creator_name': 'Unknown',
              'status': game['status'],
              'visibility': game['visibility'] ?? 'invited',
              'is_public': game['is_public'] ?? false,
            });
          }
          if (kDebugMode) {
            print('[WARNING] Built ${result.length} basic results from ${allGamesFinal.length} games');
          }
          return result;
        }
      } catch (e2) {
        if (kDebugMode) {
          print('[ERROR] Failed to build basic results: $e2');
        }
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
