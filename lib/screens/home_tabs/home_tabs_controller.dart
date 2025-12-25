import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/home_repository.dart';
import '../../services/location_service.dart';

class HomeTabsController extends ChangeNotifier {
  final HomeRepository repo;
  final SupabaseClient supa;

  HomeTabsController(this.supa) : repo = HomeRepository(supa);

  int selectedIndex = 0;
  String? currentUserId;
  String? baseZip;
  String? userName;
  String? userLocation;
  String? userPhotoUrl;
  List<String> userSports = [];

  List<Map<String, dynamic>> adminTeams = [];
  List<Map<String, dynamic>> teamVsTeamInvites = [];
  List<Map<String, dynamic>> confirmedTeamMatches = [];
  List<Map<String, dynamic>> allMyMatches = []; // All matches including cancelled
  List<Map<String, dynamic>> allMyIndividualMatches = []; // All individual games
  List<Map<String, dynamic>> discoveryPickupMatches = [];
  List<Map<String, dynamic>> pendingTeamMatchesForAdmin = [];
  List<Map<String, dynamic>> friendsOnlyIndividualGames = [];
  List<Map<String, dynamic>> pendingAvailabilityTeamMatches = [];
  List<Map<String, dynamic>> pendingIndividualGames = []; // Individual games with pending requests
  List<Map<String, dynamic>> awaitingOpponentConfirmationGames = []; // Team games awaiting opponent acceptance
  List<Map<String, dynamic>> publicPendingGames = []; // Public games matching notification preferences
  bool loadingConfirmedMatches = false;
  bool loadingAllMatches = false;
  bool loadingIndividualMatches = false;
  bool loadingDiscoveryMatches = false;
  bool loadingAwaitingOpponentGames = false;
  bool myGamesTabLoadInitiated = false; // Prevent infinite loops

  String? lastError;

  // caching
  final Set<String> _adminTeamIds = {};
  final Set<String> _hiddenRequestIds = {};

  RealtimeChannel? attendanceChannel;

  Future<void> init() async {
    currentUserId = supa.auth.currentUser?.id;
    if (currentUserId == null) return;

    lastError = null;
    notifyListeners();

    try {
      await loadUserBasics();
      await loadAdminTeamsAndInvites();
      await loadHiddenGames();
      await loadConfirmedTeamMatches();
      await loadDiscoveryPickupMatches();
      await loadPendingGamesForAdmin();
      await loadFriendsOnlyIndividualGames();
      await loadMyPendingAvailabilityMatches();
      await loadPendingIndividualGames();
      await loadAwaitingOpponentConfirmationGames();
      await loadPublicPendingGames();
      setupRealtimeAttendance();
    } catch (e) {
      lastError = 'Init failed: $e';
      notifyListeners();
    }
  }

  void disposeRealtime() {
    if (attendanceChannel != null) {
      supa.removeChannel(attendanceChannel!);
      attendanceChannel = null;
    }
  }

  void setupRealtimeAttendance() {
    if (attendanceChannel != null) return;

    attendanceChannel = supa
        .channel('public:team_match_attendance')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'team_match_attendance',
          callback: (_) async {
            await loadConfirmedTeamMatches();
            await loadMyPendingAvailabilityMatches();
            // Don't reload awaiting games here - they're only affected by invite acceptance, not attendance changes
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> loadUserBasics() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      // Load critical user data first (name, sports, profile ZIP for backward compatibility)
      final profileZip = await repo.getBaseZip(uid);
      baseZip = profileZip; // Keep for backward compatibility
      
      userSports = await repo.getUserSports(uid);
      final nameAndLocation = await repo.getUserNameAndLocation(uid);
      userName = nameAndLocation['name'];
      userLocation = nameAndLocation['location'];
      userPhotoUrl = nameAndLocation['photo_url'];
      notifyListeners();
      
      // Note: We now use GPS coordinates instead of ZIP codes for location
      // baseZip is kept only for backward compatibility with existing code
      
    } catch (e) {
      lastError = 'loadUserBasics failed: $e';
      notifyListeners();
    }
  }

  Future<void> loadAdminTeamsAndInvites() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      adminTeams = await repo.getAdminTeams(uid);
      _adminTeamIds
        ..clear()
        ..addAll(adminTeams.map((t) => t['id'] as String));

      final adminTeamIdsList = adminTeams.map((t) => t['id'] as String).toList();
      teamVsTeamInvites = await repo.getPendingInvitesForTeams(adminTeamIdsList);

      // Also load pending games where user can approve as admin
      await loadPendingGamesForAdmin();

      notifyListeners();
    } catch (e) {
      lastError = 'loadAdminTeamsAndInvites failed: $e';
      notifyListeners();
    }
  }

  /// Get all teams user is member of but NOT admin
  Future<List<Map<String, dynamic>>> getNonAdminTeams() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      return await repo.getNonAdminTeams(uid);
    } catch (e) {
      lastError = 'getNonAdminTeams failed: $e';
      notifyListeners();
      return [];
    }
  }

  Future<void> loadHiddenGames() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final ids = await repo.getHiddenRequestIds(uid);
      _hiddenRequestIds
        ..clear()
        ..addAll(ids);
    } catch (e) {
      lastError = 'loadHiddenGames failed: $e';
      notifyListeners();
    }
  }

  bool isHidden(String requestId) => _hiddenRequestIds.contains(requestId);
  
  Set<String> get hiddenRequestIds => _hiddenRequestIds;

  /// ✅ NEW: Hide from My Games (per-user)
  Future<void> hideGame(String requestId) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await repo.hideGameForUser(userId: uid, requestId: requestId);
      _hiddenRequestIds.add(requestId);

      // remove immediately from list
      confirmedTeamMatches.removeWhere((m) => m['request_id'] == requestId);
      notifyListeners();
    } catch (e) {
      lastError = 'hideGame failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Unhide a game (remove from hidden list)
  Future<void> unhideGame(String requestId) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await repo.unhideGameForUser(userId: uid, requestId: requestId);
      _hiddenRequestIds.remove(requestId);

      // Reload all matches to refresh the lists
      await loadAllMyMatches();
      notifyListeners();
    } catch (e) {
      lastError = 'unhideGame failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loadConfirmedTeamMatches() async {
    final uid = currentUserId;
    if (uid == null) return;

    loadingConfirmedMatches = true;
    lastError = null;
    notifyListeners();

    try {
      await loadHiddenGames();

      final raw = await repo.loadMyAcceptedTeamMatches(uid);

      confirmedTeamMatches = raw
          .where((m) => !_hiddenRequestIds.contains(m['request_id'] as String))
          .toList();
    } catch (e) {
      lastError = 'loadConfirmedTeamMatches failed: $e';
    } finally {
      loadingConfirmedMatches = false;
      notifyListeners();
    }
  }

  Future<void> loadAllMyMatches() async {
    final uid = currentUserId;
    if (uid == null) return;
    
    // Prevent multiple simultaneous loads
    if (loadingAllMatches) return;

    loadingAllMatches = true;
    lastError = null;
    notifyListeners();

    try {
      await loadHiddenGames();

      final raw = await repo.loadAllMatchesForUser(uid);

      if (kDebugMode) {
        print('[DEBUG] loadAllMyMatches: Loaded ${raw.length} matches');
      }

      // Store all matches (including cancelled and hidden)
      allMyMatches = raw;
      
      // Also update confirmedTeamMatches for backward compatibility
      confirmedTeamMatches = raw
          .where((m) => 
              !_hiddenRequestIds.contains(m['request_id'] as String) &&
              (m['status'] as String?)?.toLowerCase() != 'cancelled'
          )
          .toList();
      
      if (kDebugMode) {
        print('[DEBUG] loadAllMyMatches: Filtered to ${confirmedTeamMatches.length} confirmed matches');
      }
    } catch (e) {
      lastError = 'loadAllMyMatches failed: $e';
      if (kDebugMode) {
        print('[DEBUG] loadAllMyMatches ERROR: $e');
      }
    } finally {
      loadingAllMatches = false;
      notifyListeners();
    }
  }

  Future<void> loadAllMyIndividualMatches() async {
    final uid = currentUserId;
    if (uid == null) return;
    
    // Prevent multiple simultaneous loads
    if (loadingIndividualMatches) return;

    loadingIndividualMatches = true;
    lastError = null;
    notifyListeners();

    try {
      final supa = Supabase.instance.client;

      // Get all individual games where user has attendance (accepted, declined, or pending)
      final attendanceRows = await supa
          .from('individual_game_attendance')
          .select('request_id, status, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      if (kDebugMode) {
        print('[DEBUG] loadAllMyIndividualMatches: Found ${attendanceRows is List ? attendanceRows.length : 0} attendance records');
      }

      // Also get games created by the user (even if no attendance record exists)
      final createdGames = await supa
          .from('instant_match_requests')
          .select('id')
          .eq('created_by', uid)
          .neq('mode', 'team_vs_team')
          .neq('status', 'cancelled');

      final Set<String> allRequestIds = {};
      
      if (attendanceRows is List) {
        for (final row in attendanceRows) {
          final reqId = row['request_id'] as String?;
          if (reqId != null) {
            allRequestIds.add(reqId);
          }
        }
      }
      
      if (createdGames is List) {
        for (final game in createdGames) {
          final gameId = game['id'] as String?;
          if (gameId != null) {
            allRequestIds.add(gameId);
          }
        }
      }

      if (kDebugMode) {
        print('[DEBUG] loadAllMyIndividualMatches: Total unique game IDs: ${allRequestIds.length}');
      }

      if (allRequestIds.isEmpty) {
        allMyIndividualMatches = [];
        loadingIndividualMatches = false;
        notifyListeners();
        return;
      }

      final requestIds = allRequestIds.toList();

      // Load game details
      final games = await supa
          .from('instant_match_requests')
          .select('id, sport, mode, zip_code, start_time_1, start_time_2, venue, details, status, created_by, num_players, visibility, friends_group_id, chat_enabled, chat_mode, created_at')
          .inFilter('id', requestIds)
          .neq('mode', 'team_vs_team')
          .order('created_at', ascending: false);

      if (games is List) {
        // Get creator names
        final creatorIds = games
            .map<String?>((g) => g['created_by'] as String?)
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();

        final creators = creatorIds.isEmpty
            ? <dynamic>[]
            : await supa
                .from('users')
                .select('id, full_name')
                .inFilter('id', creatorIds);

        final Map<String, String> creatorNames = {};
        if (creators is List) {
          for (final c in creators) {
            final id = c['id'] as String?;
            final name = c['full_name'] as String?;
            if (id != null) {
              creatorNames[id] = name ?? 'Unknown';
            }
          }
        }

        // Get attendance status for each game
        final Map<String, String> attendanceStatusByRequest = {};
        if (attendanceRows is List) {
          for (final row in attendanceRows) {
            final reqId = row['request_id'] as String?;
            final status = (row['status'] as String?)?.toLowerCase() ?? 'pending';
            if (reqId != null) {
              attendanceStatusByRequest[reqId] = status;
            }
          }
        }
        
        // For games created by user without attendance record, set status to 'accepted'
        for (final game in games) {
          final gameId = game['id'] as String?;
          final createdBy = game['created_by'] as String?;
          if (gameId != null && createdBy == uid && !attendanceStatusByRequest.containsKey(gameId)) {
            attendanceStatusByRequest[gameId] = 'accepted';
          }
        }

        // Get accepted count for each game
        final acceptedCounts = await supa
            .from('individual_game_attendance')
            .select('request_id')
            .inFilter('request_id', requestIds)
            .eq('status', 'accepted');

        final Map<String, int> acceptedCountByRequest = {};
        if (acceptedCounts is List) {
          for (final row in acceptedCounts) {
            final reqId = row['request_id'] as String?;
            if (reqId != null) {
              acceptedCountByRequest[reqId] = (acceptedCountByRequest[reqId] ?? 0) + 1;
            }
          }
        }

        // Build enriched match list
        final List<Map<String, dynamic>> enriched = [];
        for (final game in games) {
          final reqId = game['id'] as String?;
          if (reqId == null) continue;

          final startTime1 = game['start_time_1'];
          final startTime2 = game['start_time_2'];
          DateTime? startDt;
          DateTime? endDt;
          if (startTime1 is String) {
            final parsed = DateTime.tryParse(startTime1);
            startDt = parsed?.toLocal();
          }
          if (startTime2 is String) {
            final parsed = DateTime.tryParse(startTime2);
            endDt = parsed?.toLocal();
          }

          final createdBy = game['created_by'] as String?;
          final numPlayers = game['num_players'] as int? ?? 4;
          final acceptedCount = acceptedCountByRequest[reqId] ?? 0;
          final spotsLeft = numPlayers - acceptedCount;

          enriched.add({
            'request_id': reqId,
            'sport': game['sport'],
            'zip_code': game['zip_code'],
            'start_time': startDt,
            'end_time': endDt,
            'venue': game['venue'],
            'details': game['details'],
            'status': game['status'],
            'created_by': createdBy,
            'creator_name': creatorNames[createdBy] ?? 'Unknown',
            'num_players': numPlayers,
            'accepted_count': acceptedCount,
            'spots_left': spotsLeft,
            'my_attendance_status': attendanceStatusByRequest[reqId] ?? 'pending',
            'visibility': game['visibility'],
            'friends_group_id': game['friends_group_id'],
            'chat_enabled': game['chat_enabled'] as bool? ?? false,
            'chat_mode': game['chat_mode'] as String? ?? 'all_users',
          });
        }

        allMyIndividualMatches = enriched;
      } else {
        allMyIndividualMatches = [];
      }
    } catch (e) {
      lastError = 'loadAllMyIndividualMatches failed: $e';
      if (kDebugMode) {
        print('[DEBUG] loadAllMyIndividualMatches ERROR: $e');
      }
      allMyIndividualMatches = [];
    } finally {
      loadingIndividualMatches = false;
      notifyListeners();
    }
  }

  bool isAdminForTeam(String teamId) => _adminTeamIds.contains(teamId);

  /// Organizer-only means created_by == current user
  bool isOrganizerForMatch(Map<String, dynamic> match) {
    final uid = currentUserId;
    if (uid == null) return false;
    
    // Check if user is the creator (created_by or creator_id)
    final createdBy = match['created_by'] as String?;
    final creatorId = match['creator_id'] as String?;
    if (createdBy == uid || creatorId == uid) {
      if (kDebugMode) {
        print('[DEBUG] isOrganizerForMatch: User is creator (created_by=$createdBy, creator_id=$creatorId)');
      }
      return true;
    }
    
    // For team games, also check if user is an admin of the creating team
    final teamId = match['team_id'] as String?;
    if (teamId != null) {
      final isAdmin = _adminTeamIds.contains(teamId);
      if (kDebugMode) {
        print('[DEBUG] isOrganizerForMatch: teamId=$teamId, isAdmin=$isAdmin, adminTeamIds=$_adminTeamIds');
      }
      if (isAdmin) {
        return true;
      }
    }
    
    if (kDebugMode) {
      print('[DEBUG] isOrganizerForMatch: User is NOT organizer. created_by=$createdBy, creator_id=$creatorId, teamId=$teamId');
    }
    return false;
  }

  /// ✅ Rule: Send reminder only if Admin in either team
  bool canSendReminderForMatch(Map<String, dynamic> match) {
    final teamAId = match['team_a_id'] as String?;
    final teamBId = match['team_b_id'] as String?;
    if (teamAId == null || teamBId == null) return false;
    return isAdminForTeam(teamAId) || isAdminForTeam(teamBId);
  }

  Future<void> approveInvite(Map<String, dynamic> invite) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final inviteId = invite['id'] as String;
      final requestId = invite['request_id'] as String;
      final targetTeamId = invite['target_team_id'] as String;

      await repo.approveTeamVsTeamInvite(
        myUserId: uid,
        inviteId: inviteId,
        requestId: requestId,
        targetTeamId: targetTeamId,
      );

      await loadAdminTeamsAndInvites();
      await loadConfirmedTeamMatches();
      await loadAwaitingOpponentConfirmationGames();
      await loadAllMyMatches(); // Refresh confirmed games
    } catch (e) {
      lastError = 'approveInvite failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> denyInvite(Map<String, dynamic> invite) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final inviteId = invite['id'] as String;
      final requestId = invite['request_id'] as String?;
      await repo.denyInvite(inviteId: inviteId, deniedBy: uid);
      await loadAdminTeamsAndInvites();
      // Also reload awaiting opponent confirmation games to remove denied games
      // This ensures team members don't see games their team has denied
      await loadAwaitingOpponentConfirmationGames();
      
      // Also remove from awaiting games list immediately if present
      if (requestId != null) {
        awaitingOpponentConfirmationGames.removeWhere((m) => m['request_id'] == requestId);
        notifyListeners();
      }
    } catch (e) {
      lastError = 'denyInvite failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// ✅ NEW: Cancel for both teams (soft cancel) - organizer only
  Future<void> cancelGameForBothTeams(Map<String, dynamic> match) async {
    final uid = currentUserId;
    if (uid == null) return;

    final requestId = match['request_id'] as String;

    if (!isOrganizerForMatch(match)) {
      throw Exception('Only the organizer can cancel this game.');
    }

    try {
      await repo.cancelGameSoft(requestId: requestId, cancelledBy: uid);
      // Remove from confirmed matches
      confirmedTeamMatches.removeWhere((m) => m['request_id'] == requestId);
      // Remove from awaiting opponent confirmation games
      awaitingOpponentConfirmationGames.removeWhere((m) => m['request_id'] == requestId);
      // Remove from all matches
      allMyMatches.removeWhere((m) => m['request_id'] == requestId);
      notifyListeners();
    } catch (e) {
      lastError = 'cancelGameForBothTeams failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setMyAttendance({
    required String requestId,
    required String teamId,
    required String status,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await repo.setMyAttendance(
        myUserId: uid,
        requestId: requestId,
        teamId: teamId,
        status: status,
      );
      // Refresh both confirmed matches and pending availability
      await loadConfirmedTeamMatches();
      await loadMyPendingAvailabilityMatches();
      notifyListeners();
    } catch (e) {
      lastError = 'setMyAttendance failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> switchMyTeamForMatch({
    required String requestId,
    required String newTeamId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await repo.switchMyTeamForMatch(
        myUserId: uid,
        requestId: requestId,
        newTeamId: newTeamId,
      );
      await loadConfirmedTeamMatches();
    } catch (e) {
      lastError = 'switchMyTeamForMatch failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Placeholder (you can wire Edge Function / FCM later)
  Future<void> sendReminderToTeams({
    required String requestId,
    required String teamId,
  }) async {
    return;
  }
  
  /// Load discovery/pickup matches (individual matches open for joining)
  Future<void> loadDiscoveryPickupMatches() async {
    final uid = currentUserId;
    if (uid == null) return;

    loadingDiscoveryMatches = true;
    lastError = null;
    notifyListeners();

    try {
      final supa = Supabase.instance.client;
      
      // Get user's current ZIP code for distance calculation
      final userZipCode = await LocationService.getCurrentZipCode();
      if (kDebugMode) {
        print('[DEBUG] User ZIP code for discovery: $userZipCode');
        if (userZipCode == null) {
          print('[DEBUG] ⚠️  WARNING: User ZIP code is null - distance calculation will be skipped');
        }
      }

      // Get friend ids for friends-only visibility
      final friendRows = await supa
          .from('friends')
          .select('friend_id')
          .eq('user_id', uid)
          .eq('status', 'accepted');

      final Set<String> friendIds = {};
      if (friendRows is List) {
        for (final r in friendRows) {
          final fid = r['friend_id'] as String?;
          if (fid != null) friendIds.add(fid);
        }
      }
      
      // Get friends group IDs user is member of
      final groupRows = await supa
          .from('friends_group_members')
          .select('group_id')
          .eq('user_id', uid);
      
      final Set<String> userGroupIds = {};
      if (groupRows is List) {
        for (final r in groupRows) {
          final gid = r['group_id'] as String?;
          if (gid != null) userGroupIds.add(gid);
        }
      }
      
      // Get user's admin teams and their sports for team game eligibility
      final Map<String, List<String>> adminTeamsBySport = {};
      for (final team in adminTeams) {
        final sport = team['sport'] as String?;
        final teamId = team['id'] as String?;
        if (sport != null && teamId != null) {
          adminTeamsBySport.putIfAbsent(sport.toLowerCase(), () => []).add(teamId);
        }
      }
      
      // Load ALL public matches (individual AND team matches)
      // Team matches can only be accepted by admins of teams in the same sport
      // Note: We exclude user's own matches from discovery, but they should see them in "My Games"
      final matches = await supa
          .from('instant_match_requests')
          .select(
            'id, sport, zip_code, mode, start_time_1, start_time_2, venue, status, created_by, num_players, created_at, visibility, is_public, friends_group_id, proficiency_level')
          .neq('status', 'cancelled')
          .neq('created_by', uid) // Don't show own matches in discovery
          .order('created_at', ascending: false)
          .limit(100);
      
      if (matches is List) {
        final List<Map<String, dynamic>> result = [];

        if (kDebugMode) {
          print('🔍 Discovery: Found ${matches.length} total matches');
          // Debug: Print visibility and is_public for each match
          for (final m in matches.take(5)) {
            print('🔍 Match: visibility=${m['visibility']}, is_public=${m['is_public']}, mode=${m['mode']}, sport=${m['sport']}');
          }
        }

        for (final m in matches) {
          final visibility = m['visibility'] as String?;
          final isPublic = m['is_public'] as bool?;
          final creatorId = m['created_by'] as String?;
          final mode = m['mode'] as String?;
          final sport = (m['sport'] as String?)?.toLowerCase() ?? '';
          final matchId = m['id'] as String?;

          // Check visibility - determine if user can see this game
          bool canSee = false;
          final friendsGroupId = m['friends_group_id'] as String?;
          
          // Friends Group games should NEVER appear in Discover tab
          // They should only appear in Pending Approval and My Games
          if (visibility == 'friends_group') {
            canSee = false; // Explicitly exclude friends_group games from Discover
          }
          // Public games - visible to all within radius
          else if (visibility == 'public' || isPublic == true) {
            canSee = true;
          }
          // Legacy friends_only (for backward compatibility)
          else if (visibility == 'friends_only') {
            if (creatorId != null && friendIds.contains(creatorId)) {
              canSee = true;
            }
          }
          // Legacy handling: null visibility defaults to public
          else if (visibility == null && (isPublic == null || isPublic == true)) {
            canSee = true;
          }
          // 'invited' or other values with is_public = false: not visible in discovery
          else {
            canSee = false;
          }

          if (kDebugMode) {
            print('🎮 Match: ${sport.toUpperCase()} | Mode: $mode | Visibility: $visibility | isPublic: $isPublic | canSee: $canSee | ID: ${matchId?.substring(0, 8)}');
            if (!canSee) {
              print('   ⚠️  Match filtered out - visibility check failed');
            }
          }

          if (!canSee) continue;

          // For team games, check if user can accept (must be admin of team in same sport)
          bool canAccept = true;
          if (mode == 'team_vs_team') {
            canAccept = adminTeamsBySport.containsKey(sport) && 
                       (adminTeamsBySport[sport]?.isNotEmpty ?? false);
          }

          DateTime? startDt;
          DateTime? endDt;
          final st1 = m['start_time_1'];
          final st2 = m['start_time_2'];
          if (st1 is String) {
            final parsed = DateTime.tryParse(st1);
            startDt = parsed?.toLocal();
          }
          if (st2 is String) {
            final parsed = DateTime.tryParse(st2);
            endDt = parsed?.toLocal();
          }
          
          // Calculate distance from user's ZIP code to game's ZIP code
          double? distanceMiles;
          final gameZip = m['zip_code'] as String?;
          
          if (userZipCode != null && gameZip != null) {
            // Normalize ZIP codes for comparison
            final normalizedUserZip = userZipCode.trim();
            final normalizedGameZip = gameZip.trim();
            
            if (kDebugMode) {
              print('[DEBUG] Comparing ZIP codes - User: "$normalizedUserZip", Game: "$normalizedGameZip"');
            }
            
            try {
              distanceMiles = await LocationService.calculateDistanceBetweenZipCodes(
                zip1: normalizedUserZip,
                zip2: normalizedGameZip,
              );
              
              if (kDebugMode) {
                if (distanceMiles != null) {
                  print('[DEBUG] ✅ Distance from user ZIP "$normalizedUserZip" to game ZIP "$normalizedGameZip": ${distanceMiles.toStringAsFixed(1)} miles');
                } else {
                  print('[DEBUG] ❌ Distance calculation returned null for ZIPs: "$normalizedUserZip" -> "$normalizedGameZip"');
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('[DEBUG] ❌ Error calculating distance between ZIP codes: $e');
                print('[DEBUG] Stack trace: ${StackTrace.current}');
              }
            }
          } else {
            if (kDebugMode) {
              print('[DEBUG] ⚠️  Cannot calculate distance - userZipCode: $userZipCode, gameZip: $gameZip');
            }
          }
          
          // Initial load: Only include games within 100 miles to limit data size
          // User can then filter within this 100-mile range using the distance filter
          if (distanceMiles != null && distanceMiles > 100) {
            if (kDebugMode) {
              print('[DEBUG] Game ${m['id']?.toString().substring(0, 8)} filtered out - distance ${distanceMiles.toStringAsFixed(1)} miles > 100 miles');
            }
            continue; // Skip games beyond 100 miles
          }
          
          // If distance couldn't be calculated, include it (might be nearby)
          // User can filter it out using the distance filter if needed
          
          result.add({
            'request_id': m['id'] as String,
            'sport': m['sport'],
            'zip_code': m['zip_code'],
            'mode': m['mode'],
            'start_time': startDt,
            'end_time': endDt,
            'venue': m['venue'],
            'num_players': m['num_players'],
            'created_by': m['created_by'],
            'can_accept': canAccept, // Flag indicating if user can accept this game
            'proficiency_level': m['proficiency_level'], // For readiness filtering
            'distance_miles': distanceMiles, // Distance in miles from user ZIP to game ZIP
          });
        }

        if (kDebugMode) {
          print('🔍 Discovery: After filtering, ${result.length} matches will be shown');
          if (result.isEmpty && matches.isNotEmpty) {
            print('   ⚠️  WARNING: Found ${matches.length} matches in DB but none passed visibility check!');
            print('   Check if games have visibility="public" or is_public=true');
          }
        }

        // Batch fetch accepted counts for individual games
        final individualGameIds = result
            .where((r) => r['mode'] != 'team_vs_team')
            .map<String>((r) => r['request_id'] as String)
            .toList();
        
        final Map<String, int> acceptedCountByRequest = {};
        if (individualGameIds.isNotEmpty) {
          final attendanceRows = await supa
              .from('individual_game_attendance')
              .select('request_id')
              .inFilter('request_id', individualGameIds)
              .eq('status', 'accepted');
          
          if (attendanceRows is List) {
            for (final row in attendanceRows) {
              final reqId = row['request_id'] as String?;
              if (reqId != null) {
                acceptedCountByRequest[reqId] = (acceptedCountByRequest[reqId] ?? 0) + 1;
              }
            }
          }
        }
        
        // Add accepted count and spots left to individual games
        for (final r in result) {
          if (r['mode'] != 'team_vs_team') {
            final reqId = r['request_id'] as String;
            final numPlayers = r['num_players'] as int? ?? 4;
            final acceptedCount = acceptedCountByRequest[reqId] ?? 0;
            r['accepted_count'] = acceptedCount;
            r['spots_left'] = numPlayers - acceptedCount;
          }
        }

        discoveryPickupMatches = result;
      } else {
        discoveryPickupMatches = [];
      }
    } catch (e) {
      lastError = 'loadDiscoveryPickupMatches failed: $e';
      discoveryPickupMatches = [];
    } finally {
      loadingDiscoveryMatches = false;
      notifyListeners();
    }
  }

  /// Load pending team matches where user is admin and can approve
  Future<void> loadPendingGamesForAdmin() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      pendingTeamMatchesForAdmin = await repo.getPendingTeamMatchesForAdmin(
        userId: uid,
        adminTeams: adminTeams,
        userZipCode: baseZip,
      );
      notifyListeners();
    } catch (e) {
      lastError = 'loadPendingGamesForAdmin failed: $e';
      notifyListeners();
    }
  }

  /// Load individual games from friends that are "friends_only"
  Future<void> loadFriendsOnlyIndividualGames() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      friendsOnlyIndividualGames = await repo.getFriendsOnlyIndividualGames(
        userId: uid,
      );
      notifyListeners();
    } catch (e) {
      lastError = 'loadFriendsOnlyIndividualGames failed: $e';
      notifyListeners();
    }
  }

  /// Load confirmed team games where MY attendance is still pending
  Future<void> loadMyPendingAvailabilityMatches() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      pendingAvailabilityTeamMatches =
          await repo.loadMyPendingAvailabilityMatches(uid);
      notifyListeners();
    } catch (e) {
      lastError = 'loadMyPendingAvailabilityMatches failed: $e';
      notifyListeners();
    }
  }
  
  /// Load individual games where user has pending attendance request
  Future<void> loadPendingIndividualGames() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final supa = Supabase.instance.client;
      
      // Get pending attendance records
      final pendingRows = await supa
          .from('individual_game_attendance')
          .select('request_id, created_at')
          .eq('user_id', uid)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (kDebugMode) {
        print('[DEBUG] loadPendingIndividualGames: Found ${pendingRows is List ? pendingRows.length : 0} pending attendance records for user $uid');
      }

      if (pendingRows is! List || pendingRows.isEmpty) {
        pendingIndividualGames = [];
        notifyListeners();
        return;
      }

      final requestIds = pendingRows
          .map<String>((r) => r['request_id'] as String)
          .toList();

      if (kDebugMode) {
        print('[DEBUG] loadPendingIndividualGames: Request IDs: $requestIds');
      }

      // Load game details - try querying with and without filters to debug
      List<dynamic> games = [];
      try {
        // First, try querying without the mode filter to see if that's the issue
        final allGames = await supa
            .from('instant_match_requests')
            .select('id, sport, mode, zip_code, start_time_1, start_time_2, venue, details, status, created_by, num_players, visibility, friends_group_id, is_public')
            .inFilter('id', requestIds);
        
        if (kDebugMode) {
          print('[DEBUG] Query without filters: Found ${allGames is List ? allGames.length : 0} games');
          if (allGames is List && allGames.isNotEmpty) {
            for (final game in allGames) {
              print('[DEBUG] Game found: id=${game['id']}, mode=${game['mode']}, status=${game['status']}, visibility=${game['visibility']}');
            }
          }
        }
        
        // Now filter in memory
        // Exclude public games - they should only appear in Discover tab
        if (allGames is List) {
          games = allGames.where((g) {
            final mode = g['mode'] as String?;
            final status = g['status'] as String?;
            final visibility = g['visibility'] as String?;
            final isPublic = g['is_public'] as bool?;
            
            // Exclude team games, cancelled games, and public games
            return mode != 'team_vs_team' && 
                   status != 'cancelled' &&
                   visibility != 'public' && 
                   isPublic != true;
          }).toList();
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DEBUG] Error querying games: $e');
        }
        // Fall back to original query
        // Exclude public games - they should only appear in Discover tab
        final allGamesFallback = await supa
            .from('instant_match_requests')
            .select('id, sport, mode, zip_code, start_time_1, start_time_2, venue, details, status, created_by, num_players, visibility, friends_group_id, is_public')
            .inFilter('id', requestIds)
            .neq('mode', 'team_vs_team')
            .neq('status', 'cancelled')
            .order('created_at', ascending: false);
        
        // Filter out public games
        if (allGamesFallback is List) {
          games = allGamesFallback.where((g) {
            final visibility = g['visibility'] as String?;
            final isPublic = g['is_public'] as bool?;
            return visibility != 'public' && isPublic != true;
          }).toList();
        } else {
          games = [];
        }
      }

      if (kDebugMode) {
        print('[DEBUG] loadPendingIndividualGames: Found ${games is List ? games.length : 0} games after filtering');
        if (games is List && games.isEmpty && requestIds.isNotEmpty) {
          print('[DEBUG] ⚠️ WARNING: Found pending attendance records but no games after filtering!');
          print('[DEBUG] This suggests the games exist but are being filtered out or RLS is blocking access');
        }
      }

      if (games is List) {
        // Get creator names
        final creatorIds = games
            .map<String?>((g) => g['created_by'] as String?)
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();

        final creators = creatorIds.isEmpty
            ? <dynamic>[]
            : await supa
                .from('users')
                .select('id, full_name')
                .inFilter('id', creatorIds);

        final Map<String, String> creatorNames = {};
        if (creators is List) {
          for (final c in creators) {
            final id = c['id'] as String?;
            final name = c['full_name'] as String?;
            if (id != null) {
              creatorNames[id] = name ?? 'Unknown';
            }
          }
        }

        // Get accepted count for each game
        final acceptedCounts = await supa
            .from('individual_game_attendance')
            .select('request_id')
            .inFilter('request_id', requestIds)
            .eq('status', 'accepted');

        final Map<String, int> acceptedCountByRequest = {};
        if (acceptedCounts is List) {
          for (final row in acceptedCounts) {
            final reqId = row['request_id'] as String?;
            if (reqId != null) {
              acceptedCountByRequest[reqId] = (acceptedCountByRequest[reqId] ?? 0) + 1;
            }
          }
        }

        // Build enriched match list
        final List<Map<String, dynamic>> enriched = [];
        for (final game in games) {
          final reqId = game['id'] as String?;
          if (reqId == null) continue;

          final startTime1 = game['start_time_1'];
          final startTime2 = game['start_time_2'];
          DateTime? startDt;
          DateTime? endDt;
          if (startTime1 is String) {
            final parsed = DateTime.tryParse(startTime1);
            startDt = parsed?.toLocal();
          }
          if (startTime2 is String) {
            final parsed = DateTime.tryParse(startTime2);
            endDt = parsed?.toLocal();
          }

          final createdBy = game['created_by'] as String?;
          final numPlayers = game['num_players'] as int? ?? 4;
          final acceptedCount = acceptedCountByRequest[reqId] ?? 0;
          final spotsLeft = numPlayers - acceptedCount;

          enriched.add({
            'request_id': reqId,
            'sport': game['sport'],
            'zip_code': game['zip_code'],
            'start_time': startDt,
            'end_time': endDt,
            'venue': game['venue'],
            'details': game['details'],
            'status': game['status'],
            'created_by': createdBy,
            'creator_name': creatorNames[createdBy] ?? 'Unknown',
            'num_players': numPlayers,
            'accepted_count': acceptedCount,
            'spots_left': spotsLeft,
            'my_attendance_status': 'pending',
            'visibility': game['visibility'],
            'friends_group_id': game['friends_group_id'],
          });
        }

        pendingIndividualGames = enriched;
      } else {
        pendingIndividualGames = [];
      }
    } catch (e) {
      lastError = 'loadPendingIndividualGames failed: $e';
      if (kDebugMode) {
        print('[DEBUG] loadPendingIndividualGames ERROR: $e');
        print('[DEBUG] Stack trace: ${StackTrace.current}');
      }
      pendingIndividualGames = [];
    } finally {
      notifyListeners();
    }
  }
  
  /// Load individual games where organizer needs to approve requests
  Future<void> loadIndividualGamesForOrganizerApproval() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final supa = Supabase.instance.client;
      
      // Get games created by user
      final myGames = await supa
          .from('instant_match_requests')
          .select('id')
          .eq('created_by', uid)
          .neq('mode', 'team_vs_team')
          .neq('status', 'cancelled');

      if (myGames is! List || myGames.isEmpty) {
        // No games to approve
        return;
      }

      final requestIds = myGames.map<String>((g) => g['id'] as String).toList();

      // Get pending attendance requests
      final pendingRequests = await supa
          .from('individual_game_attendance')
          .select('request_id, user_id, created_at')
          .inFilter('request_id', requestIds)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      // This will be used in the UI to show approval dialogs
      // For now, we'll handle approvals directly in the UI when viewing games
    } catch (e) {
      lastError = 'loadIndividualGamesForOrganizerApproval failed: $e';
    }
  }
  
  /// Approve or deny individual game request (organizer only)
  Future<void> approveIndividualGameRequest({
    required String requestId,
    required String userId,
    required bool approve,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final supa = Supabase.instance.client;
      
      // Verify user is organizer
      final game = await supa
          .from('instant_match_requests')
          .select('created_by')
          .eq('id', requestId)
          .maybeSingle();
      
      if (game == null || game['created_by'] != uid) {
        throw Exception('Only the organizer can approve requests');
      }

      // Update attendance status
      await supa
          .from('individual_game_attendance')
          .update({
            'status': approve ? 'accepted' : 'declined',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('request_id', requestId)
          .eq('user_id', userId);

      // Refresh individual games
      await loadAllMyIndividualMatches();
      notifyListeners();
    } catch (e) {
      lastError = 'approveIndividualGameRequest failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Accept a pending admin match
  Future<void> acceptPendingAdminMatch({
    required String requestId,
    required String myAdminTeamId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await repo.acceptPendingAdminMatch(
        requestId: requestId,
        myAdminTeamId: myAdminTeamId,
        userId: uid,
      );
      // Refresh lists after successful accept
      await loadPendingGamesForAdmin();
      await loadAdminTeamsAndInvites();
      await loadAwaitingOpponentConfirmationGames();
      await loadAllMyMatches(); // Refresh confirmed games
      notifyListeners();
    } catch (e) {
      final errorMsg = e.toString();
      // If invite already exists, treat it as success and refresh
      if (errorMsg.contains('Invite already exists') || 
          errorMsg.contains('already exists')) {
        // Refresh lists to remove the duplicate from UI
        await loadPendingGamesForAdmin();
        await loadAdminTeamsAndInvites();
        await loadAwaitingOpponentConfirmationGames();
        await loadAllMyMatches(); // Refresh confirmed games
        notifyListeners();
        // Don't throw - treat as success since invite exists
        return;
      }
      lastError = 'acceptPendingAdminMatch failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> denyPendingAdminMatch({
    required String requestId,
    required String myAdminTeamId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await repo.denyPendingAdminMatch(
        requestId: requestId,
        myAdminTeamId: myAdminTeamId,
        userId: uid,
      );
      // Refresh lists after successful deny
      await loadPendingGamesForAdmin();
      notifyListeners();
    } catch (e) {
      lastError = 'denyPendingAdminMatch failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loadAwaitingOpponentConfirmationGames() async {
    final uid = currentUserId;
    if (uid == null) return;
    
    // Prevent multiple simultaneous loads
    if (loadingAwaitingOpponentGames) return;

    loadingAwaitingOpponentGames = true;
    notifyListeners();

    try {
      // Get ALL teams user is a member of (not just admin teams)
      final allUserTeams = await repo.getNonAdminTeams(uid);
      final allTeamIds = [
        ...adminTeams.map((t) => t['id'] as String),
        ...allUserTeams.map((t) => t['id'] as String),
      ].toSet().toList(); // Remove duplicates
      
      awaitingOpponentConfirmationGames = await repo.getAwaitingOpponentConfirmationGames(
        uid,
        allTeamIds,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] loadAwaitingOpponentConfirmationGames: $e');
      }
      lastError = 'loadAwaitingOpponentConfirmationGames failed: $e';
    } finally {
      loadingAwaitingOpponentGames = false;
      notifyListeners();
    }
  }

  /// Load public games that match user's notification preferences
  Future<void> loadPublicPendingGames() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      // Get user's current location coordinates
      final coords = await LocationService.getCurrentCoordinates();
      final userZip = await repo.getBaseZip(uid);

      publicPendingGames = await repo.getPublicGamesForUser(
        userId: uid,
        userZipCode: userZip,
        userLat: coords?['lat'],
        userLng: coords?['lng'],
      );
      notifyListeners();
    } catch (e) {
      lastError = 'loadPublicPendingGames failed: $e';
      notifyListeners();
    }
  }
}
