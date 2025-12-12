import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/home_repository.dart';

class HomeTabsController extends ChangeNotifier {
  final HomeRepository repo;
  final SupabaseClient supa;

  HomeTabsController(this.supa) : repo = HomeRepository(supa);

  int selectedIndex = 0;
  String? currentUserId;
  String? baseZip;

  List<Map<String, dynamic>> adminTeams = [];
  List<Map<String, dynamic>> teamVsTeamInvites = [];
  List<Map<String, dynamic>> confirmedTeamMatches = [];

  bool loadingConfirmedMatches = false;

  RealtimeChannel? attendanceChannel;

  Future<void> init() async {
    currentUserId = supa.auth.currentUser?.id;
    if (currentUserId == null) return;

    await loadUserBasics();
    await loadAdminTeamsAndInvites();
    await loadConfirmedTeamMatches();
    setupRealtimeAttendance();
  }

  Future<void> loadUserBasics() async {
    final uid = currentUserId;
    if (uid == null) return;

    baseZip = await repo.getBaseZip(uid);
    notifyListeners();
  }

  Future<void> loadAdminTeamsAndInvites() async {
    final uid = currentUserId;
    if (uid == null) return;

    adminTeams = await repo.getAdminTeams(uid);
    final adminTeamIds = adminTeams.map((t) => t['id'] as String).toList();

    teamVsTeamInvites = await repo.getPendingInvitesForTeams(adminTeamIds);
    notifyListeners();
  }

  Future<void> loadConfirmedTeamMatches() async {
    final uid = currentUserId;
    if (uid == null) return;

    loadingConfirmedMatches = true;
    notifyListeners();

    confirmedTeamMatches = await repo.loadConfirmedTeamMatches(uid);

    loadingConfirmedMatches = false;
    notifyListeners();
  }

  void setupRealtimeAttendance() {
    final uid = currentUserId;
    if (uid == null) return;
    if (attendanceChannel != null) return;

    // ✅ Filter subscription so you don’t get ALL table events
    attendanceChannel = supa
        .channel('public:team_match_attendance_user_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'team_match_attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => loadConfirmedTeamMatches(),
        )
        .subscribe();
  }

  void disposeRealtime() {
    if (attendanceChannel != null) {
      supa.removeChannel(attendanceChannel!);
      attendanceChannel = null;
    }
  }

  bool isAdminOfTeam(String teamId) {
    return adminTeams.any((t) => (t['id'] as String) == teamId);
  }

  String displaySport(String key) {
    final withSpaces = key.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> approveInvite({
    required BuildContext context,
    required Map<String, dynamic> invite,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await repo.approveTeamVsTeamInvite(
        myUserId: uid,
        inviteId: invite['id'] as String,
        requestId: invite['request_id'] as String,
        targetTeamId: invite['target_team_id'] as String,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Team match confirmed. Players will be asked to respond.'),
        ),
      );

      await loadAdminTeamsAndInvites();
      await loadConfirmedTeamMatches();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve: $e')),
      );
    }
  }

  Future<void> setMyAttendance({
    required BuildContext context,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update availability: $e')),
      );
    }
  }

  Future<void> switchMyTeamForMatch({
    required BuildContext context,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to switch team: $e')),
      );
    }
  }

  // --- Create Instant Match sheet stays same as the version you already have wired ---
  // (Keeping this response focused on scale/rpc; your wired sheet can remain unchanged.)
}
