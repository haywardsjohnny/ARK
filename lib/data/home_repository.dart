// lib/data/home_repository.dart
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
    if (reqRows is List) {
      for (final r in reqRows) {
        final id = r['id'] as String?;
        if (id != null) reqById[id] = Map<String, dynamic>.from(r);
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

      invites.add({
        'id': inv['id'] as String,
        'request_id': reqId,
        'target_team_id': inv['target_team_id'] as String,
        'status': inv['status'] as String? ?? 'pending',
        'base_request': req,
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
    return _loadTeamMatchesForUser(myUserId, onlyAccepted: true);
  }

  Future<List<Map<String, dynamic>>> loadAllMyTeamMatches(
      String myUserId) async {
    return _loadTeamMatchesForUser(myUserId, onlyAccepted: false);
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

    if (attendRows is! List || attendRows.isEmpty) return [];

    final requestIds = attendRows
        .map<String>((r) => r['request_id'] as String)
        .toSet()
        .toList();

    // ✅ DO NOT require status='matched'
    final reqs = await supa
        .from('instant_match_requests')
        .select(
            'id, sport, mode, zip_code, team_id, matched_team_id, start_time_1, start_time_2, venue, status, created_by, creator_id')
        .inFilter('id', requestIds)
        .eq('mode', 'team_vs_team')
        .neq('status', 'cancelled')
        .not('matched_team_id', 'is', null);

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
