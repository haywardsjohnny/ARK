import 'package:supabase_flutter/supabase_flutter.dart';

class HomeRepository {
  final SupabaseClient supa;
  HomeRepository(this.supa);

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

  Future<List<Map<String, dynamic>>> getAdminTeams(String userId) async {
    final memberRows = await supa
        .from('team_members')
        .select('team_id, role')
        .eq('user_id', userId);

    final adminTeamIds = <String>[];
    if (memberRows is List) {
      for (final m in memberRows) {
        final role = (m['role'] as String?)?.toLowerCase() ?? 'member';
        if (role == 'admin' || role == 'captain') {
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
    for (final inv in inviteRows) {
      final reqId = inv['request_id'] as String;
      final reqRow = await supa
          .from('instant_match_requests')
          .select(
              'id, team_id, sport, zip_code, mode, start_time_1, start_time_2, venue, time_slot_1, time_slot_2')
          .eq('id', reqId)
          .maybeSingle();

      if (reqRow == null) continue;

      invites.add({
        'id': inv['id'] as String,
        'request_id': reqId,
        'target_team_id': inv['target_team_id'] as String,
        'status': inv['status'] as String? ?? 'pending',
        'base_request': reqRow,
      });
    }
    return invites;
  }

  // ---------------- TEAM VS TEAM: ACCEPT INVITE ----------------

  Future<void> approveTeamVsTeamInvite({
    required String myUserId,
    required String inviteId,
    required String requestId,
    required String targetTeamId,
  }) async {
    // 1) accept this invite
    await supa
        .from('instant_request_invites')
        .update({'status': 'accepted'})
        .eq('id', inviteId);

    // 2) cancel other invites for this request
    await supa
        .from('instant_request_invites')
        .update({'status': 'cancelled'})
        .neq('id', inviteId)
        .eq('request_id', requestId);

    // 3) base request (team A)
    final reqRow = await supa
        .from('instant_match_requests')
        .select(
            'id, team_id, sport, zip_code, created_by, start_time_1, venue, time_slot_1')
        .eq('id', requestId)
        .maybeSingle();

    if (reqRow == null) {
      throw Exception('Base team match request not found');
    }

    final teamAId = reqRow['team_id'] as String;
    final creatorUserId = reqRow['created_by'] as String?;

    // 4) mark request as matched
    await supa.from('instant_match_requests').update({
      'status': 'matched',
      'matched_team_id': targetTeamId,
    }).eq('id', requestId);

    // 5) load team members for both teams
    final teamAMembers =
        await supa.from('team_members').select('user_id').eq('team_id', teamAId);

    final teamBMembers = await supa
        .from('team_members')
        .select('user_id')
        .eq('team_id', targetTeamId);

    final List<Map<String, dynamic>> attendanceRows = [];

    if (teamAMembers is List) {
      for (final m in teamAMembers) {
        attendanceRows.add({
          'request_id': requestId,
          'team_id': teamAId,
          'user_id': m['user_id'] as String,
          'status': 'pending',
        });
      }
    }

    if (teamBMembers is List) {
      for (final m in teamBMembers) {
        attendanceRows.add({
          'request_id': requestId,
          'team_id': targetTeamId,
          'user_id': m['user_id'] as String,
          'status': 'pending',
        });
      }
    }

    // Upsert attendance rows, ignoring duplicates on (request_id, user_id)
    if (attendanceRows.isNotEmpty) {
      await supa.from('team_match_attendance').upsert(
            attendanceRows,
            onConflict: 'request_id,user_id',
            ignoreDuplicates: true,
          );
    }

    // creator admin & approving admin -> accepted
    if (creatorUserId != null) {
      await supa
          .from('team_match_attendance')
          .update({'status': 'accepted'})
          .eq('request_id', requestId)
          .eq('user_id', creatorUserId);
    }

    await supa
        .from('team_match_attendance')
        .update({'status': 'accepted'})
        .eq('request_id', requestId)
        .eq('user_id', myUserId);
  }

  // ---------------- CONFIRMED MATCHES FOR CURRENT USER ----------------

  Future<List<Map<String, dynamic>>> loadConfirmedTeamMatches(
      String myUserId) async {
    final attendRows = await supa
        .from('team_match_attendance')
        .select('request_id, team_id, status')
        .eq('user_id', myUserId);

    if (attendRows == null || attendRows is! List || attendRows.isEmpty) {
      return [];
    }

    final requestIds = attendRows
        .map<String>((r) => r['request_id'] as String)
        .toSet()
        .toList();

    // requests that are matched team_vs_team
    final reqs = await supa
        .from('instant_match_requests')
        .select(
            'id, sport, mode, zip_code, team_id, matched_team_id, start_time_1, start_time_2, time_slot_1, time_slot_2, venue, status')
        .inFilter('id', requestIds)
        .eq('mode', 'team_vs_team')
        .eq('status', 'matched');

    final List<Map<String, dynamic>> rows = [];
    if (reqs is! List) return rows;

    for (final r in reqs) {
      final reqId = r['id'] as String;
      final teamAId = r['team_id'] as String;
      final teamBId = r['matched_team_id'] as String?;
      if (teamBId == null) continue;

      // parse date/time
      DateTime? startDt;
      DateTime? endDt;
      final st1 = r['start_time_1'] ?? r['time_slot_1'];
      final st2 = r['start_time_2'] ?? r['time_slot_2'];
      if (st1 is String) startDt = DateTime.tryParse(st1);
      if (st2 is String) endDt = DateTime.tryParse(st2);

      final venue = r['venue'] as String?;

      // team names
      final teamRows = await supa
          .from('teams')
          .select('id, name')
          .inFilter('id', [teamAId, teamBId]);

      String teamAName = 'Team A';
      String teamBName = 'Team B';
      if (teamRows is List) {
        for (final t in teamRows) {
          if (t['id'] == teamAId) {
            teamAName = t['name'] as String? ?? 'Team A';
          } else if (t['id'] == teamBId) {
            teamBName = t['name'] as String? ?? 'Team B';
          }
        }
      }

      final attendees = await supa
          .from('team_match_attendance')
          .select('user_id, team_id, status')
          .eq('request_id', reqId);

      final List<Map<String, dynamic>> teamAPlayers = [];
      final List<Map<String, dynamic>> teamBPlayers = [];

      if (attendees is List) {
        for (final a in attendees) {
          final uid = a['user_id'] as String;
          final teamId = a['team_id'] as String;
          final status = (a['status'] as String?)?.toLowerCase() ?? 'pending';

          final userRow = await supa
              .from('users')
              .select('full_name')
              .eq('id', uid)
              .maybeSingle();

          final displayName = userRow?['full_name'] as String? ?? 'Player';

          final item = {
            'user_id': uid,
            'name': displayName,
            'status': status,
          };

          if (teamId == teamAId) {
            teamAPlayers.add(item);
          } else if (teamId == teamBId) {
            teamBPlayers.add(item);
          }
        }
      }

      // can switch side if member of both
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
      });
    }

    return rows;
  }

  // ---------------- ATTENDANCE ----------------

  Future<void> setMyAttendance({
    required String myUserId,
    required String requestId,
    required String teamId,
    required String status,
  }) async {
    // Use (request_id, user_id) as identity; team can change
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
}
