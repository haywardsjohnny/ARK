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
  List<Map<String, dynamic>> discoveryPickupMatches = [];
  List<Map<String, dynamic>> pendingTeamMatchesForAdmin = [];
  List<Map<String, dynamic>> friendsOnlyIndividualGames = [];
  List<Map<String, dynamic>> pendingAvailabilityTeamMatches = [];
  bool loadingConfirmedMatches = false;
  bool loadingAllMatches = false;
  bool loadingDiscoveryMatches = false;

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

  bool isAdminForTeam(String teamId) => _adminTeamIds.contains(teamId);

  /// Organizer-only means created_by == current user
  bool isOrganizerForMatch(Map<String, dynamic> match) {
    final uid = currentUserId;
    if (uid == null) return false;
    final createdBy = match['created_by'] as String?;
    return createdBy == uid;
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
      await repo.denyInvite(inviteId: inviteId, deniedBy: uid);
      await loadAdminTeamsAndInvites();
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
      confirmedTeamMatches.removeWhere((m) => m['request_id'] == requestId);
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
      final matches = await supa
          .from('instant_match_requests')
          .select(
            'id, sport, zip_code, mode, start_time_1, start_time_2, venue, status, created_by, num_players, created_at, visibility, is_public')
          .neq('status', 'cancelled')
          .neq('created_by', uid) // Don't show own matches
          .order('created_at', ascending: false)
          .limit(100);
      
      if (matches is List) {
        final List<Map<String, dynamic>> result = [];

        if (kDebugMode) {
          print('🔍 Discovery: Found ${matches.length} total matches');
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
          
          // Explicit check for public games
          if (visibility == 'public' || isPublic == true) {
            canSee = true;
          }
          // Friends-only games
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
          if (st1 is String) startDt = DateTime.tryParse(st1);
          if (st2 is String) endDt = DateTime.tryParse(st2);
          
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
          });
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
      notifyListeners();
    } catch (e) {
      final errorMsg = e.toString();
      // If invite already exists, treat it as success and refresh
      if (errorMsg.contains('Invite already exists') || 
          errorMsg.contains('already exists')) {
        // Refresh lists to remove the duplicate from UI
        await loadPendingGamesForAdmin();
        await loadAdminTeamsAndInvites();
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
}
