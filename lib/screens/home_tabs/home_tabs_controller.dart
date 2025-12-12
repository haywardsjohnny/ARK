import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/home_repository.dart';

class HomeTabsController extends ChangeNotifier {
  final SupabaseClient supa;
  final HomeRepository repo;

  HomeTabsController(this.supa) : repo = HomeRepository(supa);

  int selectedIndex = 0;

  String? currentUserId;
  String? baseZip;
  List<String> userSports = [];

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

  void setSelectedIndex(int index) {
    selectedIndex = index;
    notifyListeners();
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

  void disposeRealtime() {
    if (attendanceChannel != null) {
      supa.removeChannel(attendanceChannel!);
      attendanceChannel = null;
    }
  }

  Future<void> loadUserBasics() async {
    final uid = currentUserId;
    if (uid == null) return;

    baseZip = await repo.getBaseZip(uid);
    userSports = await repo.getUserSports(uid);
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

  Future<bool> approveTeamVsTeamInvite(Map<String, dynamic> invite) async {
    final uid = currentUserId;
    if (uid == null) return false;

    try {
      await repo.approveTeamVsTeamInvite(
        myUserId: uid,
        inviteId: invite['id'] as String,
        requestId: invite['request_id'] as String,
        targetTeamId: invite['target_team_id'] as String,
      );

      await loadAdminTeamsAndInvites();
      await loadConfirmedTeamMatches();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setMyAttendance(String requestId, String teamId, String status) async {
    final uid = currentUserId;
    if (uid == null) return;

    await repo.setMyAttendance(
      myUserId: uid,
      requestId: requestId,
      teamId: teamId,
      status: status,
    );
    await loadConfirmedTeamMatches();
  }

  Future<void> switchMyTeamForMatch(String requestId, String newTeamId) async {
    final uid = currentUserId;
    if (uid == null) return;

    await repo.switchMyTeamForMatch(
      myUserId: uid,
      requestId: requestId,
      newTeamId: newTeamId,
    );
    await loadConfirmedTeamMatches();
  }

  // Placeholder until we move the sheet UI into a dedicated widget/service.
  Future<void> showCreateInstantMatchSheet(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create instant match sheet not wired yet.')),
    );
  }

  Future<bool> sendReminderToMyTeam(String requestId, String teamId) async {
    // placeholder
    return true;
  }
}
