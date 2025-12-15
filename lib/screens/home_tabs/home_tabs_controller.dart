import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/home_repository.dart';

class HomeTabsController extends ChangeNotifier {
  final HomeRepository repo;
  final SupabaseClient supa;

  HomeTabsController(this.supa) : repo = HomeRepository(supa);

  int selectedIndex = 0;
  String? currentUserId;
  String? baseZip;
  List<String> userSports = [];

  List<Map<String, dynamic>> adminTeams = [];
  List<Map<String, dynamic>> teamVsTeamInvites = [];
  List<Map<String, dynamic>> confirmedTeamMatches = [];
  bool loadingConfirmedMatches = false;

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
          callback: (_) => loadConfirmedTeamMatches(),
        )
        .subscribe();
  }

  Future<void> loadUserBasics() async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      baseZip = await repo.getBaseZip(uid);
      userSports = await repo.getUserSports(uid);
      notifyListeners();
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

      notifyListeners();
    } catch (e) {
      lastError = 'loadAdminTeamsAndInvites failed: $e';
      notifyListeners();
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
      await loadConfirmedTeamMatches();
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
}
