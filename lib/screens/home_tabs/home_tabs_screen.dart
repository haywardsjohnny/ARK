import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../user_profile_screen.dart';
import 'home_tabs_controller.dart';

class HomeTabsScreen extends StatefulWidget {
  const HomeTabsScreen({super.key});

  @override
  State<HomeTabsScreen> createState() => _HomeTabsScreenState();
}

class _HomeTabsScreenState extends State<HomeTabsScreen> {
  late final HomeTabsController _controller;
  bool _initialPopupShown = false;
  bool _initDone = false;

  final List<String> _allSportsOptions = const [
    'badminton',
    'basketball',
    'cricket',
    'football',
    'pickleball',
    'soccer',
    'table_tennis',
    'tennis',
    'volleyball',
  ];

  @override
  void initState() {
    super.initState();
    _controller = HomeTabsController(Supabase.instance.client);
    _init();
  }

  Future<void> _init() async {
    await _controller.init();
    if (!mounted) return;

    setState(() => _initDone = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_initialPopupShown) return;
      if (_controller.currentUserId == null) return;
      _initialPopupShown = true;
      _showCreateInstantMatchSheet();
    });
  }

  @override
  void dispose() {
    _controller.disposeRealtime();
    super.dispose();
  }

  String _displaySport(String key) {
    final withSpaces = key.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  // ---------- UI HELPERS ----------

  Color _statusChipColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Colors.green.shade100;
      case 'declined':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade200;
    }
  }

  Color _statusTextColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Colors.green.shade900;
      case 'declined':
        return Colors.red.shade900;
      default:
        return Colors.grey.shade800;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return 'Available';
      case 'declined':
        return 'Not Available';
      default:
        return 'Pending';
    }
  }

  String _formatTimeRange(DateTime? start, DateTime? end) {
    if (start == null) return 'Time: TBA';

    String fmtTime(DateTime dt) {
      final h24 = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final isPM = h24 >= 12;
      final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
      final ampm = isPM ? 'PM' : 'AM';
      return '$h12:$m $ampm';
    }

    final dateStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

    if (end == null) return '$dateStr • ${fmtTime(start)}';
    return '$dateStr • ${fmtTime(start)} – ${fmtTime(end)}';
  }

  Widget _errorBanner() {
    if (_controller.lastError == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _controller.lastError!,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }

  // ---------- NEW: HIDE / CANCEL dialogs ----------

  Future<void> _confirmHideGame(String requestId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hide this game?'),
        content: const Text(
          'This removes it only from your My Games. Others will still see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hide'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _controller.hideGame(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game hidden from your My Games')),
      );
    }
  }

  Future<void> _confirmCancelGame(Map<String, dynamic> match) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel game for both teams?'),
        content: const Text(
          'This will cancel the game for everyone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _controller.cancelGameForBothTeams(match);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game cancelled')),
      );
    }
  }

  // ---------- CREATE INSTANT MATCH ----------

  Future<void> _showCreateInstantMatchSheet() async {
    if (_controller.currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first.')),
      );
      return;
    }

    final supa = Supabase.instance.client;

    String? selectedSport;
    String matchType = 'team'; // 'team' or 'pickup'
    String? selectedTeamId;

    double radiusMiles = 10;
    String? proficiencyLevel;
    bool isPublic = true;
    int? numPlayers;

    DateTime? selectedDate;
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    bool useGoogleMapLink = false;
    String? venueText;

    String? errorText;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: ctx,
                initialDate: selectedDate ?? now,
                firstDate: now.subtract(const Duration(days: 1)),
                lastDate: now.add(const Duration(days: 365)),
              );
              if (picked != null) setSheetState(() => selectedDate = picked);
            }

            Future<void> pickTime(bool isStart) async {
              final now = TimeOfDay.now();
              final picked = await showTimePicker(
                context: ctx,
                initialTime: isStart ? (startTime ?? now) : (endTime ?? now),
              );
              if (picked != null) {
                setSheetState(() {
                  if (isStart) startTime = picked;
                  if (!isStart) endTime = picked;
                });
              }
            }

            Future<void> submit() async {
              if (selectedSport == null) {
                setSheetState(() => errorText = 'Please choose a sport.');
                return;
              }
              if (selectedDate == null) {
                setSheetState(() => errorText = 'Please choose a day.');
                return;
              }
              if (startTime == null || endTime == null) {
                setSheetState(() => errorText = 'Please choose start/end time.');
                return;
              }
              if (matchType == 'team' && selectedTeamId == null) {
                setSheetState(() =>
                    errorText = 'Please select which team this is for.');
                return;
              }
              if (matchType == 'pickup' && ((numPlayers ?? 0) <= 0)) {
                setSheetState(() =>
                    errorText = 'Please enter how many players needed.');
                return;
              }

              setSheetState(() {
                saving = true;
                errorText = null;
              });

              try {
                final d = selectedDate!;
                final startLocal = DateTime(
                  d.year,
                  d.month,
                  d.day,
                  startTime!.hour,
                  startTime!.minute,
                );
                final endLocal = DateTime(
                  d.year,
                  d.month,
                  d.day,
                  endTime!.hour,
                  endTime!.minute,
                );

                // ✅ Store as UTC ISO strings
                final startUtc = startLocal.toUtc().toIso8601String();
                final endUtc = endLocal.toUtc().toIso8601String();

                // ✅ OPT A: only columns that exist in instant_match_requests
                final insertMap = <String, dynamic>{
                  'creator_id': _controller.currentUserId,
                  'created_by': _controller.currentUserId,
                  'mode': matchType == 'team' ? 'team_vs_team' : 'pickup',
                  'match_type': matchType == 'team' ? 'team_vs_team' : 'pickup',
                  'sport': selectedSport,
                  'zip_code': _controller.baseZip,
                  'radius_miles': radiusMiles.toInt(),
                  'proficiency_level': proficiencyLevel,
                  'is_public': isPublic,
                  'visibility': isPublic ? 'public' : 'friends_only',
                  'status': 'open',
                  'start_time_1': startUtc,
                  'start_time_2': endUtc,
                  'last_updated_at': DateTime.now().toUtc().toIso8601String(),
                };

                if (matchType == 'team') {
                  insertMap['team_id'] = selectedTeamId;
                } else {
                  insertMap['num_players'] = numPlayers;
                }

                final v = venueText?.trim();
                if (v != null && v.isNotEmpty) {
                  insertMap['venue'] = v;
                  insertMap['venue_type'] =
                      useGoogleMapLink ? 'google_map' : 'free_text';
                }

                final reqRow = await supa
                    .from('instant_match_requests')
                    .insert(insertMap)
                    .select('id')
                    .maybeSingle();

                final requestId = reqRow?['id'] as String?;
                if (requestId == null) {
                  throw Exception('Failed to create request');
                }

                // create invites for team_vs_team
                if (matchType == 'team') {
                  final myTeamId = selectedTeamId!;
                  final sportValue = selectedSport!;

                  final allTeamsRes = await supa
                      .from('teams')
                      .select('id, sport')
                      .neq('id', myTeamId)
                      .eq('sport', sportValue);

                  if (allTeamsRes is List) {
                    final inviteRows = <Map<String, dynamic>>[];
                    for (final t in allTeamsRes) {
                      inviteRows.add({
                        'request_id': requestId,
                        'target_team_id': t['id'] as String,
                        'status': 'pending',
                        'target_type': 'team',
                      });
                    }
                    if (inviteRows.isNotEmpty) {
                      await supa
                          .from('instant_request_invites')
                          .insert(inviteRows);
                    }
                  }
                }

                if (!mounted) return;
                Navigator.of(sheetCtx).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Instant match request created')),
                );

                await _controller.loadAdminTeamsAndInvites();
              } catch (e) {
                setSheetState(() {
                  saving = false;
                  errorText = 'Failed to create request: $e';
                });
              }
            }

            final filteredAdminTeams = selectedSport == null
                ? _controller.adminTeams
                : _controller.adminTeams
                    .where((t) =>
                        (t['sport'] as String? ?? '').toLowerCase() ==
                        selectedSport!.toLowerCase())
                    .toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: bottomInset + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Create instant match',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedSport,
                      decoration: const InputDecoration(
                        labelText: 'Sport *',
                        prefixIcon: Icon(Icons.sports),
                      ),
                      items: _allSportsOptions
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(_displaySport(s)),
                              ))
                          .toList(),
                      onChanged: (v) => setSheetState(() {
                        selectedSport = v;
                        selectedTeamId = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Team vs Team'),
                            value: 'team',
                            groupValue: matchType,
                            onChanged: (v) =>
                                setSheetState(() => matchType = v ?? 'team'),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Individuals'),
                            value: 'pickup',
                            groupValue: matchType,
                            onChanged: (v) =>
                                setSheetState(() => matchType = v ?? 'pickup'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (matchType == 'team') ...[
                      DropdownButtonFormField<String>(
                        value: selectedTeamId,
                        decoration: const InputDecoration(
                          labelText: 'Your team *',
                          prefixIcon: Icon(Icons.groups),
                        ),
                        items: filteredAdminTeams
                            .map((t) => DropdownMenuItem(
                                  value: t['id'] as String,
                                  child: Text(t['name'] as String? ?? ''),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setSheetState(() => selectedTeamId = v),
                      ),
                      if (selectedSport != null && filteredAdminTeams.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'No admin team found for ${_displaySport(selectedSport!)}.\nCreate/select a team first.',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red),
                          ),
                        ),
                    ] else
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'How many players are you looking for? *',
                          prefixIcon: Icon(Icons.person_add_alt_1),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) =>
                            setSheetState(() => numPlayers = int.tryParse(val)),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickDate,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              selectedDate == null
                                  ? 'Match day'
                                  : '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickTime(true),
                            icon: const Icon(Icons.access_time),
                            label: Text(startTime == null
                                ? 'Start time'
                                : 'Start: ${startTime!.format(ctx)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickTime(false),
                            icon: const Icon(Icons.access_time_outlined),
                            label: Text(endTime == null
                                ? 'End time'
                                : 'End: ${endTime!.format(ctx)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Venue (optional)',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                      onChanged: (val) => setSheetState(() => venueText = val),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              saving ? null : () => Navigator.of(sheetCtx).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: saving ? null : submit,
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check),
                          label: Text(saving ? 'Creating...' : 'Create request'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- SECTIONS ----------

  Widget _buildTeamVsTeamInvitesSection() {
    if (!_initDone) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller.teamVsTeamInvites.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          'No team match requests yet.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Team vs Team game requests received',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._controller.teamVsTeamInvites.map((inv) {
            final req = inv['base_request'] as Map<String, dynamic>;
            final sport = req['sport'] as String? ?? '';
            final zip = req['zip_code'] as String? ?? '-';

            DateTime? startDt;
            final st1 = req['start_time_1'];
            if (st1 is String) startDt = DateTime.tryParse(st1);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text('Team match request (${_displaySport(sport)})'),
                subtitle: Text([
                  'ZIP: $zip',
                  if (startDt != null) _formatTimeRange(startDt, null),
                ].join(' • ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () async {
                        try {
                          await _controller.denyInvite(inv);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invite denied')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      },
                      child: const Text('Deny'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          await _controller.approveInvite(inv);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invite approved')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      },
                      child: const Text('Accept'),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _playerChip(Map<String, dynamic> p) {
    final name = (p['name'] as String?) ?? 'Player';
    final status = (p['status'] as String?) ?? 'pending';
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _statusChipColor(status),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        '$name • ${_statusLabel(status)}',
        style: TextStyle(fontSize: 12, color: _statusTextColor(status)),
      ),
    );
  }

  Map<String, int> _statusCounts(List<Map<String, dynamic>> players) {
    int a = 0, d = 0, p = 0;
    for (final x in players) {
      final st = ((x['status'] as String?) ?? 'pending').toLowerCase();
      if (st == 'accepted') a++;
      else if (st == 'declined') d++;
      else p++;
    }
    return {'accepted': a, 'declined': d, 'pending': p, 'total': players.length};
  }

  String _pct(int part, int total) {
    if (total <= 0) return '0%';
    final v = ((part / total) * 100).round();
    return '$v%';
  }

  Future<void> _vote({
    required String requestId,
    required String teamId,
    required String status,
  }) async {
    try {
      await _controller.setMyAttendance(
        requestId: requestId,
        teamId: teamId,
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated: ${_statusLabel(status)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _switchSide({
    required String requestId,
    required String newTeamId,
  }) async {
    try {
      await _controller.switchMyTeamForMatch(
        requestId: requestId,
        newTeamId: newTeamId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Switched team for this match')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Widget _buildConfirmedMatchesSection() {
    if (_controller.loadingConfirmedMatches) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller.confirmedTeamMatches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'You don\'t have any games yet.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      );
    }

    final uid = _controller.currentUserId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your games',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._controller.confirmedTeamMatches.map((m) {
            final reqId = m['request_id'] as String;
            final teamAId = m['team_a_id'] as String?;
            final teamBId = m['team_b_id'] as String?;
            final teamAName = m['team_a_name'] as String? ?? 'Team A';
            final teamBName = m['team_b_name'] as String? ?? 'Team B';
            final sport = m['sport'] as String? ?? '';
            final startDt = m['start_time'] as DateTime?;
            final endDt = m['end_time'] as DateTime?;
            final venue = m['venue'] as String?;
            final canSwitchSide = (m['can_switch_side'] as bool?) ?? false;

            final teamAPlayers =
                (m['team_a_players'] as List?)?.cast<Map<String, dynamic>>() ??
                    <Map<String, dynamic>>[];
            final teamBPlayers =
                (m['team_b_players'] as List?)?.cast<Map<String, dynamic>>() ??
                    <Map<String, dynamic>>[];

            final myStatusA = teamAPlayers
                .where((p) => p['user_id'] == uid)
                .map((p) => p['status'] as String?)
                .firstWhere((x) => x != null, orElse: () => null);
            final myStatusB = teamBPlayers
                .where((p) => p['user_id'] == uid)
                .map((p) => p['status'] as String?)
                .firstWhere((x) => x != null, orElse: () => null);

            final myTeamId = myStatusA != null
                ? teamAId
                : (myStatusB != null ? teamBId : teamAId);

            final aCounts = _statusCounts(teamAPlayers);
            final bCounts = _statusCounts(teamBPlayers);

            final isOrganizer = _controller.isOrganizerForMatch(m);
            final canSendReminder = _controller.canSendReminderForMatch(m);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$teamAName vs $teamBName',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'hide') {
                              await _confirmHideGame(reqId);
                            } else if (v == 'cancel') {
                              await _confirmCancelGame(m);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'hide',
                              child: Text('Hide from My Games'),
                            ),
                            if (isOrganizer)
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Text('Cancel game (both teams)'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Sport: ${_displaySport(sport)}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimeRange(startDt, endDt),
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    if (venue != null && venue.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              venue,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (canSendReminder && myTeamId != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _controller.sendReminderToTeams(
                            requestId: reqId,
                            teamId: myTeamId,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Reminder sent (placeholder)')),
                          );
                        },
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Send reminder to teams'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (myTeamId == null)
                                ? null
                                : () => _vote(
                                      requestId: reqId,
                                      teamId: myTeamId,
                                      status: 'accepted',
                                    ),
                            child: const Text('Available'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (myTeamId == null)
                                ? null
                                : () => _vote(
                                      requestId: reqId,
                                      teamId: myTeamId,
                                      status: 'declined',
                                    ),
                            child: const Text('Not available'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: (myTeamId == null)
                                ? null
                                : () => _vote(
                                      requestId: reqId,
                                      teamId: myTeamId,
                                      status: 'pending',
                                    ),
                            child: const Text('Reset'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Team $teamAName: '
                      'Avail ${aCounts['accepted']} (${_pct(aCounts['accepted']!, aCounts['total']!)}), '
                      'Not ${aCounts['declined']} (${_pct(aCounts['declined']!, aCounts['total']!)}), '
                      'Pending ${aCounts['pending']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Team $teamBName: '
                      'Avail ${bCounts['accepted']} (${_pct(bCounts['accepted']!, bCounts['total']!)}), '
                      'Not ${bCounts['declined']} (${_pct(bCounts['declined']!, bCounts['total']!)}), '
                      'Pending ${bCounts['pending']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    if (canSwitchSide && teamAId != null && teamBId != null)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final newTeam =
                                    (myTeamId == teamAId) ? teamBId : teamAId;
                                await _switchSide(
                                  requestId: reqId,
                                  newTeamId: newTeam,
                                );
                              },
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Switch side'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Text(teamAName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(children: teamAPlayers.map(_playerChip).toList()),
                    const SizedBox(height: 10),
                    Text(teamBName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(children: teamBPlayers.map(_playerChip).toList()),
                    const SizedBox(height: 10),
                    Text('Request ID: $reqId',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------- TABS ----------

  Widget _buildHomeTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _controller.loadAdminTeamsAndInvites();
          await _controller.loadConfirmedTeamMatches();
          await _controller.loadDiscoveryPickupMatches();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _errorBanner(),
            const SizedBox(height: 12),
            
            // 1. Create Instant Match Section
            _buildCreateInstantMatchSection(),
            const SizedBox(height: 24),
            
            // 2. Team vs Team Matches Section
            _buildTeamVsTeamMatchesSection(),
            const SizedBox(height: 24),
            
            // 3. Matches (Discovery / Pickup) Section
            _buildDiscoveryPickupMatchesSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  
  // 1. Create Instant Match Section
  Widget _buildCreateInstantMatchSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1. Create Instant Match',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.green,
                child: Icon(Icons.flash_on, color: Colors.white),
              ),
              title: const Text(
                'Create instant match',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Set up a quick match now and find teams or players nearby.',
              ),
              onTap: _showCreateInstantMatchSheet,
            ),
          ),
        ],
      ),
    );
  }
  
  // 2. Team vs Team Matches Section
  Widget _buildTeamVsTeamMatchesSection() {
    if (!_initDone) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    // Filter confirmed matches to only show team vs team
    final teamVsTeamMatches = _controller.confirmedTeamMatches
        .where((m) {
          // All confirmedTeamMatches are already team_vs_team from the query
          return true;
        })
        .toList();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '2. Team vs Team Matches',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (teamVsTeamMatches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No team vs team matches yet.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            )
          else
            ...teamVsTeamMatches.take(5).map((m) {
              return _buildMatchCard(m, isTeamVsTeam: true);
            }),
          if (teamVsTeamMatches.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextButton(
                onPressed: () {
                  // Switch to My Games tab to see all matches
                  setState(() => _controller.selectedIndex = 1);
                },
                child: Text('View all ${teamVsTeamMatches.length} matches'),
              ),
            ),
        ],
      ),
    );
  }
  
  // 3. Matches (Discovery / Pickup) Section
  Widget _buildDiscoveryPickupMatchesSection() {
    if (!_initDone) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_controller.loadingDiscoveryMatches) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '3. Matches (Discovery / Pickup)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_controller.discoveryPickupMatches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No discovery or pickup matches available yet.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            )
          else
            ..._controller.discoveryPickupMatches.take(5).map((m) {
              return _buildPickupMatchCard(m);
            }),
          if (_controller.discoveryPickupMatches.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextButton(
                onPressed: () async {
                  await _controller.loadDiscoveryPickupMatches();
                },
                child: const Text('Load more matches'),
              ),
            ),
        ],
      ),
    );
  }
  
  // Helper to build pickup/discovery match card
  Widget _buildPickupMatchCard(Map<String, dynamic> match) {
    final reqId = match['request_id'] as String;
    final sport = match['sport'] as String? ?? '';
    final numPlayers = match['num_players'];
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final venue = match['venue'] as String?;
    final zip = match['zip_code'] as String?;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Icon(Icons.people_outline, color: Colors.blue.shade700),
        ),
        title: Text(
          '${_displaySport(sport)} Pickup Match',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (numPlayers != null)
              Text('Looking for $numPlayers players'),
            if (startDt != null)
              Text(_formatTimeRange(startDt, endDt)),
            if (venue != null && venue.isNotEmpty)
              Text('Venue: $venue'),
            if (zip != null)
              Text('ZIP: $zip'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // TODO: Show match details or join dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pickup match: ${_displaySport(sport)}')),
          );
        },
      ),
    );
  }
  
  // Helper to build match card
  Widget _buildMatchCard(Map<String, dynamic> match, {required bool isTeamVsTeam}) {
    final reqId = match['request_id'] as String;
    final teamAName = match['team_a_name'] as String? ?? 'Team A';
    final teamBName = match['team_b_name'] as String? ?? 'Team B';
    final sport = match['sport'] as String? ?? '';
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final venue = match['venue'] as String?;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          isTeamVsTeam ? '$teamAName vs $teamBName' : 'Pickup Match',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sport: ${_displaySport(sport)}'),
            if (startDt != null)
              Text(_formatTimeRange(startDt, endDt)),
            if (venue != null && venue.isNotEmpty)
              Text('Venue: $venue'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Navigate to match details or show more info
          // For now, just show a snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Match: $teamAName vs $teamBName')),
          );
        },
      ),
    );
  }

  Widget _buildMyGamesTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('My Games')),
      body: RefreshIndicator(
        onRefresh: _controller.loadConfirmedTeamMatches,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _errorBanner(),
                _buildConfirmedMatchesSection(),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWhatsNewTab() {
    return Scaffold(
      appBar: AppBar(title: const Text("What's New")),
      body: const Center(
        child: Text(
          'What’s New coming soon.\nWe will show updates, tips and nearby events here.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCurrentTabBody() {
    switch (_controller.selectedIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildMyGamesTab();
      case 3:
        return _buildWhatsNewTab();
      default:
        return _buildHomeTab();
    }
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UserProfileScreen()),
      );
      return;
    }
    setState(() => _controller.selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Scaffold(
          body: _buildCurrentTabBody(),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _controller.selectedIndex,
            onTap: _onItemTapped,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_filled),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.sports_esports),
                label: 'My Games',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'My Profile',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.new_releases_outlined),
                label: "What's New",
              ),
            ],
          ),
        );
      },
    );
  }
}
