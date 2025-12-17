import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../user_profile_screen.dart';
import '../teams_screen.dart';
import '../discover_screen.dart';
import '../chat_screen.dart';
import '../create_game_screen.dart';
import 'home_tabs_controller.dart';
import '../../widgets/status_bar.dart';
import '../../utils/sport_defaults.dart';

class HomeTabsScreen extends StatefulWidget {
  const HomeTabsScreen({super.key});

  @override
  State<HomeTabsScreen> createState() => _HomeTabsScreenState();
}

class _HomeTabsScreenState extends State<HomeTabsScreen> {
  late final HomeTabsController _controller;
  bool _initDone = false;
  bool _pendingGamesExpanded = false;
  String _myGamesFilter = 'Current'; // 'Current', 'Past', 'Cancelled', 'Hidden'

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
      // Reload all matches to refresh the lists
      await _controller.loadAllMyMatches();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game hidden from your My Games')),
      );
    }
  }

  Future<void> _confirmUnhideGame(String requestId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unhide this game?'),
        content: const Text(
          'This will make the game visible again in your My Games.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unhide'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _controller.unhideGame(requestId);
      // Reload all matches to refresh the lists
      await _controller.loadAllMyMatches();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game unhidden. It will appear in Current tab if active.')),
      );
    }
  }

  Future<void> _editExpectedPlayers(Map<String, dynamic> match) async {
    final reqId = match['request_id'] as String;
    final sport = match['sport'] as String? ?? '';
    if (sport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid sport')),
      );
      return;
    }
    
    // Get current value: match-specific if exists, otherwise sport default
    final matchSpecific = match['expected_players_per_team'] as int?;
    final currentExpected = matchSpecific ?? await SportDefaults.getExpectedPlayersPerTeam(sport);
    final sportDefault = await SportDefaults.getExpectedPlayersPerTeam(sport);
    
    final controller = TextEditingController(text: currentExpected.toString());
    
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Expected Players'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sport: ${_displaySport(sport)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'This will update the expected players for THIS match only.',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Expected players per team',
                hintText: 'Enter number',
                border: const OutlineInputBorder(),
                helperText: 'Sport default: $sportDefault players',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              matchSpecific != null 
                  ? 'Current (match-specific): $currentExpected players'
                  : 'Current (using sport default): $currentExpected players',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value > 0) {
                Navigator.of(ctx).pop(value);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid number')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result != currentExpected) {
      try {
        // Update this specific match's expected_players_per_team
        final supa = Supabase.instance.client;
        await supa
            .from('instant_match_requests')
            .update({'expected_players_per_team': result})
            .eq('id', reqId);

        // Reload matches to refresh the UI
        await _controller.loadAllMyMatches();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Expected players for this match updated to $result')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
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

    // Navigate to new multi-step create game screen
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateGameScreen(controller: _controller),
      ),
    );
  }

  // Old implementation - kept for reference but not used
  Future<void> _showCreateInstantMatchSheetOld() async {
    if (_controller.currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first.')),
      );
      return;
    }

    final supa = Supabase.instance.client;
    
    // Check if user has admin teams
    final hasAdminTeams = _controller.adminTeams.isNotEmpty;

    String? selectedSport;
    String matchType = hasAdminTeams ? 'team' : 'pickup'; // Default to pickup if no admin teams
    String? selectedTeamId;

    double radiusMiles = 75;
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
                    if (hasAdminTeams) ...[
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
                    ] else ...[
                      // If no admin teams, only show Individual option
                      Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.orange.shade700),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Individual game only',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                          ),
                        ),
                      ],
                    ),
                              const SizedBox(height: 8),
                              const Text(
                                'Become admin of your existing team to be able to create Team games or Create a New Team.',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const TeamsScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.admin_panel_settings),
                                      label: const Text('Request Admin Rights'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        Navigator.of(ctx).pop();
                                        await _showCreateNewTeamPopup();
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Create New Team'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
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


  // ---------- CREATE NEW TEAM POPUP ----------

  Future<void> _showCreateNewTeamPopup() async {
    final supa = Supabase.instance.client;
    final creatorId = _controller.currentUserId;
    if (creatorId == null) return;

    final nameCtrl = TextEditingController();
    final zipCtrl = TextEditingController(text: _controller.baseZip ?? '');
    final descCtrl = TextEditingController();
    String? selectedSport;
    String? selectedLevel;
    String? errorText;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        final bottomInset = MediaQuery.of(bottomSheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> submit() async {
              final teamName = nameCtrl.text.trim();
              final zip = zipCtrl.text.trim();
              final desc = descCtrl.text.trim();

              if (selectedSport == null || teamName.isEmpty || zip.isEmpty) {
                setSheetState(() {
                  errorText = 'Sport, Team name and ZIP code are required.';
                });
                return;
              }

              setSheetState(() {
                saving = true;
                errorText = null;
              });

              try {
                // 1) Insert team
                final insertRes = await supa
                    .from('teams')
                    .insert({
                      'name': teamName,
                      'sport': selectedSport,
                      'zip_code': zip,
                      'description': desc.isEmpty ? null : desc,
                      'proficiency_level': selectedLevel,
                      'created_by': creatorId,
                    })
                    .select('id')
                    .maybeSingle();

                final teamId = insertRes?['id'] as String?;
                if (teamId == null) {
                  throw Exception('Failed to create team (no ID returned)');
                }

                // 2) Add creator as admin
                await supa.from('team_members').insert({
                  'team_id': teamId,
                  'user_id': creatorId,
                  'role': 'admin',
                });

                if (!mounted) return;

                Navigator.of(bottomSheetContext).pop();
                await _controller.loadAdminTeamsAndInvites();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Team "$teamName" created. You can now create team matches!'),
                  ),
                );
              } catch (e) {
                setSheetState(() {
                  saving = false;
                  errorText = 'Failed to create team: $e';
                });
              }
            }

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
                      'Create a Team',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Sport dropdown
                    DropdownButtonFormField<String>(
                      value: selectedSport,
                      decoration: const InputDecoration(
                        labelText: 'Sport *',
                        prefixIcon: Icon(Icons.sports),
                      ),
                      items: _allSportsOptions
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(_displaySport(s)),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setSheetState(() {
                          selectedSport = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Team name
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Team name *',
                        prefixIcon: Icon(Icons.group),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ZIP
                    TextField(
                      controller: zipCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Team ZIP code *',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),

                    // Proficiency level
                    DropdownButtonFormField<String>(
                      value: selectedLevel,
                      decoration: const InputDecoration(
                        labelText: 'Proficiency level (optional)',
                        prefixIcon: Icon(Icons.bar_chart),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Recreational',
                          child: Text('Recreational'),
                        ),
                        DropdownMenuItem(
                          value: 'Intermediate',
                          child: Text('Intermediate'),
                        ),
                        DropdownMenuItem(
                          value: 'Competitive',
                          child: Text('Competitive'),
                        ),
                      ],
                      onChanged: (val) {
                        setSheetState(() {
                          selectedLevel = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Description
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          errorText!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving ? null : () => Navigator.of(bottomSheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: saving ? null : submit,
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check),
                          label: Text(saving ? 'Creating...' : 'Create Team'),
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

  /// Calculate percentage based on expected players (for status bar)
  double _calculatePercentage(int available, int? expectedPlayers) {
    if (expectedPlayers == null || expectedPlayers <= 0) return 0.0;
    return (available / expectedPlayers).clamp(0.0, 1.0);
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
      // Reload all matches to reflect the change
      await _controller.loadAllMyMatches();
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
      // Reload all matches to reflect the change
      await _controller.loadAllMyMatches();
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

            // Get user's attendance status (from RPC result or fallback to team players)
            final myAttendanceStatus = (m['my_attendance_status'] as String?)?.toLowerCase() ??
                teamAPlayers
                    .where((p) => p['user_id'] == uid)
                    .map((p) => (p['status'] as String?)?.toLowerCase())
                    .firstWhere((x) => x != null, orElse: () => null) ??
                teamBPlayers
                    .where((p) => p['user_id'] == uid)
                    .map((p) => (p['status'] as String?)?.toLowerCase())
                    .firstWhere((x) => x != null, orElse: () => 'accepted');

            final myStatusA = teamAPlayers
                .where((p) => p['user_id'] == uid)
                .map((p) => p['status'] as String?)
                .firstWhere((x) => x != null, orElse: () => null);
            final myStatusB = teamBPlayers
                .where((p) => p['user_id'] == uid)
                .map((p) => p['status'] as String?)
                .firstWhere((x) => x != null, orElse: () => null);

            final myTeamId = m['my_team_id'] as String? ??
                (myStatusA != null
                ? teamAId
                    : (myStatusB != null ? teamBId : teamAId));
            
            final isDeclined = myAttendanceStatus == 'declined';

            final aCounts = _statusCounts(teamAPlayers);
            final bCounts = _statusCounts(teamBPlayers);

            final isOrganizer = _controller.isOrganizerForMatch(m);
            final canSendReminder = _controller.canSendReminderForMatch(m);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: isDeclined ? Colors.grey.shade100 : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                            '$teamAName vs $teamBName',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                              if (isDeclined) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Not Available',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
      body: RefreshIndicator(
        onRefresh: () async {
          await _controller.loadUserBasics();
          await _controller.loadAdminTeamsAndInvites();
          await _controller.loadConfirmedTeamMatches();
          await _controller.loadDiscoveryPickupMatches();
          await _controller.loadPendingGamesForAdmin();
          await _controller.loadFriendsOnlyIndividualGames();
          await _controller.loadMyPendingAvailabilityMatches();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (kDebugMode) ...[
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.yellow.shade100,
                child: Text(
                  'Debug: pendingAvailabilityTeamMatches=${_controller.pendingAvailabilityTeamMatches.length}, '
                  'userId=${_controller.currentUserId}, lastError=${_controller.lastError ?? 'none'}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
            _errorBanner(),
            const SizedBox(height: 12),
            
            // [ Greeting ] Section
            _buildGreetingSection(),
            const SizedBox(height: 24),
            
            // [ Primary CTA ] Section
            _buildPrimaryCTASection(),
            const SizedBox(height: 24),
            
            // [ Smart Cards ] Section
            _buildSmartCardsSection(),
            const SizedBox(height: 24),
            
            // [ Sponsored / Monetization ] Section
            _buildSponsoredSection(),
            const SizedBox(height: 24),
            
            // [ My Games Preview ] Section
            _buildMyGamesPreviewSection(),
            const SizedBox(height: 24),
            
            // [ Pending Games ] Section (expanded)
            if (_pendingGamesExpanded) ...[
              _buildPendingGamesSection(),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
  
  // [ Greeting ] Section
  Widget _buildGreetingSection() {
    final name = _controller.userName ?? 'User';
    final location = _controller.userLocation ?? 'Location';
    
    return Row(
      children: [
        const Text('👋', style: TextStyle(fontSize: 24)),
        const SizedBox(width: 8),
        Text(
          'Hi $name',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Text(' | ', style: TextStyle(fontSize: 18, color: Colors.grey)),
        const Icon(Icons.location_on, size: 18, color: Colors.grey),
        Text(
          location,
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ],
    );
  }
  
  // [ Primary CTA ] Section
  Widget _buildPrimaryCTASection() {
    return Row(
      children: [
        Expanded(
          child: _buildCTACard(
            icon: '🟢',
            label: 'Join Game',
            isSelected: true, // Join Game is default selected
            onTap: () {
              // Navigate to Discover tab
              _controller.selectedIndex = 1;
              setState(() {});
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildCTACard(
            icon: '⚪',
            label: 'Create Game',
            isSelected: false,
            onTap: () {
              _showCreateInstantMatchSheet();
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildCTACard({
    required String icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // [ Smart Cards ] Section
  Widget _buildSmartCardsSection() {
    final cards = _buildSmartCards();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Smart Cards',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (cards.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No smart cards available'),
            ),
          )
        else
          ...cards,
      ],
    );
  }

  List<Widget> _buildSmartCards() {
    final cards = <Widget>[];
    final now = DateTime.now();
    final userId = _controller.currentUserId;

    // 1️⃣ Urgency-based: Match is today, spots < 3, user eligible
    for (final match in _controller.discoveryPickupMatches) {
      final startDt = match['start_time'] as DateTime?;
      if (startDt == null) continue;
      
      final isToday = startDt.day == now.day && 
                      startDt.month == now.month && 
                      startDt.year == now.year;
      
      if (!isToday) continue;
      
      final numPlayers = match['num_players'] as int? ?? 0;
      final spotsLeft = numPlayers;
      
      if (spotsLeft >= 3) continue; // Only show if < 3 spots
      
      final sport = match['sport'] as String? ?? '';
      final sportEmoji = _getSportEmoji(sport);
      
      cards.add(_buildUrgencyCard(
        sportEmoji: sportEmoji,
        sport: sport,
        spotsLeft: spotsLeft,
        match: match,
      ));
      
      if (cards.length >= 4) break; // Max 4 cards
    }

    // 2️⃣ Action-required: User created/requested, approval pending
    if (cards.length < 4 && userId != null) {
      final pendingRequests = _controller.teamVsTeamInvites
          .where((inv) {
            final req = inv['request'] as Map<String, dynamic>?;
            if (req == null) return false;
            final createdBy = req['created_by'] as String?;
            final status = req['status'] as String?;
            return createdBy == userId && (status == 'pending' || status == null);
          })
          .take(4 - cards.length)
          .toList();
      
      for (final invite in pendingRequests) {
        final req = invite['request'] as Map<String, dynamic>?;
        if (req == null) continue;
        
        final startDt = req['start_time_1'] as String?;
        DateTime? startDate;
        if (startDt != null) {
          try {
            startDate = DateTime.parse(startDt).toLocal();
          } catch (_) {}
        }
        
        cards.add(_buildActionRequiredCard(
          invite: invite,
          startDate: startDate,
        ));
        
        if (cards.length >= 4) break;
      }
    }

    // 3️⃣ Role-aware: Admin-only, games needing confirmation
    if (cards.length < 4 && _controller.adminTeams.isNotEmpty) {
      final adminTeamIds = _controller.adminTeams.map((t) => t['id'] as String).toList();
      final pendingInvites = _controller.teamVsTeamInvites
          .where((inv) {
            final targetTeamId = inv['target_team_id'] as String?;
            final status = inv['status'] as String?;
            return targetTeamId != null && 
                   adminTeamIds.contains(targetTeamId) && 
                   status == 'pending';
          })
          .take(4 - cards.length)
          .toList();
      
      for (final invite in pendingInvites) {
        final req = invite['request'] as Map<String, dynamic>?;
        if (req == null) continue;
        
        cards.add(_buildRoleAwareCard(
          invite: invite,
        ));
        
        if (cards.length >= 4) break;
      }
    }

    // 4️⃣ Geo-aware: Nearby games starting soon (within 45 mins)
    if (cards.length < 4) {
      for (final match in _controller.discoveryPickupMatches) {
        final startDt = match['start_time'] as DateTime?;
        if (startDt == null) continue;
        
        final timeUntil = startDt.difference(now);
        if (timeUntil.isNegative || timeUntil.inMinutes > 45) continue;
        
        final sport = match['sport'] as String? ?? '';
        final sportEmoji = _getSportEmoji(sport);
        
        cards.add(_buildGeoAwareCard(
          sportEmoji: sportEmoji,
          sport: sport,
          timeUntil: timeUntil,
          match: match,
        ));
        
        if (cards.length >= 4) break;
      }
    }

    return cards;
  }

  Widget _buildUrgencyCard({
    required String sportEmoji,
    required String sport,
    required int spotsLeft,
    required Map<String, dynamic> match,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.red.shade50,
      child: ListTile(
        leading: Text(sportEmoji, style: const TextStyle(fontSize: 24)),
        title: Text(
          '${_displaySport(sport)} tonight — $spotsLeft ${spotsLeft == 1 ? 'spot' : 'spots'} left',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: ElevatedButton(
          onPressed: () {
            _controller.selectedIndex = 1; // Discover tab
            setState(() {});
          },
          child: const Text('Join Now'),
        ),
      ),
    );
  }

  Widget _buildActionRequiredCard({
    required Map<String, dynamic> invite,
    DateTime? startDate,
  }) {
    final req = invite['request'] as Map<String, dynamic>?;
    final sport = req?['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    final tomorrow = startDate != null && 
                     startDate.day == DateTime.now().add(const Duration(days: 1)).day;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.orange.shade50,
      child: ListTile(
        leading: Text(sportEmoji, style: const TextStyle(fontSize: 24)),
        title: Text(
          tomorrow ? 'Tomorrow — waiting approval' : 'Waiting approval',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('You created/requested this game'),
        trailing: ElevatedButton(
          onPressed: () {
            _controller.selectedIndex = 2; // My Games tab
            setState(() {});
          },
          child: const Text('View Request'),
        ),
      ),
    );
  }

  Widget _buildRoleAwareCard({
    required Map<String, dynamic> invite,
  }) {
    final req = invite['request'] as Map<String, dynamic>?;
    final sport = req?['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.blue.shade50,
      child: ListTile(
        leading: const Text('🛡', style: TextStyle(fontSize: 24)),
        title: const Text(
          'Team Admin — confirm opponent',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${_displaySport(sport)} match needs your action'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () {
                _controller.selectedIndex = 2; // My Games tab
                setState(() {});
              },
              child: const Text('Confirm'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: () {
                _controller.selectedIndex = 2; // My Games tab
                setState(() {});
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeoAwareCard({
    required String sportEmoji,
    required String sport,
    required Duration timeUntil,
    required Map<String, dynamic> match,
  }) {
    final minutes = timeUntil.inMinutes;
    final timeText = minutes <= 0 
        ? 'starting now' 
        : minutes == 1 
            ? 'starting in 1 min' 
            : 'starting in $minutes mins';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.green.shade50,
      child: ListTile(
        leading: const Text('📍', style: TextStyle(fontSize: 24)),
        title: Text(
          'Nearby game $timeText',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${_displaySport(sport)} match nearby'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: () {
                _controller.selectedIndex = 1; // Discover tab
                setState(() {});
              },
              child: const Text('Navigate'),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () {
                _controller.selectedIndex = 1; // Discover tab
                setState(() {});
              },
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getSportEmoji(String sport) {
    final lower = sport.toLowerCase();
    if (lower.contains('soccer') || lower.contains('football')) return '⚽';
    if (lower.contains('basketball')) return '🏀';
    if (lower.contains('tennis')) return '🎾';
    if (lower.contains('volleyball')) return '🏐';
    if (lower.contains('cricket')) return '🏏';
    if (lower.contains('badminton')) return '🏸';
    return '🏃';
  }
  
  // [ Sponsored / Monetization ] Section
  Widget _buildSponsoredSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sponsored / Monetization',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.amber.shade50,
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: const Text('Featured Venue', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Premium location spotlight'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Show featured venues
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.orange.shade50,
          child: ListTile(
            leading: const Icon(Icons.local_fire_department, color: Colors.orange),
            title: const Text('Paid Highlighted Game', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Promoted match'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Show highlighted games
            },
          ),
        ),
      ],
    );
  }
  
  // [ Pending Games ] Section (expanded with details)
  Widget _buildPendingGamesSection() {
    final pendingInvites = _controller.teamVsTeamInvites
        .where((inv) => inv['status'] == 'pending')
        .toList();
    final pendingAdminMatches = _controller.pendingTeamMatchesForAdmin;
    final friendsOnlyGames = _controller.friendsOnlyIndividualGames;
    final pendingAvailabilityGames =
        _controller.pendingAvailabilityTeamMatches;

    if (pendingInvites.isEmpty &&
        pendingAdminMatches.isEmpty &&
        friendsOnlyGames.isEmpty &&
        pendingAvailabilityGames.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No pending games',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pending Games',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        
        // Pending Team Invites
        ...pendingInvites.map((invite) => _buildPendingInviteCard(invite)),
        
        // Pending Admin Matches (can approve)
        ...pendingAdminMatches.map((match) => _buildPendingAdminMatchCard(match)),
        
        // Friends-only Individual Games
        ...friendsOnlyGames.map((game) => _buildFriendsOnlyGameCard(game)),

        // Confirmed Team Games where MY availability is pending
        ...pendingAvailabilityGames
            .map((game) => _buildPendingAvailabilityTeamCard(game)),
      ],
    );
  }

  Widget _buildPendingInviteCard(Map<String, dynamic> invite) {
    final req = invite['base_request'] as Map<String, dynamic>?;
    if (req == null) return const SizedBox.shrink();

    final sport = req['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    final startTime1 = req['start_time_1'] as String?;
    final startTime2 = req['start_time_2'] as String?;
    final venue = req['venue'] as String?;
    final teamId = req['team_id'] as String?;
    
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

    String? teamName;
    if (teamId != null) {
      final team = _controller.adminTeams.firstWhere(
        (t) => t['id'] == teamId,
        orElse: () => <String, dynamic>{},
      );
      teamName = team['name'] as String?;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(sportEmoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_displaySport(sport)} - Team Invite',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (teamName != null)
                        Text(
                          'Your team: $teamName',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (startDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (startDt != null && endDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatTime(startDt)} - ${_formatTime(endDt)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (venue != null && venue.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      venue,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await _controller.denyInvite(invite);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite denied')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to deny: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Deny'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _controller.approveInvite(invite);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite approved')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to approve: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingAdminMatchCard(Map<String, dynamic> match) {
    final req = match['request'] as Map<String, dynamic>?;
    final team = match['team'] as Map<String, dynamic>?;
    if (req == null || team == null) return const SizedBox.shrink();

    final sport = req['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    final teamName = team['name'] as String? ?? 'Unknown Team';
    final startTime1 = req['start_time_1'] as String?;
    final startTime2 = req['start_time_2'] as String?;
    final venue = req['venue'] as String?;
    
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(sportEmoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Team Match - Admin Approval',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Requesting team: $teamName',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (startDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (startDt != null && endDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatTime(startDt)} - ${_formatTime(endDt)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (venue != null && venue.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      venue,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    // TODO: Implement deny for admin matches
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Deny functionality coming soon')),
                    );
                  },
                  child: const Text('Deny'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    // Find matching admin team for this sport
                    final req = match['request'] as Map<String, dynamic>?;
                    if (req == null) return;
                    
                    final sport = req['sport'] as String?;
                    if (sport == null) return;
                    
                    // Find admin team with same sport
                    final matchingTeam = _controller.adminTeams.firstWhere(
                      (t) => (t['sport'] as String? ?? '').toLowerCase() == sport.toLowerCase(),
                      orElse: () => <String, dynamic>{},
                    );
                    
                    if (matchingTeam.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No admin team found for this sport')),
                      );
                      return;
                    }
                    
                    final requestId = req['id'] as String?;
                    final teamId = matchingTeam['id'] as String?;
                    if (requestId == null || teamId == null) return;
                    
                    try {
                      await _controller.acceptPendingAdminMatch(
                        requestId: requestId,
                        myAdminTeamId: teamId,
                      );
                      // Reload pending games to refresh the list
                      await _controller.loadPendingGamesForAdmin();
                      if (mounted) {
                        setState(() {}); // Refresh UI
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Match request accepted')),
                        );
                      }
                    } catch (e) {
                      final errorMsg = e.toString();
                      if (mounted) {
                        // Show friendly message for "already exists" error
                        if (errorMsg.contains('Invite already exists') || 
                            errorMsg.contains('already exists')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('This match has already been accepted'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          // Refresh the list to remove the duplicate
                          await _controller.loadPendingGamesForAdmin();
                          setState(() {});
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to accept: $e')),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsOnlyGameCard(Map<String, dynamic> game) {
    final req = game['request'] as Map<String, dynamic>?;
    final creator = game['creator'] as Map<String, dynamic>?;
    if (req == null) return const SizedBox.shrink();

    final sport = req['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    final creatorName = creator?['full_name'] as String? ?? 'Friend';
    final numPlayers = req['num_players'] as int?;
    final startTime1 = req['start_time_1'] as String?;
    final venue = req['venue'] as String?;
    
    DateTime? startDt;
    if (startTime1 != null) {
      try {
        startDt = DateTime.parse(startTime1).toLocal();
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(sportEmoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_displaySport(sport)} - Friends Only',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Created by: $creatorName',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (numPlayers != null) ...[
              Row(
                children: [
                  const Icon(Icons.people, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Players needed: $numPlayers',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (startDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')} ${_formatTime(startDt)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (venue != null && venue.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      venue,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    // For friends-only games, "deny" means hide/ignore
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Game hidden')),
                    );
                  },
                  child: const Text('Ignore'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    // Navigate to Discover tab to see full details and join
                    _controller.selectedIndex = 1;
                    setState(() {});
                  },
                  child: const Text('View Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Availability card for confirmed team games where my attendance is pending
  Widget _buildPendingAvailabilityTeamCard(Map<String, dynamic> game) {
    final sport = game['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    final teamAName = game['team_a_name'] as String? ?? 'Team A';
    final teamBName = game['team_b_name'] as String?;
    final myTeamId = game['my_team_id'] as String?;
    final myStatus = (game['my_status'] as String? ?? 'pending').toLowerCase();
    final isConfirmed = game['is_confirmed'] as bool? ?? false;

    final startDt = game['start_time'] as DateTime?;
    final endDt = game['end_time'] as DateTime?;
    final venue = game['venue'] as String?;

    final isOnTeamA = myTeamId == game['team_a_id'];
    final myTeamName = isOnTeamA ? teamAName : (teamBName ?? 'Opponent Team');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(sportEmoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_displaySport(sport)} • Team Match',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isConfirmed
                            ? 'You are in: $myTeamName'
                            : 'You are in: $myTeamName • Waiting for opponent',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '⏳ Awaiting your response',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (venue != null && venue.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      venue,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            if (startDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (startDt != null && endDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatTime(startDt)} - ${_formatTime(endDt)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final requestId = game['request_id'] as String?;
                    final teamId = myTeamId;
                    if (requestId == null || teamId == null) return;

                    await _setAvailability(
                      requestId: requestId,
                      teamId: teamId,
                      status: 'declined',
                    );
                  },
                  child: const Text('Not available'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final requestId = game['request_id'] as String?;
                    final teamId = myTeamId;
                    if (requestId == null || teamId == null) return;

                    await _setAvailability(
                      requestId: requestId,
                      teamId: teamId,
                      status: 'accepted',
                    );
                  },
                  child: const Text('Available'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAvailability({
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
      // setMyAttendance already refreshes confirmed matches and pending availability
      // Just refresh the UI
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'accepted'
                  ? 'Availability set to Available'
                  : 'Availability set to Not available',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update availability: $e')),
        );
      }
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  // [ My Games Preview ] Section
  Widget _buildMyGamesPreviewSection() {
    final confirmedCount = _controller.confirmedTeamMatches.length;
    
    // Calculate pending count:
    // 1. Existing team invites (pending)
    final existingPendingInvites = _controller.teamVsTeamInvites
        .where((inv) => inv['status'] == 'pending')
        .length;
    
    // 2. Team matches where user is admin and can approve (within 75 miles, same sport)
    final pendingAdminMatches = _controller.pendingTeamMatchesForAdmin.length;
    
    // 3. Individual games from friends that are "friends_only"
    final friendsOnlyGames = _controller.friendsOnlyIndividualGames.length;
    
    // 4. Confirmed team games where user's attendance is pending
    final pendingAvailabilityTeamMatches = _controller.pendingAvailabilityTeamMatches.length;
    
    final pendingCount = existingPendingInvites + 
        pendingAdminMatches + 
        friendsOnlyGames + 
        pendingAvailabilityTeamMatches;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'My Games Preview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Text('Confirmed – $confirmedCount'),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        _controller.selectedIndex = 2; // My Games tab
                        setState(() {});
                      },
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pending, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text('Pending – $pendingCount'),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _pendingGamesExpanded = !_pendingGamesExpanded;
                        });
                      },
                      child: Text(_pendingGamesExpanded ? 'Hide' : 'View All'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
    // Load all matches when tab is opened (if not already loaded or loading)
    if (_controller.allMyMatches.isEmpty && !_controller.loadingAllMatches) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.loadAllMyMatches();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(''), // Empty title since tab already says "My Games"
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _controller.loadAllMyMatches();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            return Stack(
              children: [
                ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8),
                  children: [
                    _errorBanner(),
                    const SizedBox(height: 60), // Space for the filter banner
                    _buildFilteredMatchesSection(),
                    const SizedBox(height: 24),
                  ],
                ),
                // Position filter banner in top right
                Positioned(
                  top: 8,
                  right: 16,
                  child: _buildMyGamesFilterBanner(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMyGamesFilterBanner() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320), // Limit width to keep it compact
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilterSegment('Current', _myGamesFilter == 'Current'),
          _buildFilterSegment('Past', _myGamesFilter == 'Past'),
          _buildFilterSegment('Cancelled', _myGamesFilter == 'Cancelled'),
          _buildFilterSegment('Hidden', _myGamesFilter == 'Hidden'),
        ],
      ),
    );
  }

  Widget _buildFilterSegment(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _myGamesFilter = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C5CE7) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 11,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredMatchesSection() {
    if (_controller.loadingAllMatches) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final filteredMatches = _getFilteredMatches();

    if (filteredMatches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _getEmptyMessage(),
          style: const TextStyle(fontSize: 14, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return _buildMatchesList(filteredMatches);
  }

  List<Map<String, dynamic>> _getFilteredMatches() {
    final now = DateTime.now();
    // Compare dates only (ignore time) for more accurate filtering
    final today = DateTime(now.year, now.month, now.day);
    final hiddenIds = _controller.hiddenRequestIds;

    // Use allMyMatches if available, otherwise fall back to confirmedTeamMatches
    final matchesToFilter = _controller.allMyMatches.isNotEmpty
        ? _controller.allMyMatches
        : _controller.confirmedTeamMatches;

    if (kDebugMode) {
      print('[DEBUG] _getFilteredMatches: Filter=$_myGamesFilter, allMyMatches=${_controller.allMyMatches.length}, confirmedTeamMatches=${_controller.confirmedTeamMatches.length}, using=${matchesToFilter.length}');
    }

    return matchesToFilter.where((match) {
      final status = (match['status'] as String?)?.toLowerCase() ?? '';
      final startTime = match['start_time'] as DateTime?;
      final requestId = match['request_id'] as String;
      final isHidden = hiddenIds.contains(requestId);

      if (kDebugMode && _myGamesFilter == 'Current') {
        final rawStatus = match['status'];
        if (rawStatus == null || rawStatus == '') {
          print('[DEBUG] WARNING: Match $requestId has empty/null status. Raw value: $rawStatus');
        }
      }

      // Compare dates only (ignore time)
      DateTime? matchDate;
      if (startTime != null) {
        matchDate = DateTime(startTime.year, startTime.month, startTime.day);
      }

      switch (_myGamesFilter) {
        case 'Current':
          // Active games (accepted/denied), current/future dates, not cancelled, not hidden
          final isCancelled = status == 'cancelled';
          final isCurrent = !isCancelled &&
              !isHidden &&
              matchDate != null &&
              (matchDate.isAfter(today) || matchDate.isAtSameMomentAs(today));
          
          if (kDebugMode) {
            if (isCancelled) {
              print('[DEBUG] Excluding cancelled match from Current: $requestId, status=$status');
            } else if (isCurrent) {
              print('[DEBUG] Current match: $requestId, status=$status, date=$matchDate, hidden=$isHidden');
            }
          }
          
          return isCurrent;

        case 'Past':
          // Any event date that is past the current system date
          return matchDate != null && matchDate.isBefore(today);

        case 'Cancelled':
          // Organizer cancelled games
          return status == 'cancelled';

        case 'Hidden':
          // Current/future matches where you either accepted/denied, should display under hidden
          return isHidden &&
              matchDate != null &&
              (matchDate.isAfter(today) || matchDate.isAtSameMomentAs(today));

        default:
          return false;
      }
    }).toList();
  }

  String _getEmptyMessage() {
    switch (_myGamesFilter) {
      case 'Current':
        return 'You don\'t have any current games.';
      case 'Past':
        return 'You don\'t have any past games.';
      case 'Cancelled':
        return 'You don\'t have any cancelled games.';
      case 'Hidden':
        return 'You don\'t have any hidden games.';
      default:
        return 'No games found.';
    }
  }

  Widget _buildMatchesList(List<Map<String, dynamic>> matches) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your games (${matches.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...matches.map((m) => _buildMatchCardForFilter(m)),
        ],
      ),
    );
  }

  Widget _buildMatchCardForFilter(Map<String, dynamic> match) {
    // Use the full card implementation for Current and Hidden tabs (today/future matches)
    final startTime = match['start_time'] as DateTime?;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? matchDate;
    if (startTime != null) {
      matchDate = DateTime(startTime.year, startTime.month, startTime.day);
    }
    final isTodayOrFuture = matchDate != null && 
        (matchDate.isAfter(today) || matchDate.isAtSameMomentAs(today));
    
    // For Current and Hidden tabs with today/future matches, show full card
    if ((_myGamesFilter == 'Current' || _myGamesFilter == 'Hidden') && isTodayOrFuture) {
      return _buildFullMatchCard(match);
    }
    
    // For Past and Cancelled tabs, show simplified card
    return _buildMatchCardFromData(match);
  }

  Widget _buildFullMatchCard(Map<String, dynamic> match) {
    // Full card implementation with all features (Available, Not available, team percentage, players, switch, etc.)
    final reqId = match['request_id'] as String;
    final teamAId = match['team_a_id'] as String?;
    final teamBId = match['team_b_id'] as String?;
    final teamAName = match['team_a_name'] as String? ?? 'Team A';
    final teamBName = match['team_b_name'] as String? ?? 'Team B';
    final sport = match['sport'] as String? ?? '';
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final venue = match['venue'] as String?;
    final canSwitchSide = (match['can_switch_side'] as bool?) ?? false;

    final teamAPlayers =
        (match['team_a_players'] as List?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];
    final teamBPlayers =
        (match['team_b_players'] as List?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];

    final uid = _controller.currentUserId;

    // Get user's attendance status (from RPC result or fallback to team players)
    final myAttendanceStatus = (match['my_attendance_status'] as String?)?.toLowerCase() ??
        teamAPlayers
            .where((p) => p['user_id'] == uid)
            .map((p) => (p['status'] as String?)?.toLowerCase())
            .firstWhere((x) => x != null, orElse: () => null) ??
        teamBPlayers
            .where((p) => p['user_id'] == uid)
            .map((p) => (p['status'] as String?)?.toLowerCase())
            .firstWhere((x) => x != null, orElse: () => 'accepted');

    final myStatusA = teamAPlayers
        .where((p) => p['user_id'] == uid)
        .map((p) => p['status'] as String?)
        .firstWhere((x) => x != null, orElse: () => null);
    final myStatusB = teamBPlayers
        .where((p) => p['user_id'] == uid)
        .map((p) => p['status'] as String?)
        .firstWhere((x) => x != null, orElse: () => null);

    final myTeamId = match['my_team_id'] as String? ??
        (myStatusA != null
            ? teamAId
            : (myStatusB != null ? teamBId : teamAId));
    
    final isDeclined = myAttendanceStatus == 'declined';

    final aCounts = _statusCounts(teamAPlayers);
    final bCounts = _statusCounts(teamBPlayers);

    final isOrganizer = _controller.isOrganizerForMatch(match);
    final canSendReminder = _controller.canSendReminderForMatch(match);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: isDeclined ? Colors.grey.shade100 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '$teamAName vs $teamBName',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      if (isDeclined) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Not Available',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Game Level Status Bar on the right
                Builder(
                  builder: (context) {
                    // Use match-specific value if exists, otherwise use sport default
                    final matchSpecific = match['expected_players_per_team'] as int?;
                    
                    return FutureBuilder<int>(
                      future: matchSpecific != null 
                          ? Future.value(matchSpecific)
                          : SportDefaults.getExpectedPlayersPerTeam(sport),
                      builder: (context, snapshot) {
                        final expectedPlayersPerTeam = snapshot.data ?? 11;
                    final teamAPercentage = _calculatePercentage(aCounts['accepted']!, expectedPlayersPerTeam);
                    final teamBPercentage = _calculatePercentage(bCounts['accepted']!, expectedPlayersPerTeam);
                    final gamePercentage = (teamAPercentage + teamBPercentage) / 2.0;
                    final pct = gamePercentage.clamp(0.0, 1.0);
                    final percentageText = '${(pct * 100).round()}%';
                    
                    // Get color for the percentage
                    Color getColor(double pct) {
                      final clamped = pct.clamp(0.0, 1.0);
                      if (clamped <= 0.5) {
                        final ratio = clamped * 2;
                        return Color.lerp(Colors.red, Colors.orange, ratio)!;
                      } else {
                        final ratio = (clamped - 0.5) * 2;
                        return Color.lerp(Colors.orange, Colors.green, ratio)!;
                      }
                    }
                    final color = getColor(pct);
                    
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Stack(
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: pct,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          percentageText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    );
                      },
                    );
                  },
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'hide') {
                      await _confirmHideGame(reqId);
                    } else if (v == 'unhide') {
                      await _confirmUnhideGame(reqId);
                    } else if (v == 'edit_players') {
                      await _editExpectedPlayers(match);
                    } else if (v == 'cancel') {
                      await _confirmCancelGame(match);
                    }
                  },
                  itemBuilder: (_) => [
                    // Show "Unhide" in Hidden tab, "Hide" otherwise
                    if (_myGamesFilter == 'Hidden')
                      const PopupMenuItem(
                        value: 'unhide',
                        child: Text('Unhide game'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'hide',
                        child: Text('Hide from My Games'),
                      ),
                    if (isOrganizer) ...[
                      const PopupMenuItem(
                        value: 'edit_players',
                        child: Text('Edit expected players'),
                      ),
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Text('Cancel game (both teams)'),
                      ),
                    ],
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
              style: const TextStyle(fontSize: 13, color: Colors.black87),
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
            
            // Team availability info (without status bars)
            Builder(
              builder: (context) {
                // Use match-specific value if exists, otherwise use sport default
                final matchSpecific = match['expected_players_per_team'] as int?;
                
                return FutureBuilder<int>(
                  future: matchSpecific != null 
                      ? Future.value(matchSpecific)
                      : SportDefaults.getExpectedPlayersPerTeam(sport),
                  builder: (context, snapshot) {
                    final expectedPlayersPerTeam = snapshot.data ?? 11;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Team A info
                        Text(
                          'Team $teamAName: Avail ${aCounts['accepted']}, Not ${aCounts['declined']}, Pending ${aCounts['pending']}',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        // Team B info
                        Text(
                          'Team $teamBName: Avail ${bCounts['accepted']}, Not ${bCounts['declined']}, Pending ${bCounts['pending']}',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(height: 12),
                      ],
                    );
                  },
                );
              },
            ),
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
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchCardFromData(Map<String, dynamic> match) {
    // This will be similar to the card in _buildConfirmedMatchesSection
    // but simplified for the filter view
    final reqId = match['request_id'] as String;
    final teamAName = match['team_a_name'] as String? ?? 'Team A';
    final teamBName = match['team_b_name'] as String? ?? 'Team B';
    final sport = match['sport'] as String? ?? '';
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final venue = match['venue'] as String?;
    final status = (match['status'] as String?)?.toLowerCase() ?? '';
    final myAttendanceStatus = (match['my_attendance_status'] as String?)?.toLowerCase() ?? 'accepted';
    final isCancelled = status == 'cancelled';
    final isDeclined = myAttendanceStatus == 'declined';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: isCancelled
          ? Colors.red.shade50
          : (isDeclined ? Colors.grey.shade100 : null),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '$teamAName vs $teamBName',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      if (isCancelled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Cancelled',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else if (isDeclined) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Not Available',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Sport: ${_displaySport(sport)}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              _formatTimeRange(startDt, endDt),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
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
            // Add Unhide button for Hidden tab
            if (_myGamesFilter == 'Hidden') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _confirmUnhideGame(reqId);
                  },
                  icon: const Icon(Icons.visibility),
                  label: const Text('Unhide game'),
                ),
              ),
            ],
          ],
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
        return DiscoverScreen(
          controller: _controller,
          onCreateGame: _showCreateInstantMatchSheet,
        );
      case 2:
        return _buildMyGamesTab();
      case 3:
        return ChatScreen(controller: _controller);
      case 4:
        return const UserProfileScreen();
      default:
        return _buildHomeTab();
    }
  }

  void _onItemTapped(int index) {
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
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_filled),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.explore),
                label: 'Discover',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.sports_esports),
                label: 'My Games',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline),
                label: 'Chat',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}
