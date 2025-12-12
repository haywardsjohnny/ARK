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

  // ✅ RPC: pending invites for admin team ids
  Future<List<Map<String, dynamic>>> getPendingInvitesForTeams(
      List<String> teamIds) async {
    if (teamIds.isEmpty) return [];

    final res = await supa.rpc(
      'get_pending_team_invites',
      params: {'admin_team_ids': teamIds},
    );

    if (res is! List) return [];
    return res.cast<Map<String, dynamic>>();
  }

  // ---------- CREATE REQUEST ----------
  Future<String> createInstantMatchRequest(Map<String, dynamic> insertMap) async {
    final reqRow = await supa
        .from('instant_match_requests')
        .insert(insertMap)
        .select('id')
        .maybeSingle();

    final String? requestId = reqRow?['id'] as String?;
    if (requestId == null) throw Exception('Failed to create instant match request');
    return requestId;
  }

  Future<void> createTeamInvitesForRequest({
    required String requestId,
    required String myTeamId,
    required String sport,
  }) async {
    final allTeamsRes = await supa
        .from('teams')
        .select('id, sport')
        .neq('id', myTeamId)
        .eq('sport', sport);

    if (allTeamsRes is! List) return;

    final List<Map<String, dynamic>> inviteRows = [];
    for (final t in allTeamsRes) {
      inviteRows.add({
        'request_id': requestId,
        'target_team_id': t['id'] as String,
        'status': 'pending',
        'target_type': 'team',
      });
    }

    if (inviteRows.isNotEmpty) {
      await supa.from('instant_request_invites').insert(inviteRows);
    }
  }

  // ---------- APPROVE INVITE (transaction-ish order) ----------
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
        .select('id, team_id, created_by')
        .eq('id', requestId)
        .maybeSingle();

    if (reqRow == null) throw Exception('Base team match request not found');

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

  // ✅ RPC: confirmed matches for user (single call, aggregated)
  Future<List<Map<String, dynamic>>> loadConfirmedTeamMatches(String myUserId) async {
    final res = await supa.rpc(
      'get_confirmed_team_matches',
      params: {'my_user_id': myUserId},
    );

    if (res is! List) return [];

    // Normalize JSON array fields to List<Map<String,dynamic>>
    return res.map<Map<String, dynamic>>((row) {
      final r = Map<String, dynamic>.from(row as Map);

      List<Map<String, dynamic>> parsePlayers(dynamic v) {
        if (v is List) return v.cast<Map<String, dynamic>>();
        return const [];
      }

      r['team_a_players'] = parsePlayers(r['team_a_players']);
      r['team_b_players'] = parsePlayers(r['team_b_players']);
      return r;
    }).toList();
  }

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
        .eq('team_id', teamId)
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
