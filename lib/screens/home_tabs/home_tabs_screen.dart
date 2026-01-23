import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../user_profile_screen.dart';
import '../teams_screen.dart';
import '../team_profile_screen.dart';
import '../discover_screen.dart';
import '../chat_screen.dart';
import '../create_game_screen.dart';
import '../game_chat_screen.dart';
import 'home_tabs_controller.dart';
import '../../widgets/status_bar.dart';
import '../../widgets/location_picker_dialog.dart';
import '../../utils/sport_defaults.dart';
import '../../services/location_service.dart';

class HomeTabsScreen extends StatefulWidget {
  const HomeTabsScreen({super.key});

  @override
  State<HomeTabsScreen> createState() => _HomeTabsScreenState();
}

class _HomeTabsScreenState extends State<HomeTabsScreen> {
  late final HomeTabsController _controller;
  bool _initDone = false;
  String _myGamesFilter = 'Current'; // 'Current', 'Past', 'Cancelled', 'Hidden'
  final Set<String> _expandedMatchIds = {}; // Track which matches are expanded
  final Set<String> _expandedSportSections = {}; // Track which sport sections are expanded
  String? _currentLocation; // Profile home location or manual location display
  bool _loadingLocation = false;
  
  // Discover section filters (matching DiscoverScreen)
  String? _selectedSportFilter; // null = all sports
  DateTime? _selectedDateFilter; // DateTime for date filter, null = any date
  int _maxDistance = 100; // miles, default 100 (100 = any distance)
  bool _nearbyFilterActive = false; // Toggle for nearby filter (when true, uses _maxDistance)

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
    // Load location immediately, don't wait for controller init
    _loadCurrentLocation();
    _init();
  }

  Future<void> _init() async {
    await _controller.init();
    if (!mounted) return;

    setState(() => _initDone = true);
  }

  Future<void> _loadCurrentLocation() async {
    if (_loadingLocation) return;
    
    setState(() {
      _loadingLocation = true;
    });

    try {
      if (kDebugMode) {
        print('[HomeTabsScreen] Loading location from profile only');
      }
      
      // Only use profile home location - no device location, no API calls
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user != null) {
        final result = await supa
            .from('users')
            .select('home_city, home_state, home_zip_code')
            .eq('id', user.id)
            .maybeSingle();
        
        // Use home_city and home_state directly (fastest, no API call)
        final homeCity = result?['home_city'] as String?;
        final homeState = result?['home_state'] as String?;
        if (homeCity != null && homeState != null && 
            homeCity.isNotEmpty && homeState.isNotEmpty) {
          final cityState = '$homeCity, $homeState';
          if (kDebugMode) {
            print('[HomeTabsScreen] Using home location from profile: $cityState');
          }
          if (mounted) {
            setState(() {
              _currentLocation = cityState;
              _loadingLocation = false;
            });
          }
          return;
        }
        
        // If no city/state, try to convert home_zip_code (only if available)
        final homeZip = result?['home_zip_code'] as String?;
        if (homeZip != null && homeZip.isNotEmpty) {
          if (kDebugMode) {
            print('[HomeTabsScreen] Converting home ZIP to city/state: $homeZip');
          }
          final cityState = await LocationService.getCityStateFromZip(homeZip);
          if (cityState != null && mounted) {
            setState(() {
              _currentLocation = cityState;
              _loadingLocation = false;
            });
            return;
          }
        }
      }
      
      // If no profile location found, show placeholder
      if (mounted) {
        setState(() {
          _currentLocation = 'Set Location';
          _loadingLocation = false;
        });
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('[HomeTabsScreen] Error loading location from profile: $e');
      }
      
      if (mounted) {
        setState(() {
          _currentLocation = 'Set Location';
          _loadingLocation = false;
        });
      }
    }
  }

  Future<void> _showLocationPicker() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const LocationPickerDialog(),
    );

    // If location was changed, reload it and refresh discovery matches
    if (result == true) {
      await _loadCurrentLocation();
      
      // Reload discovery matches with new location for accurate distance calculation
      // Force refresh to clear cache since location changed
      if (mounted) {
        _controller.clearDiscoveryCache(); // Clear cache before reloading
        await _controller.loadDiscoveryPickupMatches(forceRefresh: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location updated')),
        );
      }
    }
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
  
  Future<void> _showLeaveGameDialog(String requestId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text(
          'This will mark you as "Not Available" and you will no longer be part of this game.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Leave Game'),
          ),
        ],
      ),
    );

    if (ok == true) {
      // Mark user as declined for this game
      final myTeamId = _controller.allMyMatches
          .firstWhere((m) => m['request_id'] == requestId, 
                     orElse: () => {'my_team_id': null})['my_team_id'] as String?;
      
      if (myTeamId != null) {
        await _vote(requestId: requestId, teamId: myTeamId, status: 'declined');
      }
      
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have left the game')),
      );
    }
  }
  
  Future<void> _enableChat(String requestId, {required bool enabled}) async {
    try {
      final supa = Supabase.instance.client;
      await supa
          .from('instant_match_requests')
          .update({
            'chat_enabled': enabled,
            'last_updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', requestId);
      
      // Reload matches to refresh UI
      await _controller.loadAllMyMatches();
      
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'Chat enabled' : 'Chat disabled'),
        ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update chat: $e')),
      );
    }
  }
  
  Future<void> _setChatMode(String requestId, {required String mode}) async {
    try {
      final supa = Supabase.instance.client;
      await supa
          .from('instant_match_requests')
          .update({
            'chat_mode': mode,
            'last_updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', requestId);
      
      // Reload matches to refresh UI
      await _controller.loadAllMyMatches();
      
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mode == 'all_users' 
              ? 'All users can now message' 
              : 'Only admins can message'),
        ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update chat mode: $e')),
      );
    }
  }

  Future<void> _toggleTeamRosterPrivacy(String requestId, Map<String, dynamic> match, {required String team}) async {
    try {
      final teamAId = match['team_a_id'] as String?;
      final teamBId = match['team_b_id'] as String?;
      final teamAName = match['team_a_name'] as String? ?? 'Team A';
      final teamBName = match['team_b_name'] as String? ?? 'Team B';
      
      String fieldName;
      String teamName;
      String opponentName;
      
      if (team == 'a') {
        fieldName = 'show_team_a_roster';
        teamName = teamAName;
        opponentName = teamBName;
      } else {
        fieldName = 'show_team_b_roster';
        teamName = teamBName;
        opponentName = teamAName;
      }
      
      final currentValue = match[fieldName] as bool? ?? false;
      final newValue = !currentValue;
      
      final supa = Supabase.instance.client;
      await supa
          .from('instant_match_requests')
          .update({
            fieldName: newValue,
            'last_updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', requestId);
      
      // Reload matches to refresh the UI
      await _controller.loadAllMyMatches();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue 
                ? '$teamName roster is now visible to $opponentName'
                : '$teamName roster is now hidden from $opponentName (privacy enabled)'
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update roster privacy: $e')),
      );
    }
  }

  /// Get ZIP code from user profile only
  Future<String?> _getDeviceLocationZipForQuickCreate() async {
    // Only use profile home_zip_code - no device location
    try {
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user != null) {
        final result = await supa
            .from('users')
            .select('home_zip_code')
            .eq('id', user.id)
            .maybeSingle();
        
        final homeZip = result?['home_zip_code'] as String?;
        if (homeZip != null && homeZip.isNotEmpty) {
          if (kDebugMode) {
            print('[DEBUG] Using home ZIP from profile for quick game creation: $homeZip');
          }
          return homeZip;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DEBUG] Error getting ZIP from profile: $e');
      }
    }
    
    if (kDebugMode) {
      print('[DEBUG] ⚠️  No ZIP code available from profile');
    }
    return null;
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
                  'zip_code': await _getDeviceLocationZipForQuickCreate(), // Use profile home location or fallback
                  'radius_miles': radiusMiles.toInt(),
                  'proficiency_level': proficiencyLevel,
                  'is_public': isPublic,
                  'visibility': isPublic ? 'public' : 'friends_only',
                  'status': 'open',
                  'start_time_1': startUtc,
                  'start_time_2': endUtc,
                  'last_updated_at': DateTime.now().toUtc().toIso8601String(),
                };

                // Set game_type and game_sub_type based on game type
                if (matchType == 'team') {
                  insertMap['team_id'] = selectedTeamId;
                  // Team games: TEAM/OPEN at creation (DIRECT is set when a team accepts)
                  insertMap['game_type'] = 'TEAM';
                  insertMap['game_sub_type'] = 'OPEN';
                } else {
                  insertMap['num_players'] = numPlayers;
                  // Individual games: determine sub-type based on visibility
                  insertMap['game_type'] = 'IND';
                  if (isPublic) {
                    insertMap['game_sub_type'] = 'PUB';  // Public pick-up game
                  } else {
                    // Private games: Check visibility to determine if friends_group or selected friends
                    // visibility = 'friends_group' means IND/GROUP, 'friends_only' means IND/IND
                    // Note: friends_group_id may be set separately if it's a friends group game
                    insertMap['game_sub_type'] = 'IND';  // Selected friends private game (IND/IND)
                    // If friends_group_id is set later, it will be IND/GROUP
                  }
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

                // Clear discovery cache and reload to show new game (for other users)
                _controller.clearDiscoveryCache();
                await _controller.loadAdminTeamsAndInvites();
                await _controller.loadDiscoveryPickupMatches(forceRefresh: true);
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
              final desc = descCtrl.text.trim();

              if (selectedSport == null || teamName.isEmpty) {
                setSheetState(() {
                  errorText = 'Sport and Team name are required.';
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
            if (st1 is String) {
              final parsed = DateTime.tryParse(st1);
              startDt = parsed?.toLocal();
            }

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateInstantMatchSheet,
        backgroundColor: const Color(0xFF14919B), // Teal color matching app theme
        icon: const Icon(Icons.add_circle_outline, color: Colors.white),
        label: const Text(
          'Create Game',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        onRefresh: () async {
          await _controller.loadUserBasics();
          await _controller.loadAdminTeamsAndInvites();
          await _controller.loadConfirmedTeamMatches();
          await _controller.loadDiscoveryPickupMatches();
          await _controller.loadPendingGamesForAdmin();
          await _controller.loadFriendsOnlyIndividualGames();
          await _controller.loadMyPendingAvailabilityMatches();
          await _controller.loadPendingIndividualGames();
          await _controller.loadIncomingFriendRequests();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          color: const Color(0xFF0D7377), // Dark teal background for entire screen
          child: Column(
            children: [
              // Dark top section with greeting and smart cards
              SafeArea(
                bottom: false, // Don't add bottom padding, let content extend
                top: false, // Don't add top padding, let logo touch top edge
                child: Container(
                color: const Color(0xFF0D7377), // Dark teal background (logo color)
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // No top padding - logo touches top edge
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _errorBanner(),
                      if (_controller.lastError != null) const SizedBox(height: 8), // Reduced from 12
                    
                      // Greeting Section - aligned to top
                    _buildGreetingSection(),
                    const SizedBox(height: 20),
                    
                    // Smart Cards (replaces Join/Create Game section)
                    _buildSmartCardsInDarkSection(),
                  ],
                ),
              ),
              ),
              // [ Trending Games ] Section - Chip/card extending to bottom with teal side borders
                _buildDiscoverSectionContent(),
            ],
            ),
          ),
        ),
      ),
    );
  }
  
  // [ Greeting ] Section - Modern banner with profile pic (dark theme)
  Widget _buildGreetingSection() {
    final fullName = _controller.userName ?? 'User';
    // Extract first name only
    final firstName = fullName.split(' ').first;
    final location = _currentLocation ?? (_loadingLocation ? 'Loading...' : 'Location');
    final photoUrl = _controller.userPhotoUrl;
    
    // Get safe area insets for all devices (iOS notch, Android status bar, etc.)
    final safeAreaTop = MediaQuery.of(context).padding.top;
    
    return Padding(
      padding: EdgeInsets.only(top: safeAreaTop), // Respect safe area on all devices
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile Picture
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const UserProfileScreen(),
              ),
            );
          },
          child: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[700],
            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                ? NetworkImage(photoUrl)
                : null,
            child: photoUrl == null || photoUrl.isEmpty
                ? const Icon(Icons.person, size: 28, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        
                // Name and Location column with Search icon positioned between them
        Expanded(
                  child: Stack(
                    children: [
                      Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                          // User Name (first name only)
              Text(
                            firstName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                          const SizedBox(height: 12),
                          // Location (City, State) on the row below
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              // Location (tappable) - below name
                  InkWell(
                    onTap: _showLocationPicker,
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          location,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
                      // Search icon positioned on the right, vertically centered between Name and City
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: InkWell(
                            onTap: _showSearchDialog,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.search,
                                color: Colors.white.withOpacity(0.7),
                                size: 24, // Increased size
                              ),
                            ),
                          ),
          ),
        ),
      ],
                  ),
                ),
              ],
      ),
    );
  }
  
  // Search Dialog for person/team within 100 miles
  Future<void> _showSearchDialog() async {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;
    String selectedTab = 'Players'; // 'Players' or 'Teams'
    String? userZipCode;

    // Get user's ZIP code for distance calculation
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user != null) {
      final userData = await supa
          .from('users')
          .select('home_zip_code')
          .eq('id', user.id)
          .maybeSingle();
      userZipCode = userData?['home_zip_code'] as String?;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> performSearch() async {
            final query = searchController.text.trim();
            if (query.isEmpty) {
              setSheetState(() {
                searchResults = [];
                isSearching = false;
              });
              return;
            }

            setSheetState(() => isSearching = true);

            try {
              if (selectedTab == 'Players') {
                // Search for players
                final users = await supa
                    .from('users')
                    .select('id, full_name, photo_url, home_zip_code, base_zip_code')
                    .ilike('full_name', '%$query%')
                    .limit(50);

                List<Map<String, dynamic>> results = [];
                if (users is List) {
                  for (final userData in users) {
                    final zipCode = userData['home_zip_code'] as String? ?? 
                                   userData['base_zip_code'] as String?;
                    
                    // Filter by distance if user has ZIP code
                    if (userZipCode != null && zipCode != null && zipCode.isNotEmpty) {
                      final distance = await LocationService.calculateDistanceBetweenZipCodes(
                        zip1: userZipCode,
                        zip2: zipCode,
                      );
                      if (distance != null && distance <= 100) {
                        results.add({
                          'type': 'player',
                          'id': userData['id'],
                          'name': userData['full_name'] ?? 'Unknown',
                          'photo_url': userData['photo_url'],
                          'zip_code': zipCode,
                          'distance': distance,
                        });
                      }
                    } else {
                      // Include if no ZIP code (show all)
                      results.add({
                        'type': 'player',
                        'id': userData['id'],
                        'name': userData['full_name'] ?? 'Unknown',
                        'photo_url': userData['photo_url'],
                        'zip_code': zipCode,
                        'distance': null,
                      });
                    }
                  }
                }

                // Sort by distance (nulls last)
                results.sort((a, b) {
                  final distA = a['distance'] as double?;
                  final distB = b['distance'] as double?;
                  if (distA == null && distB == null) return 0;
                  if (distA == null) return 1;
                  if (distB == null) return -1;
                  return distA.compareTo(distB);
                });

                setSheetState(() {
                  searchResults = results;
                  isSearching = false;
                });
              } else {
                // Search for teams
                final teams = await supa
                    .from('teams')
                    .select('id, name, sport, zip_code')
                    .ilike('name', '%$query%')
                    .limit(50);

                List<Map<String, dynamic>> results = [];
                if (teams is List) {
                  for (final teamData in teams) {
                    final zipCode = teamData['zip_code'] as String?;
                    
                    // Filter by distance if user has ZIP code
                    if (userZipCode != null && zipCode != null && zipCode.isNotEmpty) {
                      final distance = await LocationService.calculateDistanceBetweenZipCodes(
                        zip1: userZipCode,
                        zip2: zipCode,
                      );
                      if (distance != null && distance <= 100) {
                        results.add({
                          'type': 'team',
                          'id': teamData['id'],
                          'name': teamData['name'] ?? 'Unknown',
                          'sport': teamData['sport'],
                          'zip_code': zipCode,
                          'distance': distance,
                        });
                      }
                    } else {
                      // Include if no ZIP code (show all)
                      results.add({
                        'type': 'team',
                        'id': teamData['id'],
                        'name': teamData['name'] ?? 'Unknown',
                        'sport': teamData['sport'],
                        'zip_code': zipCode,
                        'distance': null,
                      });
                    }
                  }
                }

                // Sort by distance (nulls last)
                results.sort((a, b) {
                  final distA = a['distance'] as double?;
                  final distB = b['distance'] as double?;
                  if (distA == null && distB == null) return 0;
                  if (distA == null) return 1;
                  if (distB == null) return -1;
                  return distA.compareTo(distB);
                });

                setSheetState(() {
                  searchResults = results;
                  isSearching = false;
                });
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Search failed: $e')),
                );
              }
              setSheetState(() {
                searchResults = [];
                isSearching = false;
              });
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
          children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Search Players & Teams',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  
                  // Search field (larger when opened)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: searchController,
              autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search by name...',
                        hintStyle: const TextStyle(
                          color: Colors.black54,
                          fontSize: 16,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.black54,
                        ),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.black54),
                                onPressed: () {
                                  searchController.clear();
                                  setSheetState(() {
                                    searchResults = [];
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                      ),
                      onChanged: (value) {
                        setSheetState(() {});
                        if (value.length >= 2) {
                          performSearch();
                        } else {
                          setSheetState(() => searchResults = []);
                        }
                      },
                    ),
                  ),

                  // Tab selector
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              selectedTab = 'Players';
                              searchResults = [];
                            });
                            if (searchController.text.length >= 2) {
                              performSearch();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selectedTab == 'Players' 
                                  ? Colors.orange.shade100 
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: selectedTab == 'Players' 
                                      ? Colors.orange 
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              'Players',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: selectedTab == 'Players' 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                                color: selectedTab == 'Players' 
                                    ? Colors.orange 
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              selectedTab = 'Teams';
                              searchResults = [];
                            });
                            if (searchController.text.length >= 2) {
                              performSearch();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selectedTab == 'Teams' 
                                  ? Colors.orange.shade100 
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: selectedTab == 'Teams' 
                                      ? Colors.orange 
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              'Teams',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: selectedTab == 'Teams' 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                                color: selectedTab == 'Teams' 
                                    ? Colors.orange 
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),

                  // Results
                  Expanded(
                    child: isSearching
                        ? const Center(child: CircularProgressIndicator())
                        : searchResults.isEmpty
                            ? Center(
                                child: Text(
                                  searchController.text.isEmpty
                                      ? 'Start typing to search...'
                                      : 'No results found',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final result = searchResults[index];
                                  final isPlayer = result['type'] == 'player';
                                  final distance = result['distance'] as double?;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundImage: isPlayer && 
                                                result['photo_url'] != null &&
                                                (result['photo_url'] as String).isNotEmpty
                                            ? NetworkImage(result['photo_url'] as String)
                                            : null,
                                        child: isPlayer && 
                                                (result['photo_url'] == null || 
                                                 (result['photo_url'] as String).isEmpty)
                                            ? const Icon(Icons.person)
                                            : !isPlayer
                                                ? const Icon(Icons.group)
                                                : null,
                                      ),
                                      title: Text(result['name'] as String? ?? 'Unknown'),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (!isPlayer && result['sport'] != null)
                                            Text('Sport: ${result['sport']}'),
                                          if (distance != null)
                                            Text('${distance.toStringAsFixed(1)} miles away'),
                                        ],
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                Navigator.pop(context);
                                        if (isPlayer) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => UserProfileScreen(
                                                userId: result['id'] as String,
                                              ),
                                            ),
                                          );
                                        } else {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => TeamProfileScreen(
                                                teamId: result['id'] as String,
                                                teamName: result['name'] as String? ?? '',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  // [ Smart Cards ] Section - Replaces Join/Create Game section in dark area
  Widget _buildSmartCardsInDarkSection() {
    final cards = _buildNewSmartCards();
    
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show up to 3 cards with reduced spacing
        ...cards.take(3).map((card) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: card,
        )),
      ],
    );
  }

  List<Widget> _buildNewSmartCards() {
    final cards = <Widget>[];
    
    // Priority 1: Friend requests (highest priority - action required)
    final friendRequests = _controller.incomingFriendRequests;
    if (friendRequests.isNotEmpty) {
      cards.add(_buildFriendRequestsCard(friendRequests));
    }
    
    // Priority 1.5: Team follow requests (high priority - action required)
    final teamFollowRequests = _controller.pendingTeamFollowRequests;
    if (teamFollowRequests.isNotEmpty) {
      cards.add(_buildTeamFollowRequestsCard(teamFollowRequests));
    }
    
    // Priority 2: Profile notifications (team/friends group additions)
    final profileNotifications = _controller.profileNotifications;
    if (profileNotifications.isNotEmpty) {
      cards.add(_buildProfileNotificationsCard(profileNotifications));
    }
    
    // Priority 2: Team/Group invitations (action required)
    // Note: Team/group invitations might be checked separately if there's a pending status
    // For now, this is a placeholder - you may need to query for pending team/group memberships
    // Uncomment and implement if you have a way to detect pending team/group invites:
    /*
    final pendingTeamInvites = 0; // TODO: Query for pending team invitations
    final pendingGroupInvites = 0; // TODO: Query for pending friends group invitations
    if (pendingTeamInvites > 0 || pendingGroupInvites > 0) {
      cards.add(_buildSmartCard(
        message: 'You have been added to ${pendingTeamInvites + pendingGroupInvites > 1 ? 'groups/teams' : 'a group/team'}, please accept.',
                onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TeamsScreen()),
          );
        },
        icon: Icons.group_add,
        color: Colors.red,
      ));
    }
    */
    
    // Priority 3: Games awaiting action (pending admin approval, pending invites, pending join requests)
    final pendingAdminCount = _controller.pendingTeamMatchesForAdmin.length;
    final pendingAvailabilityCount = _controller.pendingAvailabilityTeamMatches.length;
    final pendingIndividualCount = _controller.pendingIndividualGames.length;
    final pendingJoinRequestsCount = _controller.pendingJoinRequestsForMyGames.length;
    final totalPendingAction = pendingAdminCount + pendingAvailabilityCount + pendingIndividualCount + pendingJoinRequestsCount;
    
    if (totalPendingAction > 0) {
      cards.add(_buildPendingActionCard(
        count: totalPendingAction,
        onTap: () {
          _showPendingActionDialog();
        },
      ));
    }
    
    // Priority 4: Confirmed games
    // Use cached count to avoid recalculating and prevent "no games" flash
    // Show loading state if data is still loading
    final isLoading = _controller.loadingConfirmedMatches || _controller.loadingIndividualMatches;
    final confirmedCount = _controller.cachedConfirmedGamesCount ?? 0;
    
    // Only show card if we have a count (either loaded or cached)
    // Don't show "0 games" during initial load to prevent flash
    if (isLoading && confirmedCount == 0) {
      // Still loading, don't show anything yet to prevent "no games" flash
    } else if (confirmedCount > 0) {
      cards.add(_buildSmartCard(
        message: confirmedCount == 1
            ? 'You have 1 confirmed game scheduled and ready to play.'
            : 'You have $confirmedCount confirmed games scheduled and ready to play.',
        onTap: () {
          setState(() => _controller.selectedIndex = 1); // My Games tab (index 1 after Discover was removed)
        },
        icon: Icons.event,
        color: Colors.green,
      ));
    }
    
    // Priority 5: Nearby games (discovery)
    final nearbyGames = _controller.discoveryPickupMatches.length;
    if (nearbyGames > 0 && _currentLocation != null) {
      final locationName = _currentLocation!.split(',').first; // Get city name
      cards.add(_buildSmartCard(
        message: '$nearbyGames ${nearbyGames == 1 ? 'game' : 'games'} near $locationName this week',
        onTap: () {
          setState(() => _controller.selectedIndex = 1); // Discover tab
        },
        icon: Icons.explore,
        color: Colors.purple,
      ));
    }
    
    // Priority 6: Add sports (if user has few or no sports)
    final userSportsCount = _controller.userSports.length;
    if (userSportsCount < 2) {
      cards.add(_buildSmartCard(
        message: 'Add your favorite sports to get better matches',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UserProfileScreen()),
          );
        },
        icon: Icons.add_circle_outline,
        color: Colors.blue,
      ));
    }
    
    // Priority 7: No games yet
    if (confirmedCount == 0 && totalPendingAction == 0) {
      cards.add(_buildSmartCard(
        message: 'No games yet — create one in under 60 seconds',
        onTap: _showCreateInstantMatchSheet,
        icon: Icons.add_circle_outline,
        color: Colors.teal,
      ));
    }
    
    return cards;
  }

  Widget _buildProfileNotificationsCard(List<Map<String, dynamic>> notifications) {
    return Container(
      height: 70,
                  decoration: BoxDecoration(
        color: const Color(0xFF1BA8B5), // Light teal matching the design
                    borderRadius: BorderRadius.circular(12),
                  ),
      child: PageView.builder(
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          final type = notification['type'] as String? ?? '';
          final name = notification['name'] as String? ?? '';
          
          String message;
          IconData icon;
          Color iconColor;
          
          if (type == 'friends_group') {
            final sport = notification['sport'] as String? ?? '';
            if (sport.isNotEmpty) {
              message = 'You have been added to $name, you can maintain and organize $sport games among your group. This is a private group, only people in the group can see.';
            } else {
              message = 'You have been added to $name, you can maintain and organize games among your group. This is a private group, only people in the group can see.';
            }
            icon = Icons.group;
            iconColor = Colors.purple;
          } else {
            // team
            message = 'You have been added to $name, you can participate in games team is playing.';
            icon = Icons.group_work;
            iconColor = Colors.blue;
          }
          
          return InkWell(
            onTap: () {
              // Navigate to teams screen
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TeamsScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                    width: 40,
                    height: 40,
                        decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  
                  // Message
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 13,
                          color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  // Page indicator
                  if (notifications.length > 1) ...[
                    const SizedBox(width: 6),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                          '${index + 1}/${notifications.length}',
                          style: const TextStyle(
                            fontSize: 10,
                                color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            notifications.length,
                            (i) => Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == index
                                    ? Colors.white
                                    : Colors.white38,
                              ),
                            ),
                              ),
                            ),
                          ],
                        ),
                  ],
                      
                      // Arrow
                  const SizedBox(width: 6),
                      const Icon(
                    Icons.chevron_right,
                    color: Colors.white70,
                    size: 18,
                      ),
                    ],
                  ),
                ),
          );
        },
      ),
    );
  }

  Widget _buildFriendRequestsCard(List<Map<String, dynamic>> requests) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35), // Orange color for friend requests
        borderRadius: BorderRadius.circular(12),
      ),
      child: PageView.builder(
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final request = requests[index];
          final requestId = request['request_id'] as String;
          final userId = request['user_id'] as String;
          final userName = request['full_name'] as String? ?? 'Unknown';
          final photoUrl = request['photo_url'] as String?;
          
          return InkWell(
            onTap: () {
              _showFriendRequestDialog(request);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Profile picture or icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      image: photoUrl != null && photoUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(photoUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: photoUrl == null || photoUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.white, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  
                  // Message
                  Expanded(
                    child: Text(
                      requests.length == 1
                          ? '$userName sent you a friend request'
                          : '$userName sent you a friend request (${requests.length} requests)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  // Page indicator
                  if (requests.length > 1) ...[
                    const SizedBox(width: 6),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${index + 1}/${requests.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            requests.length,
                            (i) => Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == index
                                    ? Colors.white
                                    : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  // Arrow
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showFriendRequestDialog(Map<String, dynamic> request) async {
    final requestId = request['request_id'] as String;
    final userId = request['user_id'] as String;
    final userName = request['full_name'] as String? ?? 'Unknown';
    final photoUrl = request['photo_url'] as String?;
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Friend Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (photoUrl != null && photoUrl.isNotEmpty)
              CircleAvatar(
                radius: 30,
                backgroundImage: NetworkImage(photoUrl),
              )
            else
              const CircleAvatar(
                radius: 30,
                child: Icon(Icons.person, size: 30),
              ),
            const SizedBox(height: 12),
            Text('$userName wants to be your friend'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _declineFriendRequest(requestId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _acceptFriendRequest(requestId, userId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptFriendRequest(String requestId, String userId) async {
    final supa = Supabase.instance.client;
    final currentUserId = supa.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Update the incoming request to accepted
      await supa
          .from('friends')
          .update({'status': 'accepted'})
          .eq('id', requestId);

      // Create the reverse friendship (symmetrical)
      await supa.from('friends').upsert({
        'user_id': currentUserId,
        'friend_id': userId,
        'status': 'accepted',
      }, onConflict: 'user_id,friend_id');

      // Reload friend requests
      await _controller.loadIncomingFriendRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept friend request: $e')),
      );
    }
  }

  Future<void> _declineFriendRequest(String requestId) async {
    final supa = Supabase.instance.client;

    try {
      // Delete the friend request
      await supa.from('friends').delete().eq('id', requestId);

      // Reload friend requests
      await _controller.loadIncomingFriendRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request declined')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to decline friend request: $e')),
      );
    }
  }

  Widget _buildTeamFollowRequestsCard(List<Map<String, dynamic>> requests) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35), // Orange color matching friend requests
        borderRadius: BorderRadius.circular(12),
      ),
      child: PageView.builder(
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final request = requests[index];
          final requestId = request['request_id'] as String;
          final requestingTeamId = request['requesting_team_id'] as String;
          final requestingTeamName = request['requesting_team_name'] as String? ?? 'Unknown Team';
          final targetTeamName = request['target_team_name'] as String? ?? 'Unknown Team';
          
          return InkWell(
            onTap: () {
              _showTeamFollowRequestDialog(request);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Team icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.group, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  
                  // Message
                  Expanded(
                    child: Text(
                      requests.length == 1
                          ? '$requestingTeamName wants to connect with $targetTeamName'
                          : '$requestingTeamName wants to connect with $targetTeamName (${requests.length} requests)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  // Page indicator
                  if (requests.length > 1) ...[
                    const SizedBox(width: 6),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${index + 1}/${requests.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            requests.length,
                            (i) => Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == index
                                    ? Colors.white
                                    : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  // Arrow
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showTeamFollowRequestDialog(Map<String, dynamic> request) async {
    final requestId = request['request_id'] as String;
    final requestingTeamId = request['requesting_team_id'] as String;
    final requestingTeamName = request['requesting_team_name'] as String? ?? 'Unknown Team';
    final targetTeamName = request['target_team_name'] as String? ?? 'Unknown Team';
    final requestingTeamSport = request['requesting_team_sport'] as String? ?? '';
    final requestingTeamCity = request['requesting_team_base_city'] as String? ?? '';
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Team Follow Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(Icons.group, size: 30, color: Colors.blue),
            ),
            const SizedBox(height: 12),
            Text(
              '$requestingTeamName wants to connect with $targetTeamName',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (requestingTeamSport.isNotEmpty || requestingTeamCity.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${requestingTeamCity.isNotEmpty ? requestingTeamCity : ''}${requestingTeamCity.isNotEmpty && requestingTeamSport.isNotEmpty ? ' • ' : ''}${requestingTeamSport.isNotEmpty ? requestingTeamSport : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _rejectTeamFollowRequest(requestId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _approveTeamFollowRequest(requestId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _approveTeamFollowRequest(String requestId) async {
    final supa = Supabase.instance.client;

    try {
      if (kDebugMode) {
        print('[DEBUG] Approving follow request: $requestId');
      }
      
      // Get request details before updating
      final requestDetails = await supa
          .from('team_follow_requests')
          .select('requesting_team_id, target_team_id')
          .eq('id', requestId)
          .maybeSingle();
      
      if (kDebugMode && requestDetails != null) {
        print('[DEBUG] Request details: requesting_team_id=${requestDetails['requesting_team_id']}, target_team_id=${requestDetails['target_team_id']}');
      }
      
      // Update the request status to approved (this should trigger the database trigger)
      await supa
          .from('team_follow_requests')
          .update({'status': 'approved'})
          .eq('id', requestId);

      if (kDebugMode) {
        print('[DEBUG] Request status updated to approved');
        
        // Check if both directions exist in team_follows after a short delay
        if (requestDetails != null) {
          await Future.delayed(const Duration(milliseconds: 500));
          
          final requestingTeamId = requestDetails['requesting_team_id'] as String;
          final targetTeamId = requestDetails['target_team_id'] as String;
          
          // Check direction 1: requesting -> target
          final dir1 = await supa
              .from('team_follows')
              .select('follower_team_id, followed_team_id')
              .eq('follower_team_id', requestingTeamId)
              .eq('followed_team_id', targetTeamId)
              .maybeSingle();
          
          // Check direction 2: target -> requesting
          final dir2 = await supa
              .from('team_follows')
              .select('follower_team_id, followed_team_id')
              .eq('follower_team_id', targetTeamId)
              .eq('followed_team_id', requestingTeamId)
              .maybeSingle();
          
          print('[DEBUG] After approval - Direction 1 (requesting->target): ${dir1 != null ? "EXISTS" : "MISSING"}');
          print('[DEBUG] After approval - Direction 2 (target->requesting): ${dir2 != null ? "EXISTS" : "MISSING"}');
        }
      }

      // Reload follow requests
      await _controller.loadPendingTeamFollowRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team follow request approved')),
      );
    } catch (e) {
      if (kDebugMode) {
        print('[DEBUG] Error approving follow request: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve follow request: $e')),
      );
    }
  }

  Future<void> _rejectTeamFollowRequest(String requestId) async {
    final supa = Supabase.instance.client;

    try {
      // Update the request status to rejected
      await supa
          .from('team_follow_requests')
          .update({'status': 'rejected'})
          .eq('id', requestId);

      // Reload follow requests
      await _controller.loadPendingTeamFollowRequests();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team follow request rejected')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject follow request: $e')),
      );
    }
  }

  Widget _buildSmartCard({
    required String message,
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
        padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
          color: const Color(0xFF1BA8B5), // Light teal matching the design
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // Icon
                      Container(
              width: 40,
              height: 40,
                        decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            
            // Message
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                          color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            
            // Arrow
            const Icon(
              Icons.chevron_right,
              color: Colors.white70,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // Special card for pending games with orange flame icon and light background
  Widget _buildPendingActionCard({
    required int count,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100, // Light background
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Orange flame icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.local_fire_department,
                color: Colors.orange.shade700,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            
            // Message with subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count ${count == 1 ? 'game' : 'games'} awaiting your action',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Tap here to review your game!',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            
            // Arrow
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade600,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // Show dialog with all pending admin/approval items
  Future<void> _showPendingActionDialog() async {
    // Reload all pending data to ensure it's fresh
    await _controller.loadPendingGamesForAdmin();
    await _controller.loadMyPendingAvailabilityMatches();
    await _controller.loadPendingIndividualGames();
    await _controller.loadPendingJoinRequestsForMyGames(); // Load pending join requests for public pick-up games
    await _controller.loadAdminTeamsAndInvites();
    await _controller.loadFriendsOnlyIndividualGames();
    
    final pendingAdminMatches = _controller.pendingTeamMatchesForAdmin;
    final pendingAvailabilityGames = _controller.pendingAvailabilityTeamMatches;
    final pendingIndividualGames = _controller.pendingIndividualGames;
    final pendingJoinRequests = _controller.pendingJoinRequestsForMyGames;
    final pendingInvites = _controller.teamVsTeamInvites
        .where((inv) => inv['status'] == 'pending')
        .toList();
    final friendsOnlyGames = _controller.friendsOnlyIndividualGames;

    final hasAnyPending = pendingAdminMatches.isNotEmpty ||
        pendingAvailabilityGames.isNotEmpty ||
        pendingIndividualGames.isNotEmpty ||
        pendingJoinRequests.isNotEmpty ||
        pendingInvites.isNotEmpty ||
        friendsOnlyGames.isNotEmpty;

    if (!hasAnyPending) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending actions')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Create local mutable lists that can be updated in real-time
          final pendingAdminMatches = List<Map<String, dynamic>>.from(_controller.pendingTeamMatchesForAdmin);
          final pendingAvailabilityGames = List<Map<String, dynamic>>.from(_controller.pendingAvailabilityTeamMatches);
          final pendingIndividualGames = List<Map<String, dynamic>>.from(_controller.pendingIndividualGames);
          final pendingJoinRequests = List<Map<String, dynamic>>.from(_controller.pendingJoinRequestsForMyGames);
          
          return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
                        child: Column(
              mainAxisSize: MainAxisSize.min,
                          children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Games Awaiting Your Action',
                              style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Refresh data after closing dialog
                          _controller.loadPendingGamesForAdmin();
                          _controller.loadMyPendingAvailabilityMatches();
                          _controller.loadPendingIndividualGames();
                          _controller.loadAdminTeamsAndInvites();
                          setState(() {});
                        },
                            ),
                          ],
                        ),
                      ),
                  // Content - Use sections with local lists that update in real-time
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Use the exact same pending admin approval section
                        _buildPendingAdminApprovalSection(),
                        const SizedBox(height: 24),
                          // Use pending confirmation section with local lists
                          _buildPendingConfirmationSectionInDialog(
                            pendingAvailabilityGames: pendingAvailabilityGames,
                            pendingIndividualGames: pendingIndividualGames,
                            setDialogState: setDialogState,
                            onGameRemoved: (requestId) {
                              // Remove from local lists immediately
                              pendingAvailabilityGames.removeWhere((g) => g['request_id'] == requestId);
                              pendingIndividualGames.removeWhere((g) => g['request_id'] == requestId);
                              
                              // Check if all lists are empty and close dialog
                              final hasAnyPending = pendingAdminMatches.isNotEmpty ||
                                  pendingAvailabilityGames.isNotEmpty ||
                                  pendingIndividualGames.isNotEmpty ||
                                  pendingJoinRequests.isNotEmpty;
                              
                              setDialogState(() {
                                if (!hasAnyPending) {
                                  Navigator.of(context).pop();
                                  // Refresh data after closing
                                  _controller.loadPendingGamesForAdmin();
                                  _controller.loadMyPendingAvailabilityMatches();
                                  _controller.loadPendingIndividualGames();
                                  _controller.loadAdminTeamsAndInvites();
                                  setState(() {});
                                }
                              });
                            },
                          ),
                          // Pending join requests for my public pick-up games
                          if (pendingJoinRequests.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildPendingJoinRequestsSectionInDialog(
                              pendingJoinRequests: pendingJoinRequests,
                              setDialogState: setDialogState,
                              onRequestRemoved: (requestId, userId) {
                                // Remove from local list immediately
                                pendingJoinRequests.removeWhere((r) => 
                                  r['request_id'] == requestId && r['user_id'] == userId);
                                
                                // Check if all lists are empty and close dialog
                                final hasAnyPending = pendingAdminMatches.isNotEmpty ||
                                    pendingAvailabilityGames.isNotEmpty ||
                                    pendingIndividualGames.isNotEmpty ||
                                    pendingJoinRequests.isNotEmpty;
                                
                                setDialogState(() {
                                  if (!hasAnyPending) {
                                    Navigator.of(context).pop();
                                    // Refresh data after closing
                                    _controller.loadPendingGamesForAdmin();
                                    _controller.loadMyPendingAvailabilityMatches();
                                    _controller.loadPendingIndividualGames();
                                    _controller.loadPendingJoinRequestsForMyGames();
                                    _controller.loadAdminTeamsAndInvites();
                                    setState(() {});
                                  }
                                });
                              },
                            ),
                          ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
          );
        },
      ),
    );
  }

  
  // [ Primary CTA ] Section (DEPRECATED - now using My Active Plans)
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
  
  // Calculate distance from match data (for Discover section)
  String _calculateDistanceHome(Map<String, dynamic> match) {
    final distance = match['distance_miles'] as double?;
    if (distance == null) {
      return 'Distance unknown';
    }
    if (distance < 1) {
      return '${(distance * 5280).round()} ft';
    } else if (distance < 10) {
      return '${distance.toStringAsFixed(1)} mi';
    } else {
      return '${distance.round()} mi';
    }
  }
  
  // Format date for filter display
  String _formatDateHome(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    return '${date.month}/${date.day}/${date.year}';
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
  
  // [ Pending Admin Approval ] Section (expanded with details)
  Widget _buildPendingAdminApprovalSection() {
    final pendingInvites = _controller.teamVsTeamInvites
        .where((inv) => inv['status'] == 'pending')
        .toList();
    final pendingAdminMatches = _controller.pendingTeamMatchesForAdmin;
    // Filter out private games (friends_group visibility) - they should not show in admin notifications
    final friendsOnlyGames = _controller.friendsOnlyIndividualGames
        .where((game) {
          // The game structure has 'request' nested inside
          final request = game['request'] as Map<String, dynamic>?;
          if (request == null) return false;
          final visibility = (request['visibility'] as String?)?.toLowerCase() ?? '';
          // Exclude private games (friends_group) - they should not appear in admin approval
          return visibility != 'friends_group';
        })
        .toList();

    final hasContent = pendingInvites.isNotEmpty ||
        pendingAdminMatches.isNotEmpty ||
        friendsOnlyGames.isNotEmpty;

    // Hide the section if there's no content
    if (!hasContent) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
                        Row(
                          children: [
            const Icon(Icons.admin_panel_settings, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Pending Admin Approval',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Pending Team Invites
        ...pendingInvites.map((invite) => _buildPendingInviteCard(invite)),
        
        // Pending Admin Matches (can approve)
        ...pendingAdminMatches.map((match) => _buildPendingAdminMatchCard(match)),
        
        // Friends-only Individual Games
        ...friendsOnlyGames.map((game) => _buildFriendsOnlyGameCard(game)),
      ],
    );
  }

  // [ Public Pending Approval ] Section
  Widget _buildPublicPendingApprovalSection() {
    final publicGames = _controller.publicPendingGames;

    if (publicGames.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.public, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Public Pending Approval',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '${publicGames.length}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...publicGames.map((game) => _buildPublicGameCard(game)),
      ],
    );
  }

  Widget _buildPublicGameCard(Map<String, dynamic> game) {
    final sport = game['sport'] as String? ?? '';
    final mode = game['mode'] as String? ?? '';
    final matchType = game['match_type'] as String? ?? '';
    final startDt = game['start_time'] as DateTime?;
    final venue = game['venue'] as String?;
    final creatorName = game['creator_name'] as String? ?? 'Unknown';
    final details = game['details'] as String?;
    final numPlayers = game['num_players'] as int?;
    final proficiencyLevel = game['proficiency_level'] as String?;
    final isIndividual = mode == 'pickup' || matchType == 'pickup';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _getSportEmoji(sport),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 8),
                            Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isIndividual
                            ? 'Pick-up Game'
                            : '${_displaySport(sport)} Team Game',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Created by: $creatorName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (startDt != null)
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(startDt),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            if (venue != null && venue.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      venue,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
            if (details != null && details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                details,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
            if (isIndividual && numPlayers != null) ...[
              const SizedBox(height: 8),
              Text(
                'Players needed: $numPlayers',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
            if (proficiencyLevel != null) ...[
              const SizedBox(height: 4),
              Text(
                'Level: $proficiencyLevel',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _requestToJoinPublicGame(game),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Request to Join'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestToJoinPublicGame(Map<String, dynamic> game) async {
    // Navigate to discover screen or show join dialog
    // For now, show a message
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Join game functionality coming soon')),
    );
  }

  // [ Pending Approval ] Section (expanded with details)
  Widget _buildPendingConfirmationSection() {
    final pendingAvailabilityGames = _controller.pendingAvailabilityTeamMatches;
    final pendingIndividualGames = _controller.pendingIndividualGames;
    final allPending = [
      ...pendingAvailabilityGames.map((g) => {...g, 'game_type': 'team'}),
      ...pendingIndividualGames.map((g) => {...g, 'game_type': 'individual'}),
    ];

    // Hide the section if there's no content
    if (allPending.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_available, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Confirm your availability',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // All pending games (team + individual)
        ...allPending.map((game) {
          if (game['game_type'] == 'team') {
            return _buildPendingAvailabilityTeamCard(game);
          } else {
            return _buildPendingIndividualGameCard(game);
          }
        }),
      ],
    );
  }

  // Dialog-specific version that uses local lists and supports immediate removal
  Widget _buildPendingConfirmationSectionInDialog({
    required List<Map<String, dynamic>> pendingAvailabilityGames,
    required List<Map<String, dynamic>> pendingIndividualGames,
    required StateSetter setDialogState,
    required Function(String) onGameRemoved,
  }) {
    final allPending = [
      ...pendingAvailabilityGames.map((g) => {...g, 'game_type': 'team'}),
      ...pendingIndividualGames.map((g) => {...g, 'game_type': 'individual'}),
    ];

    // Hide the section if there's no content
    if (allPending.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_available, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Confirm your availability',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // All pending games (team + individual)
        ...allPending.map((game) {
          if (game['game_type'] == 'team') {
            return _buildPendingAvailabilityTeamCard(game);
          } else {
            return _buildPendingIndividualGameCard(game, onActionComplete: () => onGameRemoved(game['request_id'] as String));
          }
        }),
      ],
    );
  }
  
  Widget _buildPendingIndividualGameCard(Map<String, dynamic> game, {VoidCallback? onActionComplete}) {
    final reqId = game['request_id'] as String;
    final sport = game['sport'] as String? ?? '';
    final startDt = game['start_time'] as DateTime?;
    final venue = game['venue'] as String?;
    final creatorName = game['creator_name'] as String? ?? 'Unknown';
    final numPlayers = game['num_players'] as int? ?? 4;
    final spotsLeft = game['spots_left'] as int? ?? numPlayers;
    final visibility = (game['visibility'] as String?)?.toLowerCase() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // Navigate to My Games tab and expand this specific game
          Navigator.of(context).pop(); // Close the dialog first
          setState(() {
            _controller.selectedIndex = 1; // Switch to My Games tab
            _expandedMatchIds.add(reqId); // Expand this specific game
          });
        },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _getSportEmoji(sport),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sport name prominently displayed
                      Text(
                        _displaySport(sport),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        visibility == 'friends_group' ? 'Private Game' : 'Pick-up Game',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Created by: $creatorName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (startDt != null)
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(startDt),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            if (venue != null && venue.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      venue,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$spotsLeft spots left',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Immediately remove from dialog if callback provided
                      if (onActionComplete != null) {
                        onActionComplete();
                      }
                      // Then perform the actual action
                      await _acceptIndividualGameAttendance(reqId);
                    },
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    label: const Text('Available'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Immediately remove from dialog if callback provided
                      if (onActionComplete != null) {
                        onActionComplete();
                      }
                      // Then perform the actual action
                      await _declineIndividualGameAttendance(reqId);
                    },
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text('Not Available'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }

  // Dialog-specific version for pending join requests section
  Widget _buildPendingJoinRequestsSectionInDialog({
    required List<Map<String, dynamic>> pendingJoinRequests,
    required StateSetter setDialogState,
    required Function(String, String) onRequestRemoved,
  }) {
    if (pendingJoinRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    // Group requests by game
    final Map<String, List<Map<String, dynamic>>> requestsByGame = {};
    for (final req in pendingJoinRequests) {
      final gameId = req['request_id'] as String?;
      if (gameId != null) {
        requestsByGame.putIfAbsent(gameId, () => []).add(req);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_add, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Join Requests for Your Pick-up Games',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...requestsByGame.entries.map((entry) {
          final gameId = entry.key;
          final requests = entry.value;
          if (requests.isEmpty) return const SizedBox.shrink();
          
          final firstReq = requests.first;
          final sport = firstReq['sport'] as String? ?? '';
          final startDt = firstReq['start_time'] as DateTime?;
          final venue = firstReq['venue'] as String?;
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_getSportEmoji(sport), style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pick-up Game - ${_displaySport(sport)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (startDt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')} ${_formatTime(startDt)}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                            if (venue != null && venue.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                venue,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pending join requests:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...requests.map((req) {
                    final userId = req['user_id'] as String?;
                    final userName = req['user_name'] as String? ?? 'Unknown';
                    final userPhoto = req['user_photo_url'] as String?;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          if (userPhoto != null && userPhoto.isNotEmpty)
                            CircleAvatar(
                              radius: 16,
                              backgroundImage: NetworkImage(userPhoto),
                            )
                          else
                            const CircleAvatar(
                              radius: 16,
                              child: Icon(Icons.person, size: 18),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              userName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              if (gameId == null || userId == null) return;
                              
                              try {
                                // First, update database
                                await _controller.approveIndividualGameRequest(
                                  requestId: gameId,
                                  userId: userId,
                                  approve: true,
                                );
                                
                                // Reload all necessary data to ensure fresh state:
                                // 1. Discovery matches - to update availability counter for all users and remove from User 2's trending games
                                await _controller.loadDiscoveryPickupMatches(forceRefresh: true);
                                // 2. Pending join requests - to refresh the list from server (remove this approved request)
                                await _controller.loadPendingJoinRequestsForMyGames();
                                // 3. My Games - to ensure both User 1 and User 2 see updated game status
                                await _controller.loadAllMyIndividualMatches();
                                
                                // Update dialog with fresh data from controller and remove from local list
                                setDialogState(() {
                                  // Remove the approved request from local list
                                  pendingJoinRequests.removeWhere((r) => 
                                    r['request_id'] == gameId && r['user_id'] == userId);
                                  
                                  // Refresh from controller to ensure we have latest data
                                  final freshRequests = _controller.pendingJoinRequestsForMyGames;
                                  // Only update if there's a difference to avoid unnecessary rebuilds
                                  if (freshRequests.length != pendingJoinRequests.length ||
                                      !freshRequests.every((fr) => pendingJoinRequests.any((pr) => 
                                        pr['request_id'] == fr['request_id'] && pr['user_id'] == fr['user_id']))) {
                                    pendingJoinRequests.clear();
                                    pendingJoinRequests.addAll(freshRequests);
                                  }
                                });
                                
                                // Trigger parent widget refresh to update smart card count and My Games
                                if (!mounted) return;
                                setState(() {});
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Request approved!')),
                                );
                              } catch (e) {
                                // On error, reload to restore correct state
                                await _controller.loadPendingJoinRequestsForMyGames();
                                setDialogState(() {
                                  pendingJoinRequests.clear();
                                  pendingJoinRequests.addAll(_controller.pendingJoinRequestsForMyGames);
                                });
                                if (!mounted) return;
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to approve: $e')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Approve', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              if (gameId == null || userId == null) return;
                              
                              try {
                                // Update database
                                await _controller.approveIndividualGameRequest(
                                  requestId: gameId,
                                  userId: userId,
                                  approve: false,
                                );
                                
                                // Reload all necessary data:
                                // 1. Discovery matches - to remove denied game from User 2's trending games
                                await _controller.loadDiscoveryPickupMatches(forceRefresh: true);
                                // 2. Pending join requests - to refresh the list from server (remove this denied request)
                                await _controller.loadPendingJoinRequestsForMyGames();
                                
                                // Update dialog with fresh data from controller and remove from local list
                                setDialogState(() {
                                  // Remove the denied request from local list
                                  pendingJoinRequests.removeWhere((r) => 
                                    r['request_id'] == gameId && r['user_id'] == userId);
                                  
                                  // Refresh from controller to ensure we have latest data
                                  final freshRequests = _controller.pendingJoinRequestsForMyGames;
                                  if (freshRequests.length != pendingJoinRequests.length ||
                                      !freshRequests.every((fr) => pendingJoinRequests.any((pr) => 
                                        pr['request_id'] == fr['request_id'] && pr['user_id'] == fr['user_id']))) {
                                    pendingJoinRequests.clear();
                                    pendingJoinRequests.addAll(freshRequests);
                                  }
                                });
                                
                                // Trigger parent widget refresh to update smart card count
                                if (!mounted) return;
                                setState(() {});
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Request denied')),
                                );
                              } catch (e) {
                                // On error, reload to restore correct state
                                await _controller.loadPendingJoinRequestsForMyGames();
                                setDialogState(() {
                                  pendingJoinRequests.clear();
                                  pendingJoinRequests.addAll(_controller.pendingJoinRequestsForMyGames);
                                });
                                if (!mounted) return;
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to deny: $e')),
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Deny', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
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
    
    // Get inviting team name (the team that created the invite)
    final invitingTeamName = invite['request_team_name'] as String? ?? 'Team';
    // Get user's team name (the team that received the invite)
    final yourTeamName = invite['target_team_name'] as String?;
    
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

    // Build the title message: "<Inviting Team Name> <Sport> team is inviting for a match with your <your team>. Please confirm."
    final titleMessage = yourTeamName != null && yourTeamName.isNotEmpty
        ? '$invitingTeamName ${_displaySport(sport)} team is inviting for a match with your $yourTeamName. Please confirm.'
        : '$invitingTeamName ${_displaySport(sport)} team is inviting for a match. Please confirm.';

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
                        titleMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
                      // Reload all pending data
                      await _controller.loadAdminTeamsAndInvites();
                      await _controller.loadPendingGamesForAdmin();
                      if (mounted) {
                        setState(() {}); // Refresh UI
                        // Close dialog if open
                        if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }
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
                      // Reload all pending data
                      await _controller.loadAdminTeamsAndInvites();
                      await _controller.loadPendingGamesForAdmin();
                      await _controller.loadConfirmedTeamMatches();
                      if (mounted) {
                        setState(() {}); // Refresh UI
                        // Close dialog if open
                        if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }
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
    final respondingTeam = match['responding_team'] as Map<String, dynamic>?;
    final adminTeam = match['admin_team'] as Map<String, dynamic>?;
    if (req == null || team == null) return const SizedBox.shrink();

    final sport = req['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    final invitingTeamName = team['name'] as String? ?? 'Unknown Team';
    final respondingTeamName = respondingTeam?['name'] as String?;
    final yourTeamName = adminTeam?['name'] as String?; // User's team that received the invite
    final visibility = req['visibility'] as String?;
    final isPublic = req['is_public'] as bool? ?? false;
    final startTime1 = req['start_time_1'] as String?;
    final startTime2 = req['start_time_2'] as String?;
    final venue = req['venue'] as String?;
    
    // Debug logging
    if (kDebugMode) {
      print('[DEBUG] _buildPendingAdminMatchCard:');
      print('  - visibility: $visibility');
      print('  - is_public: $isPublic');
      print('  - respondingTeam: $respondingTeam');
      print('  - respondingTeamName: $respondingTeamName');
      print('  - invitingTeamName: $invitingTeamName');
      print('  - yourTeamName: $yourTeamName');
    }
    
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

    // Build the message: Use new format for all games
    final String titleMessage;
    final bool isPublicGame = (visibility?.toLowerCase() == 'public') || isPublic;
    
    if (isPublicGame && respondingTeamName != null && respondingTeamName.isNotEmpty) {
      // Public game: "<Team X> has responded to <Team A> <Sport> Team match request. Please confirm :"
      titleMessage = '$respondingTeamName has responded to $invitingTeamName ${_displaySport(sport)} Team match request. Please confirm :';
    } else if (!isPublicGame && yourTeamName != null && yourTeamName.isNotEmpty) {
      // Invite-specific game: "<Inviting Team Name> <Sport> team is inviting for a match with your <your team>. Please confirm."
      titleMessage = '$invitingTeamName ${_displaySport(sport)} team is inviting for a match with your $yourTeamName. Please confirm.';
    } else {
      // Fallback: Use old format if we don't have the necessary information
      titleMessage = 'Team Match - Admin Approval';
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
                      Text(
                        titleMessage,
                        style: TextStyle(
                          fontSize: (respondingTeamName != null || (yourTeamName != null && !((visibility?.toLowerCase() == 'public') || (req['is_public'] as bool? ?? false)))) ? 15 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Only show "Requesting team" if we're using the old format (fallback)
                      if (titleMessage == 'Team Match - Admin Approval') ...[
                        Text(
                          'Requesting team: $invitingTeamName',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
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
                    // Deny the pending admin match
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
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No admin team found for this sport')),
                        );
                      }
                      return;
                    }
                    
                    final requestId = req['id'] as String?;
                    final teamId = matchingTeam['id'] as String?;
                    if (requestId == null || teamId == null) return;
                    
                    // Check if this is a public game
                    final visibility = req['visibility'] as String?;
                    final isPublic = req['is_public'] as bool? ?? false;
                    final isPublicGame = (visibility?.toLowerCase() == 'public') || isPublic;
                    
                    // For public games, we need to deny the responding team's invite
                    // The responding_team_id is the team that clicked "Join" (Team X, Team Y, etc.)
                    final respondingTeamId = match['responding_team_id'] as String?;
                    final respondingTeam = match['responding_team'] as Map<String, dynamic>?;
                    
                    // For public games, use responding team ID; for non-public, use creating team ID
                    final targetTeamIdForDeny = (isPublicGame && respondingTeamId != null) 
                        ? respondingTeamId 
                        : teamId;
                    
                    try {
                      await _controller.denyPendingAdminMatch(
                        requestId: requestId,
                        myAdminTeamId: targetTeamIdForDeny,
                      );
                      // Reload all pending data
                      await _controller.loadPendingGamesForAdmin();
                      await _controller.loadAdminTeamsAndInvites();
                      if (mounted) {
                        setState(() {}); // Refresh UI
                        // Close dialog if open
                        if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Match declined')),
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
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No admin team found for this sport')),
                        );
                      }
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
                      // Reload all pending data
                      await _controller.loadAdminTeamsAndInvites();
                      await _controller.loadMyPendingAvailabilityMatches();
                      if (mounted) {
                        setState(() {}); // Refresh UI
                        // Close dialog if open
                        if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }
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
    final opponentTeamName = isOnTeamA ? (teamBName ?? 'Opponent Team') : teamAName;
    final isOpenChallenge = game['is_open_challenge'] as bool? ?? false;
    
    // For confirmed specific team invites (not open challenge), show custom message
    final isSpecificTeamInvite = isConfirmed && !isOpenChallenge && teamBName != null && teamBName.isNotEmpty;

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
                      // For confirmed specific team invites, show custom message
                      if (isSpecificTeamInvite)
                        Text(
                          'You have a match with "$opponentTeamName". Please confirm your availability:',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        Text(
                          '${_displaySport(sport)} • Team Match',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      // Only show "You are in" subtitle for non-specific team invites or non-confirmed games
                      if (!isSpecificTeamInvite)
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
                      closeDialog: true,
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
                      closeDialog: true,
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
    bool closeDialog = false,
  }) async {
    try {
      await _controller.setMyAttendance(
        requestId: requestId,
        teamId: teamId,
        status: status,
      );
      // Reload pending availability games
      await _controller.loadMyPendingAvailabilityMatches();
      // Just refresh the UI
      setState(() {});
      if (mounted) {
        // Close dialog if requested
        if (closeDialog && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
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

  /// Get color based on percentage (0.0-1.0): red → orange → green
  Color _getPercentageColor(double pct) {
    final clamped = pct.clamp(0.0, 1.0);
    
    if (clamped <= 0.5) {
      // 0% to 50%: Red to Orange
      final ratio = clamped * 2;
      return Color.lerp(Colors.red, Colors.orange, ratio)!;
    } else {
      // 50% to 100%: Orange to Green
      final ratio = (clamped - 0.5) * 2;
      return Color.lerp(Colors.orange, Colors.green, ratio)!;
    }
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
  
  // Discover Section Content - Chip/card extending to bottom with teal side borders
  Widget _buildDiscoverSectionContent() {
    if (!_initDone || _controller.loadingDiscoveryMatches) {
      return Container(
        margin: const EdgeInsets.only(top: 16), // Space from dark section above
        decoration: BoxDecoration(
          color: Colors.white, // White chip/card background
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border(
            left: BorderSide(color: const Color(0xFF14919B), width: 2), // Teal green side borders (little border)
            right: BorderSide(color: const Color(0xFF14919B), width: 2),
          ),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    
    final filteredMatches = _getFilteredMatchesHome();
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available height to extend to bottom edge
        final screenHeight = MediaQuery.of(context).size.height;
        final availableHeight = screenHeight - 200; // Subtract approximate header height
    
    return Container(
      margin: const EdgeInsets.only(top: 16), // Space from dark section above
          constraints: BoxConstraints(
            minHeight: availableHeight, // Extend to fill available space to bottom edge
          ),
      decoration: BoxDecoration(
        color: Colors.white, // White chip/card background
        borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24), // Rounded top corners
          topRight: Radius.circular(24),
              bottomLeft: Radius.zero, // Rectangular bottom corners
              bottomRight: Radius.zero,
        ),
        border: Border(
          left: BorderSide(color: const Color(0xFF14919B), width: 2), // Teal green side borders (little border)
          right: BorderSide(color: const Color(0xFF14919B), width: 2),
        ),
      ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with "Trending Games" and "View All" link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Trending Games',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Switch to My Games tab to see all matches
                          setState(() => _controller.selectedIndex = 1);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6B35), // Orange color
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Filter chips row - "All" first, then Sports, Date, Nearby
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 0),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50, // Teal green background matching My Games filter
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: _buildDiscoverFilters(),
                  ),
                  const SizedBox(height: 16),
                  
                  if (filteredMatches.isEmpty) ...[
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.search_off, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No games available',
                            style: TextStyle(fontSize: 18, color: Colors.black87),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Check back later for new matches',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Game cards list
                    ...filteredMatches.take(10).map((match) => _buildResultCardHome(match)),
                    if (filteredMatches.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextButton(
                          onPressed: () {
                            _controller.loadDiscoveryPickupMatches();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6B35), // Orange color
                          ),
                          child: Text('View More (${filteredMatches.length - 10} more)'),
                        ),
                      ),
                  ],
                ],
              ),
      ),
        );
      },
    );
  }
  
  // Filter matches based on current filter state
  List<Map<String, dynamic>> _getFilteredMatchesHome() {
    var matches = _controller.discoveryPickupMatches;
    
    // Apply sport filter
    if (_selectedSportFilter != null) {
      matches = matches.where((m) => 
        (m['sport'] as String?)?.toLowerCase() == _selectedSportFilter?.toLowerCase()
      ).toList();
    }
    
    // Apply date filter
    if (_selectedDateFilter != null) {
      matches = matches.where((m) {
        final startTime = m['start_time'] as DateTime?;
        if (startTime == null) return false;
        return startTime.year == _selectedDateFilter!.year &&
               startTime.month == _selectedDateFilter!.month &&
               startTime.day == _selectedDateFilter!.day;
      }).toList();
    }
    
    // Apply distance filter (when nearby is active)
    if (_nearbyFilterActive && _maxDistance < 100) {
      matches = matches.where((m) {
        final distance = m['distance_miles'] as double?;
        if (distance == null) return false;
        return distance <= _maxDistance;
      }).toList();
    }
    
    return matches;
  }
  
  // Build full result card matching DiscoverScreen format
  Widget _buildResultCardHome(Map<String, dynamic> match) {
    final sport = match['sport'] as String? ?? '';
    final mode = match['mode'] as String? ?? '';
    final numPlayers = match['num_players'] as int?;
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final venue = match['venue'] as String?;
    final canAccept = match['can_accept'] as bool? ?? true;
    final spotsLeft = match['spots_left'] as int?;
    final requestId = match['request_id'] as String?;
    final sportEmoji = _getSportEmoji(sport);
    final distance = _calculateDistanceHome(match);
    final teamName = match['team_name'] as String?;
    final creatorName = match['creator_name'] as String?;
    final isOpenChallenge = match['is_open_challenge'] as bool? ?? false;
    final userTeamInviteStatus = match['user_team_invite_status'] as String?;
    final userTeamInviteStatuses = match['user_team_invite_statuses'] as List<dynamic>?;
    
    final isTeamGame = mode == 'team_vs_team';
    
    // Format date
    final dateStr = startDt != null 
        ? '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}'
        : '';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
        color: Colors.grey.shade100, // Dark white background
                    borderRadius: BorderRadius.circular(12),
                  ),
      child: InkWell(
        onTap: () {
          // TODO: Show match details
        },
                          borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sport name and Join button row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Sport name with distance (e.g., "🏏 Cricket || 2.5 mi")
                  Expanded(
                    child: Text(
                      '$sportEmoji ${_displaySport(sport)} || ${distance != "Distance unknown" ? distance : "N/A"}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // Join button (only show if can join)
                  if (isTeamGame && canAccept && userTeamInviteStatus != 'pending' && userTeamInviteStatus != 'denied' && (userTeamInviteStatuses == null || userTeamInviteStatuses.isEmpty))
                    ElevatedButton(
                      onPressed: () async {
                        await _handleJoinTeamGameHome(requestId!, sport);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Join',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else if (!isTeamGame && canAccept)
                    Builder(
                      builder: (context) {
                        // Check if user has pending request for this game
                        final myAttendanceStatus = match['my_attendance_status'] as String?;
                        final hasPendingRequest = myAttendanceStatus?.toLowerCase() == 'pending';
                        
                        if (hasPendingRequest) {
                          // Show "Request has been sent" button
                          return OutlinedButton(
                            onPressed: null, // Disabled
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: const BorderSide(color: Colors.grey),
                            ),
                            child: Text(
                              'Pending',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          );
                        } else {
                          // Show "Join" button
                          return ElevatedButton(
                      onPressed: () async {
                        await _requestToJoinIndividualGameHome(requestId!);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Join',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                          );
                        }
                      },
                    ),
                ],
              ),
              
              const SizedBox(height: 6),
              
              // Created by: Team Name (only for team games)
              if (isTeamGame && teamName != null) ...[
                Text(
                  'Created by: $teamName',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              
              // Looking for opponents/players
              Text(
                isTeamGame ? 'Looking for opponents' : 'Looking for players',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Date | Location row (swapped positions)
              Row(
                children: [
                  // Date (moved to first position)
                  if (dateStr.isNotEmpty) ...[
                    const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const Text(' | ', style: TextStyle(color: Colors.grey)),
                  ],
                  // Location (moved to second position)
                  if (venue != null && venue.isNotEmpty) ...[
                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        venue,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ] else if (distance.isNotEmpty) ...[
                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      distance,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
              
              // Spots left for individual games (show below location/date)
              if (!isTeamGame && spotsLeft != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.people, size: 14, color: spotsLeft! > 0 ? Colors.green : Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      '$spotsLeft ${spotsLeft == 1 ? 'spot' : 'spots'} left',
                      style: TextStyle(
                        fontSize: 13,
                        color: spotsLeft! > 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                        ),
                    ],
                  ),
              ],
              
              const SizedBox(height: 10),
              
              // Status messages for team games (only show if cannot join or has status)
              if (isTeamGame && !canAccept) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You must be an admin of a ${_displaySport(sport)} team to accept this match',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isTeamGame && userTeamInviteStatuses != null && userTeamInviteStatuses.isNotEmpty) ...[
                _buildMultiTeamStatusDisplayHome(userTeamInviteStatuses, teamName ?? _displaySport(sport)),
              ] else if (isTeamGame && userTeamInviteStatus == 'pending') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_empty, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Request has been sent, wait for the ${teamName ?? _displaySport(sport)} team admin response',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isTeamGame && userTeamInviteStatus == 'denied') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cancel, size: 16, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This request has been denied',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Show organizer approval message for individual games (only if button not shown)
              if (!isTeamGame && !canAccept) ...[
                const SizedBox(height: 4),
                Text(
                  'Organizer must approve your request',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  // Format time for discover cards (matching DiscoverScreen)
  String _formatTimeForDiscover(DateTime? start) {
    if (start == null) return 'TBA';
    final now = DateTime.now();
    final isToday = start.year == now.year && 
                    start.month == now.month && 
                    start.day == now.day;
    final isTomorrow = start.year == now.year && 
                       start.month == now.month && 
                       start.day == now.day + 1;
    
    String fmtTime(DateTime dt) {
      final h24 = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final isPM = h24 >= 12;
      final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
      final ampm = isPM ? 'PM' : 'AM';
      return '$h12:$m $ampm';
    }
    
    if (isToday) return 'Today ${fmtTime(start)}';
    if (isTomorrow) return 'Tomorrow ${fmtTime(start)}';
    return '${start.month}/${start.day} ${fmtTime(start)}';
  }
  
  // Build multi-team status display
  Widget _buildMultiTeamStatusDisplayHome(List<dynamic> inviteStatuses, String creatingTeamName) {
    final statusList = inviteStatuses.map((s) {
      if (s is Map<String, dynamic>) {
        return {
          'status': s['status'] as String?,
          'team_name': s['team_name'] as String? ?? 'Unknown Team',
        };
      }
      return null;
    }).whereType<Map<String, dynamic>>().toList();
    
    if (statusList.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final pendingTeams = <String>[];
    final deniedTeams = <String>[];
    final acceptedTeams = <String>[];
    
    for (final statusInfo in statusList) {
      final status = (statusInfo['status'] as String?)?.toLowerCase();
      final teamName = statusInfo['team_name'] as String? ?? 'Unknown Team';
      
      if (status == 'pending') {
        pendingTeams.add(teamName);
      } else if (status == 'denied') {
        deniedTeams.add(teamName);
      } else if (status == 'accepted') {
        acceptedTeams.add(teamName);
      }
    }
    
    // Determine which status to show (priority: denied > pending > accepted)
    if (deniedTeams.isNotEmpty && pendingTeams.isEmpty && acceptedTeams.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade300),
        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
            Row(
              children: [
                Icon(Icons.cancel, size: 16, color: Colors.red[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All requests denied',
                              style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (deniedTeams.length > 1) ...[
                            const SizedBox(height: 4),
                            Text(
                'Teams: ${deniedTeams.join(', ')}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[800],
                ),
              ),
            ],
          ],
        ),
      );
    } else if (pendingTeams.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_empty, size: 16, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pendingTeams.length == 1
                        ? '${pendingTeams.first}: Request sent, waiting for $creatingTeamName admin response'
                        : 'Requests sent for ${pendingTeams.join(', ')}. Waiting for $creatingTeamName admin response',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                        ),
                    ],
                  ),
            if (deniedTeams.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Denied: ${deniedTeams.join(', ')}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[800],
                ),
              ),
            ],
          ],
        ),
      );
    } else if (acceptedTeams.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                acceptedTeams.length == 1
                    ? '${acceptedTeams.first}: Accepted!'
                    : 'Accepted for: ${acceptedTeams.join(', ')}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green[900],
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }
  
  // Handle joining team game
  Future<void> _handleJoinTeamGameHome(String requestId, String sport) async {
    if (requestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid game request')),
      );
      return;
    }
    
    try {
      final adminTeamsForSport = _controller.getAdminTeamsForSport(sport);
      
      List<String>? selectedTeamIds;
      if (adminTeamsForSport.length > 1) {
        selectedTeamIds = await _showTeamSelectionDialogHome(sport);
        if (selectedTeamIds == null || selectedTeamIds.isEmpty) {
          return;
        }
      } else if (adminTeamsForSport.length == 1) {
        final teamId = adminTeamsForSport.first['id'] as String?;
        if (teamId != null) {
          selectedTeamIds = [teamId];
        }
      }
      
      if (selectedTeamIds == null || selectedTeamIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No team selected')),
          );
        }
        return;
      }
      
      int successCount = 0;
      int failCount = 0;
      final errors = <String>[];
      
      for (final teamId in selectedTeamIds) {
        try {
          await _controller.requestToJoinOpenChallengeTeamGame(
            requestId: requestId,
            sport: sport,
            joiningTeamId: teamId,
          );
          successCount++;
        } catch (e) {
          failCount++;
          errors.add(e.toString());
        }
      }
      
      await _controller.loadDiscoveryPickupMatches();
      
      if (mounted) {
        if (failCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successCount > 1
                  ? 'Join requests sent for $successCount teams! Admin will review your requests.'
                  : 'Join request sent! ${_displaySport(sport)} team admin will review your request.'),
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount team(s) joined successfully. $failCount team(s) failed: ${errors.first}'),
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to join: ${errors.first}'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join: $e')),
        );
      }
    }
  }
  
  // Show team selection dialog
  Future<List<String>?> _showTeamSelectionDialogHome(String sport) async {
    final adminTeamsForSport = _controller.getAdminTeamsForSport(sport);
    
    if (adminTeamsForSport.isEmpty) {
      return null;
    }
    
    if (adminTeamsForSport.length == 1) {
      final teamId = adminTeamsForSport.first['id'] as String?;
      return teamId != null ? [teamId] : null;
    }
    
    final selectedTeamIds = <String>{};
    
    return showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Select Team(s) to Join'),
              content: SizedBox(
                width: double.maxFinite,
      child: Column(
                  mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                    Text(
                      'You are an admin of multiple ${_displaySport(sport)} teams. Select which team(s) to join with:',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    if (adminTeamsForSport.length > 1)
                      CheckboxListTile(
                        title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.bold)),
                        value: selectedTeamIds.length == adminTeamsForSport.length,
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              for (final team in adminTeamsForSport) {
                                final teamId = team['id'] as String?;
                                if (teamId != null) {
                                  selectedTeamIds.add(teamId);
                                }
                              }
                            } else {
                              selectedTeamIds.clear();
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    const Divider(),
                    ...adminTeamsForSport.map((team) {
                      final teamId = team['id'] as String?;
                      final teamName = team['name'] as String? ?? 'Unknown Team';
                      final isSelected = teamId != null && selectedTeamIds.contains(teamId);
                      
                      return CheckboxListTile(
                        title: Text(teamName),
                        value: isSelected,
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true && teamId != null) {
                              selectedTeamIds.add(teamId);
                            } else if (teamId != null) {
                              selectedTeamIds.remove(teamId);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedTeamIds.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(selectedTeamIds.toList()),
                  child: Text('Join (${selectedTeamIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  // Request to join individual game
  Future<void> _requestToJoinIndividualGameHome(String requestId) async {
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to join games')),
      );
      return;
    }

    try {
      final existing = await supa
          .from('individual_game_attendance')
          .select('id, status')
          .eq('request_id', requestId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        final status = (existing['status'] as String?)?.toLowerCase() ?? 'pending';
        if (status == 'accepted') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are already part of this game!')),
          );
        } else if (status == 'pending') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request already sent. Waiting for organizer approval.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You previously declined this game.')),
          );
        }
        return;
      }

      await supa.from('individual_game_attendance').insert({
        'request_id': requestId,
        'user_id': userId,
        'status': 'pending',
      });

      // Optimistically update UI immediately - set my_attendance_status to 'pending'
      // so the button changes to "Pending" without waiting for reload
      if (mounted) {
        setState(() {
          // Find the match in discovery matches and update its status immediately
          final matchIndex = _controller.discoveryPickupMatches.indexWhere(
            (m) => (m['request_id'] as String?) == requestId,
          );
          if (matchIndex >= 0) {
            _controller.discoveryPickupMatches[matchIndex]['my_attendance_status'] = 'pending';
          }
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request sent! Organizer will review your request.'),
          duration: Duration(seconds: 3),
        ),
      );
      
      // Reload to get updated data from server
      await _controller.loadDiscoveryPickupMatches(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join game: $e')),
      );
    }
  }
  
  // Show distance picker
  void _showDistancePickerHome() {
    int tempDistance = _maxDistance;
    
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
      child: Column(
                mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
                    'Maximum Distance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
                  const SizedBox(height: 16),
                  Text(
                    tempDistance == 100 ? 'Any Distance' : '$tempDistance miles',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: tempDistance.toDouble(),
                    min: 5,
                    max: 100,
                    divisions: 19,
                    label: tempDistance == 100 ? 'Any' : '$tempDistance miles',
                    onChanged: (value) {
                      setModalState(() {
                        tempDistance = value.round();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                onPressed: () {
                          setModalState(() {
                            tempDistance = 100;
                          });
                        },
                        child: const Text('Any Distance'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _maxDistance = tempDistance;
                            _nearbyFilterActive = tempDistance < 100;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: const Text('Done'),
                      ),
                    ],
            ),
        ],
      ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildSimpleDiscoveryCard(Map<String, dynamic> match) {
    final sport = match['sport'] as String? ?? '';
    final mode = match['mode'] as String? ?? '';
    final startDt = match['start_time'] as DateTime?;
    final venue = match['venue'] as String?;
    final distance = match['distance_miles'] as double?;
    
    String distanceStr = '';
    if (distance != null) {
      if (distance < 1) {
        distanceStr = '${(distance * 5280).round()} ft';
      } else if (distance < 10) {
        distanceStr = '${distance.toStringAsFixed(1)} mi';
      } else {
        distanceStr = '${distance.round()} mi';
      }
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
                Text(
                  _displaySport(sport),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (mode == 'team_vs_team') ...[
                  const Text(' • '),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D7377).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF0D7377)),
                    ),
                    child: const Text(
                      'TEAM GAME',
                      style: TextStyle(
                        color: Color(0xFF0D7377),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (distanceStr.isNotEmpty) ...[
                  const Text(' • '),
                  Text(distanceStr),
                ],
              ],
            ),
            if (startDt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    _formatDateTime(startDt),
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            if (venue != null && venue.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      venue,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isTomorrow = dt.year == now.year && 
                       dt.month == now.month && 
                       dt.day == now.day + 1;
    
    String fmtTime(DateTime d) {
      final h24 = d.hour;
      final m = d.minute.toString().padLeft(2, '0');
      final isPM = h24 >= 12;
      final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
      final ampm = isPM ? 'PM' : 'AM';
      return '$h12:$m $ampm';
    }
    
    if (isToday) return 'Today ${fmtTime(dt)}';
    if (isTomorrow) return 'Tomorrow ${fmtTime(dt)}';
    return '${dt.month}/${dt.day} ${fmtTime(dt)}';
  }
  
  // Build filter buttons for Discover section - "All" first, then Sports, Date, Nearby
  Widget _buildDiscoverFilters() {
    const orangeAccent = Color(0xFFFF6B35);
    
    // Check if any filter is active (if none are active, "All" is selected)
    final bool allSelected = _selectedSportFilter == null && 
                            _selectedDateFilter == null && 
                            !_nearbyFilterActive;
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // "All" filter chip (selected by default when no filters are active)
          _buildFilterChip(
            label: 'All',
            isSelected: allSelected,
            onTap: () {
              setState(() {
                _selectedSportFilter = null;
                _selectedDateFilter = null;
                _nearbyFilterActive = false;
                _maxDistance = 100;
              });
            },
            accentColor: orangeAccent,
          ),
          const SizedBox(width: 8),
          
          // Sports filter
          _buildFilterChip(
            label: _selectedSportFilter != null ? _displaySport(_selectedSportFilter!) : 'Sports',
            isSelected: _selectedSportFilter != null,
            onTap: () => _showSportFilterDialog(),
            accentColor: orangeAccent,
          ),
          const SizedBox(width: 8),
          
          // Date filter
          _buildFilterChip(
            label: _selectedDateFilter != null ? _formatDateHome(_selectedDateFilter!) : 'Date',
            isSelected: _selectedDateFilter != null,
            onTap: () => _showDateFilterDialog(),
            accentColor: orangeAccent,
          ),
          const SizedBox(width: 8),
          
          // Nearby filter
          _buildFilterChip(
            label: _maxDistance < 100 ? '$_maxDistance mi' : 'Nearby',
            isSelected: _nearbyFilterActive || _maxDistance < 100,
            onTap: () => _showDistancePickerHome(),
            accentColor: orangeAccent,
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? accentColor : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _showSportFilterDialog() async {
    final allSports = [
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
    
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
            mainAxisSize: MainAxisSize.min,
        children: [
              // Title
          const Text(
                'Select Sport',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D7377),
                ),
              ),
              const SizedBox(height: 20),
              // Horizontal scrollable chips
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // "All Sports" chip
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildSportChip(
                        label: 'All Sports',
                        isSelected: _selectedSportFilter == null,
                onTap: () {
                  setState(() => _selectedSportFilter = null);
                  Navigator.pop(context);
                },
              ),
                    ),
                    // Sport chips
                    ...allSports.map((sport) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildSportChip(
                        label: _displaySport(sport),
                        isSelected: _selectedSportFilter == sport,
                onTap: () {
                  setState(() => _selectedSportFilter = sport);
                  Navigator.pop(context);
                },
                      ),
              )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSportChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const orangeAccent = Color(0xFFFF6B35);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? orangeAccent : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? orangeAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _showDateFilterDialog() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() {
        _selectedDateFilter = date;
      });
    } else if (_selectedDateFilter != null) {
      // User cancelled - clear filter if they want
      final clear = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear Date Filter?'),
          content: const Text('Do you want to clear the date filter?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep Filter'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        ),
      );
      if (clear == true) {
        setState(() {
          _selectedDateFilter = null;
        });
      }
    }
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
    // Use a one-time flag to prevent infinite loops
    // IMPORTANT: This check must happen BEFORE any rebuilds to prevent infinite loops
    if (!_controller.myGamesTabLoadInitiated) {
      _controller.myGamesTabLoadInitiated = true; // Set flag immediately to prevent multiple calls
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Load team matches if needed
        if (_controller.allMyMatches.isEmpty && !_controller.loadingAllMatches) {
          _controller.loadAllMyMatches();
        }
        
        // Load individual games if needed
        if (_controller.allMyIndividualMatches.isEmpty && !_controller.loadingIndividualMatches) {
          _controller.loadAllMyIndividualMatches();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(''), // Empty title since tab already says "My Games"
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0, // Remove AppBar height to move filter all the way up
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _controller.loadAllMyMatches();
          await _controller.loadAllMyIndividualMatches();
          await _controller.loadAwaitingOpponentConfirmationGames();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            return Stack(
              children: [
                ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 56), // Space for filter banner at top (increased from 48 to 56 to account for filter being moved down)
                  children: [
                    _errorBanner(),
                    _buildFilteredMatchesSection(),
                    const SizedBox(height: 24),
                  ],
                ),
                // Position filter banner at the very top - all the way up
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0), // Move filter down a bit (top: 8)
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50, // Teal green background matching sport sections
                      borderRadius: BorderRadius.circular(12), // Rounded corners on all sides
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: _buildMyGamesFilterBanner(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
  

  Widget _buildMyGamesFilterBanner() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFilterSegment('Current', _myGamesFilter == 'Current'),
          _buildFilterSegment('Past', _myGamesFilter == 'Past'),
          _buildFilterSegment('Cancelled', _myGamesFilter == 'Cancelled'),
          _buildFilterSegment('Hidden', _myGamesFilter == 'Hidden'),
        ],
    );
  }

  Widget _buildFilterSegment(String label, bool isSelected) {
    const orangeAccent = Color(0xFFFF6B35); // Orange accent color matching Trending games filters
    return GestureDetector(
      onTap: () {
        setState(() {
          _myGamesFilter = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? orangeAccent : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? orangeAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredMatchesSection() {
    final isLoading = _controller.loadingAllMatches || _controller.loadingIndividualMatches;
        
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Combine team and individual games
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

    // Show "Awaiting Opponent Confirmation" section first (only for Current filter)
    // Then show regular games grouped by sport
    if (_myGamesFilter == 'Current') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Awaiting Opponent Confirmation Section (team games only)
          _buildAwaitingOpponentConfirmationSection(),
          const SizedBox(height: 24),
          // Regular games grouped by sport
          _buildUnifiedMatchesList(filteredMatches),
        ],
      );
    }

    // For other filters (Past, Cancelled, Hidden), just show the unified list
    return _buildUnifiedMatchesList(filteredMatches);
  }

  Widget _buildAwaitingOpponentConfirmationSection() {
    final awaitingGames = _controller.awaitingOpponentConfirmationGames;

    if (awaitingGames.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.hourglass_empty, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Games Awaiting confirmation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...awaitingGames.map((game) => _buildAwaitingOpponentCard(game)),
      ],
    );
  }

  Widget _buildAwaitingOpponentCard(Map<String, dynamic> game) {
    final sport = game['sport'] as String? ?? '';
    final sportEmoji = _getSportEmoji(sport);
    final teamName = game['team_name'] as String? ?? 'My Team';
    final creatingTeamName = game['creating_team_name'] as String? ?? 'Team';
    final opponentTeams = game['opponent_teams'] as List<dynamic>? ?? [];
    final isOpenChallenge = game['is_open_challenge'] as bool? ?? false;
    final startDt = game['start_time'] as DateTime?;
    final endDt = game['end_time'] as DateTime?;
    final venue = game['venue'] as String?;
    final details = game['details'] as String?;
    final creatorName = game['creator_name'] as String? ?? 'Unknown';
    final creatingTeamId = game['team_id'] as String?; // The team that created the game
    final myTeamId = game['my_team_id'] as String?; // The user's team in this game
    final isUserOnCreatingTeam = creatingTeamId != null && myTeamId == creatingTeamId;

    // Build the message based on whether user is on creating team or invited team
    String gameTitleMessage;
    
    if (isUserOnCreatingTeam) {
      // For Team A (creating team): "<Invite Team name> is checking with <Opponent Team name 1>, <Opponent Team name 2> teams for a match"
      if (isOpenChallenge && opponentTeams.isEmpty) {
        // Open challenge - no specific teams
        gameTitleMessage = '$creatingTeamName is checking for a match';
      } else if (opponentTeams.isNotEmpty) {
        // Specific team invites
        final opponentNamesList = opponentTeams.map((t) => t.toString()).toList();
        final teamsList = opponentNamesList.join(', ');
        gameTitleMessage = '$creatingTeamName is checking with $teamsList teams for a match';
      } else {
        // Fallback
        gameTitleMessage = '$creatingTeamName is checking for a match';
      }
    } else {
      // For Team B/C (invited teams): "<Invite Team name> <Sport> Team is Inviting you <your Team name> team for a match"
      final sportDisplay = _displaySport(sport);
      gameTitleMessage = '$creatingTeamName $sportDisplay Team is Inviting you $teamName team for a match';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade50,
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
                        gameTitleMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Created by: $creatorName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Awaiting',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Team info
            Row(
              children: [
                Icon(Icons.group, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your Team: $teamName',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Opponent info
            Row(
              children: [
                Icon(Icons.sports_soccer, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // If there are specific opponent teams, show them (even if isOpenChallenge is true)
                    // Only show "Open Challenge" if there are no opponent teams
                    (isOpenChallenge && opponentTeams.isEmpty)
                        ? 'Opponent: Open Challenge'
                        : opponentTeams.isNotEmpty
                            ? 'Opponent: ${opponentTeams.join(', ')}'
                            : 'Opponent: Open Challenge',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Date & Time
            if (startDt != null) ...[
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (startDt != null) ...[
                    const SizedBox(width: 16),
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(startDt),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            
            // Venue
            if (venue != null && venue.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: Colors.grey),
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
            
            // Details
            if (details != null && details.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.description, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      details,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            
            // Cancel button (only for admins of the creating team)
            if (isUserOnCreatingTeam && _isAdminForTeam(creatingTeamId)) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _confirmCancelAwaitingGame(game),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Game'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Check if current user is an admin of the given team
  bool _isAdminForTeam(String? teamId) {
    if (teamId == null) return false;
    return _controller.adminTeams.any((team) => team['id'] == teamId);
  }

  Future<void> _confirmCancelAwaitingGame(Map<String, dynamic> game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Game?'),
        content: const Text('This will cancel the game. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final requestId = game['request_id'] as String?;
      if (requestId == null) return;

      await _controller.cancelGameForBothTeams(game);
      
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game cancelled')),
                                    );
      
      // Refresh awaiting games
      await _controller.loadAwaitingOpponentConfirmationGames();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel game: $e')),
      );
    }
  }


  List<Map<String, dynamic>> _getFilteredMatches() {
    final now = DateTime.now();
    // Compare dates only (ignore time) for more accurate filtering
    final today = DateTime(now.year, now.month, now.day);
    final hiddenIds = _controller.hiddenRequestIds;

    // Combine team and individual matches
    // NOTE: Private games are no longer in confirmedTeamMatches (they're only in allMyIndividualMatches),
    // so there should be no duplicates. We still deduplicate as a safety measure.
    final teamMatches = _controller.allMyMatches.isNotEmpty
        ? _controller.allMyMatches
        : _controller.confirmedTeamMatches;
    
    // Deduplicate by request_id as a safety measure (shouldn't be needed anymore, but keeps code robust)
    final seenRequestIds = <String>{};
    final allMatchesToFilter = <Map<String, dynamic>>[];
    
    // Add individual matches first (they have enriched attendance data for private games)
    for (final match in _controller.allMyIndividualMatches) {
      final reqId = match['request_id'] as String?;
      if (reqId != null && !seenRequestIds.contains(reqId)) {
        seenRequestIds.add(reqId);
        allMatchesToFilter.add(match);
      }
    }
    
    // Add team matches (should not overlap with individual matches anymore)
    for (final match in teamMatches) {
      final reqId = match['request_id'] as String?;
      if (reqId != null && !seenRequestIds.contains(reqId)) {
        seenRequestIds.add(reqId);
        allMatchesToFilter.add(match);
      }
    }

    if (kDebugMode) {
      print('[DEBUG] _getFilteredMatches: Filter=$_myGamesFilter, teamMatches=${teamMatches.length}, individualMatches=${_controller.allMyIndividualMatches.length}, deduplicated=${allMatchesToFilter.length}');
    }

    return allMatchesToFilter.where((match) {
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

  Widget _buildUnifiedMatchesList(List<Map<String, dynamic>> matches) {
    // Group matches by sport and sort by date
    final groupedMatches = <String, List<Map<String, dynamic>>>{};
    
    for (final match in matches) {
      final sport = (match['sport'] as String?)?.toLowerCase() ?? 'other';
      if (!groupedMatches.containsKey(sport)) {
        groupedMatches[sport] = [];
      }
      groupedMatches[sport]!.add(match);
    }
    
    // Sort matches within each sport by date (earliest first)
    for (final sportMatches in groupedMatches.values) {
      sportMatches.sort((a, b) {
        final aTime = a['start_time'] as DateTime?;
        final bTime = b['start_time'] as DateTime?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });
    }
    
    // Sort sports alphabetically
    final sortedSports = groupedMatches.keys.toList()..sort();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display matches grouped by sport
          ...sortedSports.expand((sport) {
            final sportMatches = groupedMatches[sport]!;
            return [
              // Sport section with teal green background
              Builder(
                builder: (context) {
                  // Track collapsed sections - if sport is in Set, it's collapsed
                  final isCollapsed = _expandedSportSections.contains(sport);
                  final shouldShow = !isCollapsed; // Show by default, hide if collapsed
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50, // Teal green background
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sport header with white background card - clickable to expand/collapse
                        Card(
                          color: Colors.white,
                          margin: EdgeInsets.zero,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (shouldShow) {
                                  // Currently showing, collapse it
                                  _expandedSportSections.add(sport);
                                } else {
                                  // Currently collapsed, expand it
                                  _expandedSportSections.remove(sport);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      _getSportEmoji(sport),
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                      _displaySport(sport),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                                      ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${sportMatches.length})',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    shouldShow ? Icons.expand_less : Icons.expand_more,
                                    color: Colors.grey.shade600,
                                    size: 20,
                    ),
                  ],
                ),
              ),
                          ),
                        ),
                        // Matches for this sport - show only if not collapsed
                        if (shouldShow) ...[
                          const SizedBox(height: 8),
              ...sportMatches.map((m) => _buildUnifiedMatchCard(m)),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ];
          }),
        ],
      ),
    );
  }

  Widget _buildUnifiedMatchCard(Map<String, dynamic> match) {
    // Determine if this is a team match (has team_a_id) or individual match
    final hasTeamFields = match.containsKey('team_a_id') && match['team_a_id'] != null;
    
    if (hasTeamFields) {
      // Team match - use team match card builder
      final reqId = match['request_id'] as String;
      final isExpanded = _expandedMatchIds.contains(reqId);
      return _buildCollapsibleMatchCard(match, isExpanded);
    } else {
      // Individual match - use individual match card builder
      final reqId = match['request_id'] as String;
      final isExpanded = _expandedMatchIds.contains(reqId);
      return _buildCollapsibleIndividualMatchCard(match, isExpanded);
    }
  }

  Widget _buildMatchCardForFilter(Map<String, dynamic> match) {
    final reqId = match['request_id'] as String;
    final isExpanded = _expandedMatchIds.contains(reqId);
    
    // Show compact summary by default, expandable to full details
    return _buildCollapsibleMatchCard(match, isExpanded);
  }
  
  Widget _buildIndividualMatchesList(List<Map<String, dynamic>> matches) {
    // Group matches by sport and sort by date
    final groupedMatches = <String, List<Map<String, dynamic>>>{};
    
    for (final match in matches) {
      final sport = (match['sport'] as String?)?.toLowerCase() ?? 'other';
      if (!groupedMatches.containsKey(sport)) {
        groupedMatches[sport] = [];
      }
      groupedMatches[sport]!.add(match);
    }
    
    // Sort matches within each sport by date (earliest first)
    for (final sportMatches in groupedMatches.values) {
      sportMatches.sort((a, b) {
        final aTime = a['start_time'] as DateTime?;
        final bTime = b['start_time'] as DateTime?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });
    }
    
    // Sort sports alphabetically
    final sortedSports = groupedMatches.keys.toList()..sort();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your games (${matches.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // Display matches grouped by sport
          ...sortedSports.expand((sport) {
            final sportMatches = groupedMatches[sport]!;
            return [
              // Sport header
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 8),
                child: Row(
                  children: [
                    Text(
                      _getSportEmoji(sport),
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _displaySport(sport),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${sportMatches.length})',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // Matches for this sport
              ...sportMatches.map((m) => _buildIndividualMatchCardForFilter(m)),
              const SizedBox(height: 12),
            ];
          }),
        ],
      ),
    );
  }
  
  Widget _buildIndividualMatchCardForFilter(Map<String, dynamic> match) {
    final reqId = match['request_id'] as String;
    final isExpanded = _expandedMatchIds.contains(reqId);
    
    // Show compact summary by default, expandable to full details
    return _buildCollapsibleIndividualMatchCard(match, isExpanded);
  }
  
  Widget _buildCollapsibleIndividualMatchCard(Map<String, dynamic> match, bool isExpanded) {
    final reqId = match['request_id'] as String;
    final sport = match['sport'] as String? ?? '';
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final status = (match['status'] as String?)?.toLowerCase() ?? '';
    final numPlayers = match['num_players'] as int? ?? 4;
    final acceptedCount = match['accepted_count'] as int? ?? 0;
    final spotsLeft = match['spots_left'] as int? ?? numPlayers;
    final percentage = numPlayers > 0 ? (acceptedCount / numPlayers * 100).round() : 0;
    final visibility = (match['visibility'] as String?)?.toLowerCase() ?? '';
    final myStatus = (match['my_attendance_status'] as String?)?.toLowerCase() ?? '';
    final isOrganizer = _controller.isOrganizerForMatch(match);
    // For pick-up game organizers, if no status exists, treat as "accepted" (You're Going)
    final effectiveStatus = visibility != 'friends_group' && isOrganizer && myStatus.isEmpty
        ? 'accepted'
        : myStatus;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: status == 'cancelled' ? Colors.grey.shade100 : null,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedMatchIds.remove(reqId);
            } else {
              _expandedMatchIds.add(reqId);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compact Summary (always visible)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Game Title with status badge for private games
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                visibility == 'friends_group' ? 'Private Game' : 'Pick-up Game',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                            ),
                            // Status indicator for private games and pick-up games (for creator) - on the right
                            if ((visibility == 'friends_group' && myStatus.isNotEmpty) || 
                                (visibility != 'friends_group' && isOrganizer && effectiveStatus.isNotEmpty)) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: effectiveStatus == 'accepted' 
                                      ? Colors.green.shade50 
                                      : effectiveStatus == 'declined' 
                                          ? Colors.red.shade50 
                                          : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: effectiveStatus == 'accepted' 
                                        ? Colors.green.shade300 
                                        : effectiveStatus == 'declined' 
                                            ? Colors.red.shade300 
                                            : Colors.orange.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      effectiveStatus == 'accepted' 
                                          ? Icons.check_circle 
                                          : effectiveStatus == 'declined' 
                                              ? Icons.cancel 
                                              : Icons.pending,
                                      size: 16,
                                      color: effectiveStatus == 'accepted' 
                                          ? Colors.green.shade700 
                                          : effectiveStatus == 'declined' 
                                              ? Colors.red.shade700 
                                              : Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      effectiveStatus == 'accepted' 
                                          ? 'You\'re Going' 
                                          : effectiveStatus == 'declined' 
                                              ? 'You\'re Not Going' 
                                              : 'Response Pending',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: effectiveStatus == 'accepted' 
                                            ? Colors.green.shade700 
                                            : effectiveStatus == 'declined' 
                                                ? Colors.red.shade700 
                                                : Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            // Tick/X icons for private games with pending status - nicely spaced
                            if (visibility == 'friends_group' && myStatus == 'pending' && !isOrganizer) ...[
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: () => _acceptIndividualGameAttendance(reqId),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                                ),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: () => _declineIndividualGameAttendance(reqId),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.cancel, color: Colors.red, size: 28),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Date & Time
                        if (startDt != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                              ),
                              if (endDt != null) ...[
                            const SizedBox(width: 8),
                                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  '${_formatTime(startDt)} - ${_formatTime(endDt)}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Percentage Bar and Spots Left
              Builder(
                builder: (context) {
                  final isOverbooked = acceptedCount > numPlayers;
                  final displayPercentage = isOverbooked ? 100 : percentage;
                  final additionalAccepted = isOverbooked ? acceptedCount - numPlayers : 0;
                  
                  return Row(
                children: [
                            Expanded(
                    child: StatusBar(
                          percentage: (displayPercentage / 100.0).clamp(0.0, 1.0),
                      height: 8,
                      showPercentage: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                      if (isOverbooked) ...[
                        Text(
                          '100% filled',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getPercentageColor(1.0),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Additional +$additionalAccepted member${additionalAccepted > 1 ? 's' : ''} accepted',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else ...[
                  Text(
                    '$percentage%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getPercentageColor(percentage / 100.0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$spotsLeft spots left',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                    ],
                  );
                },
              ),
              
              // Accept/Decline buttons for pending games (only for non-private games, or when expanded)
              if (myStatus == 'pending' && !isOrganizer && !isExpanded && visibility != 'friends_group') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _acceptIndividualGameAttendance(reqId),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _declineIndividualGameAttendance(reqId),
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('Decline'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              
              // Full Details (only when expanded)
              if (isExpanded) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
                _buildExpandedIndividualMatchDetails(match),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildExpandedIndividualMatchDetails(Map<String, dynamic> match) {
    final reqId = match['request_id'] as String;
    final sport = match['sport'] as String? ?? '';
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final venue = match['venue'] as String?;
    final details = match['details'] as String?;
    final creatorName = match['creator_name'] as String? ?? 'Unknown';
    final numPlayers = match['num_players'] as int? ?? 4;
    final acceptedCount = match['accepted_count'] as int? ?? 0;
    final spotsLeft = match['spots_left'] as int? ?? numPlayers;
    final myStatus = match['my_attendance_status'] as String? ?? 'pending';
    final isOrganizer = _controller.isOrganizerForMatch(match);
    final chatEnabled = match['chat_enabled'] as bool? ?? false;
    final chatMode = match['chat_mode'] as String? ?? 'all_users';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Creator Info and Menu options in same row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Creator Info
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Created by: $creatorName',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            // Menu options
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'hide') {
                  await _confirmHideGame(reqId);
                } else if (v == 'unhide') {
                  await _confirmUnhideGame(reqId);
                } else if (v == 'cancel') {
                  await _confirmCancelIndividualGame(match);
                } else if (v == 'enable_chat') {
                  await _enableChat(reqId, enabled: true);
                } else if (v == 'disable_chat') {
                  await _enableChat(reqId, enabled: false);
                } else if (v == 'chat_all_users') {
                  await _setChatMode(reqId, mode: 'all_users');
                } else if (v == 'chat_admins_only') {
                  await _setChatMode(reqId, mode: 'admins_only');
                }
              },
              itemBuilder: (_) => [
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
                  if (chatEnabled)
                    const PopupMenuItem(
                      value: 'disable_chat',
                      child: Text('Disable Chat'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'enable_chat',
                      child: Text('Enable Chat'),
                    ),
                  if (chatEnabled) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'chat_all_users',
                      child: Row(
                        children: [
                          if (chatMode == 'all_users')
                            const Icon(Icons.check, size: 16),
                          const SizedBox(width: 8),
                          const Text('All Users Can Message'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'chat_admins_only',
                      child: Row(
                        children: [
                          if (chatMode == 'admins_only')
                            const Icon(Icons.check, size: 16),
                          const SizedBox(width: 8),
                          const Text('Admins Only'),
                        ],
                      ),
                    ),
                  ],
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Text('Cancel game'),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        
        // Venue
        if (venue != null && venue.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(venue, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        
        // Game Details
        if (details != null && details.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 14, color: Colors.blue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  details,
                  style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        
        // Player Count Info
        Builder(
          builder: (context) {
            final isOverbooked = acceptedCount > numPlayers;
            final additionalAccepted = isOverbooked ? acceptedCount - numPlayers : 0;
            
            if (isOverbooked) {
              return Text(
                'Looking for $numPlayers players • $acceptedCount accepted • 100% filled • Additional +$additionalAccepted member${additionalAccepted > 1 ? 's' : ''} accepted',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              );
            } else {
              return Text(
          'Looking for $numPlayers players • $acceptedCount accepted • $spotsLeft spots left',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              );
            }
          },
        ),
        const SizedBox(height: 12),
        
        // All Attendees (for both private and public games)
        // For private games: show all invited friends
        // For public games: show all accepted attendees
        Builder(
          builder: (context) {
            final visibility = (match['visibility'] as String?)?.toLowerCase() ?? '';
            final isPublicGame = visibility != 'friends_group' && (match['is_public'] as bool? ?? false || visibility == 'public');
            
            // Show attendees for both private games and public pick-up games
            if (visibility == 'friends_group' || isPublicGame) {
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadAllAttendeesForGame(reqId, match),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  
                  final allAttendees = snapshot.data!;
                  // For public games, only show accepted attendees; for private games, show all
                  final attendees = isPublicGame 
                      ? allAttendees.where((a) => (a['status'] as String?)?.toLowerCase() == 'accepted').toList()
                      : allAttendees;
                  
                  if (attendees.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        isPublicGame 
                            ? 'Players Coming (${attendees.length})'
                            : 'Invited Friends (${attendees.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...attendees.map((attendee) {
                        final userId = attendee['user_id'] as String?;
                        final userName = attendee['user_name'] as String? ?? 'Unknown';
                        final photoUrl = attendee['photo_url'] as String?;
                        final status = (attendee['status'] as String?)?.toLowerCase() ?? 'pending';
                        final isCreator = userId == match['created_by'];
                        
                        String statusText;
                        Color statusColor;
                        IconData statusIcon;
                        
                        if (isCreator) {
                          statusText = 'Creator';
                          statusColor = Colors.blue;
                          statusIcon = Icons.person;
                        } else if (status == 'accepted' || isPublicGame) {
                          // For public games, all shown are accepted; for private, check status
                          statusText = 'Available';
                          statusColor = Colors.green;
                          statusIcon = Icons.check_circle;
                        } else if (status == 'declined') {
                          statusText = 'Not Available';
                          statusColor = Colors.red;
                          statusIcon = Icons.cancel;
                        } else {
                          statusText = 'Pending';
                          statusColor = Colors.orange;
                          statusIcon = Icons.hourglass_empty;
                        }
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?')
                                  : null,
                            ),
                            title: Text(userName),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, color: statusColor, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
        
        // Pending Requests (Organizer only) - only for public games
        Builder(
          builder: (context) {
            final visibility = (match['visibility'] as String?)?.toLowerCase() ?? '';
            if (isOrganizer && visibility != 'friends_group') {
              return FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadPendingRequestsForGame(reqId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              
              final pendingRequests = snapshot.data!;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Pending Requests (${pendingRequests.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...pendingRequests.map((request) {
                    final userId = request['user_id'] as String?;
                    final userName = request['user_name'] as String? ?? 'Unknown';
                    final photoUrl = request['photo_url'] as String?;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null || photoUrl.isEmpty
                              ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?')
                              : null,
                        ),
                        title: Text(userName),
                        subtitle: Text('Wants to join this game'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () => _approveIndividualRequest(reqId, userId!),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _denyIndividualRequest(reqId, userId!),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
        
        // Old pending requests section removed - replaced above
        if (false && isOrganizer) ...[
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadAllAttendeesForGame(reqId, match),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              
              final attendees = snapshot.data!;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Invited Friends (${attendees.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...attendees.map((attendee) {
                    final userId = attendee['user_id'] as String?;
                    final userName = attendee['user_name'] as String? ?? 'Unknown';
                    final photoUrl = attendee['photo_url'] as String?;
                    final status = (attendee['status'] as String?)?.toLowerCase() ?? 'pending';
                    final isCreator = userId == match['created_by'];
                    
                    String statusText;
                    Color statusColor;
                    IconData statusIcon;
                    
                    if (isCreator) {
                      statusText = 'Creator';
                      statusColor = Colors.blue;
                      statusIcon = Icons.person;
                    } else if (status == 'accepted') {
                      statusText = 'Available';
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                    } else if (status == 'declined') {
                      statusText = 'Not Available';
                      statusColor = Colors.red;
                      statusIcon = Icons.cancel;
                    } else {
                      statusText = 'Pending';
                      statusColor = Colors.orange;
                      statusIcon = Icons.hourglass_empty;
                    }
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null || photoUrl.isEmpty
                              ? Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?')
                              : null,
                        ),
                        title: Text(userName),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: statusColor, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ],
        
        
        // Action buttons (Available/Not Available)
        // For private games: Show buttons to allow changing availability (toggle between accepted/declined)
        // For non-private games: Show buttons only if status is not accepted and user is not organizer
        Builder(
          builder: (context) {
            final visibility = (match['visibility'] as String?)?.toLowerCase() ?? '';
            final isPrivateGame = visibility == 'friends_group';
            
            // For private games: Always show buttons (including creator)
            // For non-private games: Only show if status is not accepted and user is not organizer
            if (isPrivateGame) {
              // Private games: Allow all users (including creator) to change their availability
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _respondToIndividualGame(reqId, 'accepted'),
                          icon: Icon(
                            myStatus == 'accepted' ? Icons.check_circle : Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: Text(myStatus == 'accepted' ? 'Available ✓' : 'Available'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: myStatus == 'accepted' ? Colors.green : Colors.grey.shade700,
                            side: BorderSide(
                              color: myStatus == 'accepted' ? Colors.green : Colors.grey.shade400,
                              width: myStatus == 'accepted' ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _respondToIndividualGame(reqId, 'declined'),
                          icon: Icon(
                            myStatus == 'declined' ? Icons.cancel : Icons.cancel_outlined,
                            size: 18,
                          ),
                          label: Text(myStatus == 'declined' ? 'Not Available ✗' : 'Not Available'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: myStatus == 'declined' ? Colors.red : Colors.grey.shade700,
                            side: BorderSide(
                              color: myStatus == 'declined' ? Colors.red : Colors.grey.shade400,
                              width: myStatus == 'declined' ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            } else {
              // Non-private games: Original logic (only show if pending and not organizer)
              if (myStatus != 'accepted' && !isOrganizer) {
                return Column(
                  children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respondToIndividualGame(reqId, 'accepted'),
                  child: const Text('Available'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respondToIndividualGame(reqId, 'declined'),
                  child: const Text('Not Available'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
                );
              }
            }
            return const SizedBox.shrink();
          },
        ),
        
        // Game Action Buttons
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Open Map
            Expanded(
              child: InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening map...')),
                  );
                },
                child: Column(
                  children: [
                    Icon(Icons.map_outlined, color: Colors.orange.shade700, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Open Map',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Reminder
            Expanded(
              child: InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Setting reminder...')),
                  );
                },
                child: Column(
                  children: [
                    Icon(Icons.notifications_outlined, color: Colors.orange.shade700, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Reminder',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Chat
            Expanded(
              child: InkWell(
                onTap: () {
                  if (chatEnabled) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GameChatScreen(
                          requestId: reqId,
                          chatMode: chatMode,
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat is not enabled for this game'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: chatEnabled
                              ? Colors.orange.shade700
                              : Colors.grey.shade400,
                          size: 24,
                        ),
                        if (chatEnabled)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 12,
                        color: chatEnabled
                            ? Colors.orange.shade700
                            : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Leave
            Expanded(
              child: InkWell(
                onTap: () {
                  _showLeaveIndividualGameDialog(reqId);
                },
                child: Column(
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.orange.shade700, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Leave',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
  
  Future<void> _respondToIndividualGame(String requestId, String status) async {
    final supa = Supabase.instance.client;
    final userId = _controller.currentUserId;
    if (userId == null) return;

    try {
      // Check if record already exists
      final existingRecord = await supa
          .from('individual_game_attendance')
          .select('request_id, user_id')
          .eq('request_id', requestId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existingRecord != null) {
        // Record exists, update it
      await supa
          .from('individual_game_attendance')
            .update({
              'status': status,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('request_id', requestId)
            .eq('user_id', userId);
      } else {
        // Record doesn't exist, insert it
        await supa
            .from('individual_game_attendance')
            .insert({
            'request_id': requestId,
            'user_id': userId,
            'status': status,
          });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'accepted' ? 'You are now available!' : 'Marked as not available'),
        ),
      );
      
      await _controller.loadAllMyIndividualMatches();
    } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update availability: $e')),
      );
    }
  }
  
  Future<void> _confirmCancelIndividualGame(Map<String, dynamic> match) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this game?'),
        content: const Text('This will cancel the game for everyone.'),
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
      final supa = Supabase.instance.client;
      final reqId = match['request_id'] as String;
      
      try {
        await supa
            .from('instant_match_requests')
            .update({
              'status': 'cancelled',
              'last_updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', reqId);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game cancelled')),
        );
        await _controller.loadAllMyIndividualMatches();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel game: $e')),
        );
      }
    }
  }
  
  Future<List<Map<String, dynamic>>> _loadAllAttendeesForGame(String requestId, Map<String, dynamic> match) async {
    final supa = Supabase.instance.client;
    
    try {
      // For private games, we need to get ALL invited friends from the friends group
      // and merge with their attendance status
      // Always query friends_group_id from the database to ensure we have it
      // (match data might not include it for invited users)
      String? friendsGroupId;
      String visibility = '';
      
      String? creatorId;
      try {
        final requestData = await supa
            .from('instant_match_requests')
            .select('friends_group_id, visibility, creator_id, created_by')
            .eq('id', requestId)
            .maybeSingle();
        
        if (requestData != null) {
          friendsGroupId = requestData['friends_group_id'] as String?;
          visibility = (requestData['visibility'] as String?)?.toLowerCase() ?? '';
          creatorId = requestData['creator_id'] as String? ?? requestData['created_by'] as String?;
          
          // Fallback to match data if database query didn't return visibility
          if (visibility.isEmpty) {
            visibility = (match['visibility'] as String?)?.toLowerCase() ?? '';
          }
          if (creatorId == null) {
            creatorId = match['created_by'] as String?;
          }
        } else {
          // Fallback to match data if database query failed
          friendsGroupId = match['friends_group_id'] as String?;
          visibility = (match['visibility'] as String?)?.toLowerCase() ?? '';
          creatorId = match['created_by'] as String?;
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DEBUG] Error loading request data, using match data: $e');
        }
        // Fallback to match data
        friendsGroupId = match['friends_group_id'] as String?;
        visibility = (match['visibility'] as String?)?.toLowerCase() ?? '';
        creatorId = match['created_by'] as String?;
      }
      
      if (kDebugMode) {
        print('[DEBUG] Loading attendees for request $requestId');
        print('[DEBUG] Visibility: $visibility, Friends Group ID: $friendsGroupId');
      }
      
      Set<String> allInvitedUserIds = {};
      
      // If this is a private game with a friends group, get all group members
      if (visibility == 'friends_group' && friendsGroupId != null && friendsGroupId.isNotEmpty) {
        try {
          final groupMembers = await supa
              .from('friends_group_members')
              .select('user_id')
              .eq('group_id', friendsGroupId);
          
          if (groupMembers is List) {
            for (final member in groupMembers) {
              final memberId = member['user_id'] as String?;
              if (memberId != null) {
                allInvitedUserIds.add(memberId);
              }
            }
          }
          if (kDebugMode) {
            print('[DEBUG] Loaded ${allInvitedUserIds.length} members from friends group $friendsGroupId');
            print('[DEBUG] Group member IDs: ${allInvitedUserIds.toList()}');
          }
        } catch (e) {
          if (kDebugMode) {
            print('[DEBUG] Error loading friends group members: $e');
          }
        }
      }
      
      // Get all attendance records ordered by updated_at DESC to get latest status first
      // This is important for private games created with individual friends (no group)
      // ALWAYS load attendance records - they contain all invited users for private games
      // NOTE: RLS might restrict this to only current user's records, so we need a workaround
      List<Map<String, dynamic>> attendanceRows = [];
      try {
        final attendanceResult = await supa
            .from('individual_game_attendance')
            .select('user_id, status, updated_at, created_at, invited_by')
            .eq('request_id', requestId)
            .order('updated_at', ascending: false);
        
        if (attendanceResult is List) {
          attendanceRows = attendanceResult;
        }
        
        if (kDebugMode) {
          print('[DEBUG] Loaded ${attendanceRows.length} attendance records for request $requestId');
          print('[DEBUG] Current user: ${supa.auth.currentUser?.id}');
          print('[DEBUG] Creator ID: $creatorId');
        }
        
        // If RLS is blocking and we got fewer records than expected for a private game,
        // try alternative approaches to get all invited users
        final currentUserId = supa.auth.currentUser?.id;
        
        if (visibility == 'friends_group' && creatorId != null && currentUserId != null) {
          // Check if RLS is blocking (we should see more than just our own record + creator)
          final expectedMinimumRecords = 2; // At least creator + current user
          if (attendanceRows.length < expectedMinimumRecords || 
              (attendanceRows.length == expectedMinimumRecords && (friendsGroupId == null || friendsGroupId.isEmpty))) {
            
            if (kDebugMode) {
              print('[DEBUG] RLS appears to be blocking - only got ${attendanceRows.length} record(s)');
              print('[DEBUG] Attempting workaround for private game...');
            }
            
            // WORKAROUND: Since RLS blocks direct queries, we need to:
            // 1. Get all user_ids from attendance records using a different query strategy
            // 2. Try querying as if we're looking for all records where invited_by = creator
            //    (This might work if RLS allows seeing records where we were invited)
            
            // Strategy 1: Try querying all records where we're the invited user
            // (This should work since RLS typically allows seeing your own invitations)
            try {
              // Since we can see our own record, get all records by checking request_id
              // But if RLS blocks, try using the invited_by field in a join-like approach
              final allRecordsByRequest = await supa
                  .from('individual_game_attendance')
                  .select('user_id, status, updated_at, created_at, invited_by')
                  .eq('request_id', requestId)
                  .order('updated_at', ascending: false);
              
              if (allRecordsByRequest is List && allRecordsByRequest.length > attendanceRows.length) {
                if (kDebugMode) {
                  print('[DEBUG] Workaround Strategy 1 successful - got ${allRecordsByRequest.length} records');
                }
                attendanceRows = allRecordsByRequest;
              } else {
                // Strategy 2: Since all records have same invited_by (creator), 
                // we can't query by that alone if RLS blocks. 
                // Instead, we need to get user IDs from what we know:
                // - The creator is always invited
                // - We (current user) are invited
                // - If there's a friends group, get members from there
                // - For individual friends, we need another approach
                
                if (kDebugMode) {
                  print('[DEBUG] Strategy 1 failed, trying alternative approach...');
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('[DEBUG] Workaround query failed: $e');
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DEBUG] Error loading attendance records: $e');
        }
      }

      // Create a map of user_id -> latest status
      final Map<String, String> statusMap = {};
      
      // ALWAYS include the creator in the list (they're always invited)
      if (creatorId != null && creatorId.isNotEmpty) {
        allInvitedUserIds.add(creatorId);
        // Creator is always 'accepted' for private games
        statusMap[creatorId] = 'accepted';
        if (kDebugMode) {
          print('[DEBUG] Added creator $creatorId with status accepted');
        }
      }
      
      // Process all attendance records - this gives us ALL invited users
      for (final row in attendanceRows) {
        final uid = row['user_id'] as String?;
        if (uid != null && uid.isNotEmpty) {
          // Only update if we don't have a status yet (to get the latest due to ordering)
          if (!statusMap.containsKey(uid)) {
            final status = (row['status'] as String?)?.toLowerCase() ?? 'pending';
            statusMap[uid] = status;
          }
          // ALWAYS add to the set of invited users (whether from group or individual selection)
          // This ensures we get ALL invited users for private games
          allInvitedUserIds.add(uid);
          
          if (kDebugMode) {
            print('[DEBUG] Added user $uid with status ${statusMap[uid]}');
          }
        }
      }
      
      if (kDebugMode) {
        print('[DEBUG] Processed ${attendanceRows.length} attendance records');
        print('[DEBUG] Total unique users from attendance: ${allInvitedUserIds.length}');
        print('[DEBUG] All invited user IDs: ${allInvitedUserIds.toList()}');
        
        // Warn if RLS might be blocking
        if (visibility == 'friends_group' && (friendsGroupId == null || friendsGroupId.isEmpty)) {
          // For private games with individual friends, if we see fewer than expected records,
          // RLS is likely blocking
          if (attendanceRows.length <= 2) {
            print('[DEBUG] ⚠️ WARNING: RLS may be blocking attendance records');
            print('[DEBUG] Only seeing ${attendanceRows.length} record(s). Expected to see all invited users.');
            print('[DEBUG] The RLS policy on individual_game_attendance should allow:');
            print('[DEBUG]   - Users to see their own records (user_id = auth.uid())');
            print('[DEBUG]   - Users to see all records for games they are invited to');
            print('[DEBUG]   Example policy: request_id IN (SELECT request_id FROM individual_game_attendance WHERE user_id = auth.uid())');
          }
        }
      }
      
      // For private games created with individual friends (no friends_group_id),
      // allInvitedUserIds will be populated from attendance records above
      // For private games with a friends group, we have both group members and attendance records
      
      // IMPORTANT: If RLS is blocking and we can't see all attendance records,
      // we can only show what we have access to. The database RLS policy needs to be fixed
      // to allow invited users to see all attendance records for games they're invited to.
      
      // If we have no invited users at all, return empty
      if (allInvitedUserIds.isEmpty) {
        if (kDebugMode) {
          print('[DEBUG] No invited users found - returning empty list');
        }
        return [];
      }

      final userIds = allInvitedUserIds.toList();
      
      if (kDebugMode) {
        print('[DEBUG] Total invited users: ${userIds.length}');
        print('[DEBUG] User IDs: $userIds');
        print('[DEBUG] Status map: $statusMap');
      }

      // Get user details for all invited users
      List<Map<String, dynamic>> users = [];
      try {
        final usersResult = await supa
            .from('users')
            .select('id, full_name, photo_url')
            .inFilter('id', userIds);
        
        if (usersResult is List) {
          users = usersResult;
        }
        
        if (kDebugMode) {
          print('[DEBUG] Loaded ${users.length} user details from database for ${userIds.length} user IDs');
          if (users.length != userIds.length) {
            print('[DEBUG] WARNING: Mismatch - expected ${userIds.length} users but got ${users.length}');
            print('[DEBUG] Expected IDs: $userIds');
            print('[DEBUG] Got user IDs: ${users.map((u) => u['id']).toList()}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[DEBUG] Error loading user details: $e');
        }
      }
      
      if (users.isNotEmpty) {
        // Return all users with their latest status (or 'pending' if no attendance record)
        final result = users.map((u) {
          final userId = u['id'] as String;
          final status = statusMap[userId] ?? 'pending';
          if (kDebugMode) {
            print('[DEBUG] Mapping user: ${u['full_name']} (ID: $userId), Status: $status');
          }
          return {
            'user_id': userId,
            'user_name': u['full_name'] ?? 'Unknown',
            'photo_url': u['photo_url'],
            'status': status, // Default to 'pending' if no attendance record
          };
        }).toList();
        
        // Sort by name for consistent display
        result.sort((a, b) {
          final nameA = (a['user_name'] as String? ?? '').toLowerCase();
          final nameB = (b['user_name'] as String? ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        });
        
        if (kDebugMode) {
          print('[DEBUG] Returning ${result.length} attendees');
          print('[DEBUG] Final attendee list: ${result.map((r) => '${r['user_name']} (${r['status']})').toList()}');
        }
        
        return result;
      }
      
      // If no users found, return empty list
      if (kDebugMode) {
        print('[DEBUG] No users found in database - returning empty list');
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('[DEBUG] Error loading all attendees: $e');
      }
      return [];
    }
  }
  
  Future<List<Map<String, dynamic>>> _loadPendingRequestsForGame(String requestId) async {
    final supa = Supabase.instance.client;
    
    try {
      // Get pending attendance records
      final pendingRows = await supa
          .from('individual_game_attendance')
          .select('user_id')
          .eq('request_id', requestId)
          .eq('status', 'pending');

      if (pendingRows is! List || pendingRows.isEmpty) {
        return [];
      }

      final userIds = pendingRows
          .map<String?>((r) => r['user_id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();

      if (userIds.isEmpty) return [];

      // Get user details
      final users = await supa
          .from('users')
          .select('id, full_name, photo_url')
          .inFilter('id', userIds);

      if (users is List) {
        return users.map((u) => {
          'user_id': u['id'],
          'user_name': u['full_name'] ?? 'Unknown',
          'photo_url': u['photo_url'],
        }).toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }
  
  Future<void> _approveIndividualRequest(String requestId, String userId) async {
    try {
      await _controller.approveIndividualGameRequest(
        requestId: requestId,
        userId: userId,
        approve: true,
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request approved!')),
      );
      
      // Refresh the game view
      await _controller.loadAllMyIndividualMatches();
      setState(() {}); // Refresh UI
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve: $e')),
      );
    }
  }
  
  Future<void> _acceptIndividualGameAttendance(String requestId, {bool closeDialog = false}) async {
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) return;

      // Immediately remove from controller lists for instant UI update (optimistic update)
      _controller.pendingIndividualGames.removeWhere((g) => g['request_id'] == requestId);
      if (!mounted) return;
      setState(() {});

      // Update user's own attendance status to accepted
      await supa
          .from('individual_game_attendance')
          .update({
            'status': 'accepted',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('request_id', requestId)
          .eq('user_id', userId);

      // Reload to get fresh data
      await _controller.loadPendingIndividualGames();
      await _controller.loadAllMyIndividualMatches();

      if (!mounted) return;
      setState(() {}); // Refresh UI
      
      // Close dialog if requested
      if (closeDialog && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You marked yourself as available!')),
      );
    } catch (e) {
      // Reload on error to restore correct state
      await _controller.loadPendingIndividualGames();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update availability: $e')),
      );
    }
  }

  Future<void> _declineIndividualGameAttendance(String requestId, {bool closeDialog = false}) async {
    try {
      final supa = Supabase.instance.client;
      final userId = supa.auth.currentUser?.id;
      if (userId == null) return;

      // Immediately remove from controller lists for instant UI update (optimistic update)
      _controller.pendingIndividualGames.removeWhere((g) => g['request_id'] == requestId);
      if (!mounted) return;
      setState(() {});

      // Update user's own attendance status to declined
      await supa
          .from('individual_game_attendance')
          .update({
            'status': 'declined',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('request_id', requestId)
          .eq('user_id', userId);

      // Reload to get fresh data
      await _controller.loadPendingIndividualGames();
      await _controller.loadAllMyIndividualMatches();

      if (!mounted) return;
      setState(() {}); // Refresh UI
      
      // Close dialog if requested
      if (closeDialog && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You marked yourself as not available')),
      );
    } catch (e) {
      // Reload on error to restore correct state
      await _controller.loadPendingIndividualGames();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update availability: $e')),
      );
    }
  }

  Future<void> _denyIndividualRequest(String requestId, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deny Request?'),
        content: const Text('Are you sure you want to deny this join request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deny'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _controller.approveIndividualGameRequest(
        requestId: requestId,
        userId: userId,
        approve: false,
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request denied')),
      );
      
      // Refresh the game view
      await _controller.loadAllMyIndividualMatches();
      setState(() {}); // Refresh UI
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to deny: $e')),
      );
    }
  }
  
  Future<void> _showLeaveIndividualGameDialog(String requestId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text('This will mark you as "Not Available" and you will no longer be part of this game.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Leave Game'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _respondToIndividualGame(requestId, 'declined');
    }
  }
  
  Widget _buildCollapsibleMatchCard(Map<String, dynamic> match, bool isExpanded) {
    final reqId = match['request_id'] as String;
    final teamAName = match['team_a_name'] as String? ?? 'Team A';
    final teamBName = match['team_b_name'] as String? ?? 'Team B';
    final sport = match['sport'] as String? ?? '';
    final startDt = match['start_time'] as DateTime?;
    final endDt = match['end_time'] as DateTime?;
    final status = (match['status'] as String?)?.toLowerCase() ?? '';
    
    // Calculate game-level percentage (based on accepted players only)
    final teamAPlayers = (match['team_a_players'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final teamBPlayers = (match['team_b_players'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final expectedPlayers = match['expected_players_per_team'] as int? ?? 
        SportDefaults.getExpectedPlayersPerTeamSync(sport);
    
    // Count only accepted players
    final teamAAccepted = teamAPlayers.where((p) => (p['status'] as String?)?.toLowerCase() == 'accepted').length;
    final teamBAccepted = teamBPlayers.where((p) => (p['status'] as String?)?.toLowerCase() == 'accepted').length;
    final totalAccepted = teamAAccepted + teamBAccepted;
    final totalExpected = expectedPlayers * 2;
    final gamePercentage = totalExpected > 0 ? (totalAccepted / totalExpected * 100).round() : 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: status == 'cancelled' ? Colors.grey.shade100 : null,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedMatchIds.remove(reqId);
            } else {
              _expandedMatchIds.add(reqId);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compact Summary (always visible)
              Row(
                children: [
                            Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Team A vs Team B
                        Text(
                          '$teamAName vs $teamBName',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Date & Time
                        if (startDt != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                              ),
                              if (endDt != null) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  '${_formatTime(startDt)} - ${_formatTime(endDt)}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ],
                          ],
                        ),
                      ],
                    ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Percentage Bar
              Row(
                children: [
                  Expanded(
                    child: StatusBar(
                      percentage: gamePercentage / 100.0, // Convert 0-100 to 0.0-1.0
                      height: 8,
                      showPercentage: false, // We'll show it separately
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$gamePercentage%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getPercentageColor(gamePercentage / 100.0),
                    ),
                  ),
                ],
              ),
              
              // Full Details (only when expanded)
              if (isExpanded) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                _buildExpandedMatchDetails(match),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildExpandedMatchDetails(Map<String, dynamic> match) {
    // For interactive matches, show full details. For past/cancelled, show basic info.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startTime = match['start_time'] as DateTime?;
    DateTime? matchDate;
    if (startTime != null) {
      matchDate = DateTime(startTime.year, startTime.month, startTime.day);
    }
    final isTodayOrFuture = matchDate != null && 
        (matchDate.isAfter(today) || matchDate.isAtSameMomentAs(today));
    
    // For Current/Hidden tabs with future games, use full card content
    if ((_myGamesFilter == 'Current' || _myGamesFilter == 'Hidden') && isTodayOrFuture) {
      return _buildFullMatchCardContent(match);
    }
    
    // For Past/Cancelled, show basic info only
    return _buildBasicMatchInfo(match);
  }
  
  Widget _buildFullMatchCardContent(Map<String, dynamic> match) {
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

    final teamAPlayers = (match['team_a_players'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final teamBPlayers = (match['team_b_players'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final uid = _controller.currentUserId;

    final myStatusA = teamAPlayers
        .where((p) => p['user_id'] == uid)
        .map((p) => p['status'] as String?)
        .firstWhere((x) => x != null, orElse: () => null);
    final myStatusB = teamBPlayers
        .where((p) => p['user_id'] == uid)
        .map((p) => p['status'] as String?)
        .firstWhere((x) => x != null, orElse: () => null);

    final myTeamId = match['my_team_id'] as String? ??
        (myStatusA != null ? teamAId : (myStatusB != null ? teamBId : teamAId));

    final aCounts = _statusCounts(teamAPlayers);
    final bCounts = _statusCounts(teamBPlayers);

    final isOrganizer = _controller.isOrganizerForMatch(match);
    final canSendReminder = _controller.canSendReminderForMatch(match);
    
    // Check if user is admin of either team
    final isAdminA = teamAPlayers.any((p) => 
      p['user_id'] == uid && (p['is_admin'] as bool? ?? false));
    final isAdminB = teamBPlayers.any((p) => 
      p['user_id'] == uid && (p['is_admin'] as bool? ?? false));
    final isAdmin = isAdminA || isAdminB;
    
    final chatEnabled = match['chat_enabled'] as bool? ?? false;
    final chatMode = match['chat_mode'] as String? ?? 'all_users';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Menu options
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
                } else if (v == 'enable_chat') {
                  await _enableChat(reqId, enabled: true);
                } else if (v == 'disable_chat') {
                  await _enableChat(reqId, enabled: false);
                } else if (v == 'chat_all_users') {
                  await _setChatMode(reqId, mode: 'all_users');
                } else if (v == 'chat_admins_only') {
                  await _setChatMode(reqId, mode: 'admins_only');
                } else if (v == 'toggle_team_a_roster') {
                  await _toggleTeamRosterPrivacy(reqId, match, team: 'a');
                } else if (v == 'toggle_team_b_roster') {
                  await _toggleTeamRosterPrivacy(reqId, match, team: 'b');
                }
              },
              itemBuilder: (_) => [
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
                if (isAdmin) ...[
                  // Allow admins to edit expected players for confirmed team games
                  if (!isOrganizer) ...[
                    const PopupMenuItem(
                      value: 'edit_players',
                      child: Text('Edit expected players'),
                    ),
                  ],
                  const PopupMenuDivider(),
                  // Roster privacy toggle - only show for admin's own team
                  if (isAdminA) ...[
                    PopupMenuItem(
                      value: 'toggle_team_a_roster',
                      child: Row(
                        children: [
                          if ((match['show_team_a_roster'] as bool? ?? false))
                            const Icon(Icons.check, size: 16),
                          const SizedBox(width: 8),
                          Text((match['show_team_a_roster'] as bool? ?? false)
                              ? 'Show Team A Roster to Team B'
                              : 'Hide Team A Roster from Team B'),
                        ],
                      ),
                    ),
                  ],
                  if (isAdminB) ...[
                    PopupMenuItem(
                      value: 'toggle_team_b_roster',
                      child: Row(
                        children: [
                          if ((match['show_team_b_roster'] as bool? ?? false))
                            const Icon(Icons.check, size: 16),
                          const SizedBox(width: 8),
                          Text((match['show_team_b_roster'] as bool? ?? false)
                              ? 'Show Team B Roster to Team A'
                              : 'Hide Team B Roster from Team A'),
                        ],
                      ),
                    ),
                  ],
                  const PopupMenuDivider(),
                  if (chatEnabled)
                    const PopupMenuItem(
                      value: 'disable_chat',
                      child: Text('Disable Chat'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'enable_chat',
                      child: Text('Enable Chat'),
                    ),
                  if (chatEnabled) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'chat_all_users',
                      child: Row(
                        children: [
                          if (chatMode == 'all_users')
                            const Icon(Icons.check, size: 16),
                          const SizedBox(width: 8),
                          const Text('All Users Can Message'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'chat_admins_only',
                      child: Row(
                        children: [
                          if (chatMode == 'admins_only')
                            const Icon(Icons.check, size: 16),
                          const SizedBox(width: 8),
                          const Text('Admins Only'),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
        
        // Venue
        if (venue != null && venue.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(venue, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        
        // Creator Info
        Row(
          children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(
              'Created by: ${match['creator_name'] ?? 'Unknown'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Game Details
        if (match['details'] != null && (match['details'] as String).isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 14, color: Colors.blue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  match['details'] as String,
                  style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        
        // Expected players info
        Builder(
          builder: (context) {
            final matchSpecific = match['expected_players_per_team'] as int?;
            final expected = matchSpecific ?? SportDefaults.getExpectedPlayersPerTeamSync(sport);
            return Text(
              'Expected: $expected players per team',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            );
          },
        ),
        const SizedBox(height: 12),
        
        // Team A
        Builder(
          builder: (context) {
            final isUserOnTeamA = myTeamId == teamAId;
            final showTeamARoster = match['show_team_a_roster'] as bool? ?? false;
            
            // Show full roster if user is on Team A OR Team A admin has enabled visibility
            final showFullRoster = isUserOnTeamA || showTeamARoster;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Team $teamAName', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${aCounts['accepted']}/${teamAPlayers.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildTeamRosterDisplay(
                  players: teamAPlayers,
                  teamName: teamAName,
                  showRoster: showFullRoster,
                  counts: aCounts,
                ),
              ],
            );
          },
        ),
        
        const SizedBox(height: 12),
        
        // Team B
        Builder(
          builder: (context) {
            final isUserOnTeamA = myTeamId == teamAId;
            final showTeamBRoster = match['show_team_b_roster'] as bool? ?? false;
            
            // Show full roster if user is on Team B OR Team B admin has enabled visibility
            final showFullRoster = !isUserOnTeamA || showTeamBRoster;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Team $teamBName', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      '${bCounts['accepted']}/${teamBPlayers.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildTeamRosterDisplay(
                  players: teamBPlayers,
                  teamName: teamBName,
                  showRoster: showFullRoster,
                  counts: bCounts,
                ),
              ],
            );
          },
        ),
        
        const SizedBox(height: 12),
        
        // Send reminder (if applicable)
        if (canSendReminder && myTeamId != null) ...[
                      OutlinedButton.icon(
                                onPressed: () async {
              await _controller.sendReminderToTeams(
                requestId: reqId,
                teamId: myTeamId,
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reminder sent')),
              );
            },
            icon: const Icon(Icons.notifications_active_outlined, size: 16),
            label: const Text('Send reminder'),
          ),
          const SizedBox(height: 8),
        ],
        
        // Action buttons
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
          ],
        ),
        
        // Switch side button
        if (canSwitchSide && myTeamId != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              // Determine the other team
              final otherTeamId = myTeamId == teamAId ? teamBId : teamAId;
              if (otherTeamId != null) {
                _switchSide(
                  requestId: reqId,
                  newTeamId: otherTeamId,
                );
              }
            },
            icon: const Icon(Icons.swap_horiz, size: 16),
            label: const Text('Switch to other team'),
          ),
        ],
        
        // Game Action Buttons
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Open Map
            Expanded(
              child: InkWell(
                onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening map...')),
                  );
                },
                child: Column(
                  children: [
                    Icon(Icons.map_outlined, color: Colors.orange.shade700, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Open Map',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Reminder
            Expanded(
              child: InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Setting reminder...')),
                  );
                },
                child: Column(
                  children: [
                    Icon(Icons.notifications_outlined, color: Colors.orange.shade700, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Reminder',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Chat
            Expanded(
              child: InkWell(
                onTap: () {
                  final chatEnabled = match['chat_enabled'] as bool? ?? false;
                  if (chatEnabled) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GameChatScreen(
                          requestId: reqId,
                          chatMode: match['chat_mode'] as String? ?? 'all_users',
                          teamAId: teamAId,
                          teamBId: teamBId,
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat is not enabled for this game'),
                        duration: Duration(seconds: 2),
                      ),
                                    );
                                  }
                                },
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: (match['chat_enabled'] as bool? ?? false)
                              ? Colors.orange.shade700
                              : Colors.grey.shade400,
                          size: 24,
                        ),
                        if (match['chat_enabled'] as bool? ?? false)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              ),
                            ),
                          ],
                        ),
                    const SizedBox(height: 4),
                    Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 12,
                        color: (match['chat_enabled'] as bool? ?? false)
                            ? Colors.orange.shade700
                            : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Leave/Cancel
            Expanded(
              child: InkWell(
                onTap: () {
                  _showLeaveGameDialog(reqId);
                },
                child: Column(
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.orange.shade700, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Leave',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
  
  Widget _buildBasicMatchInfo(Map<String, dynamic> match) {
    final venue = match['venue'] as String?;
    final teamAPlayers = (match['team_a_players'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final teamBPlayers = (match['team_b_players'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final teamAName = match['team_a_name'] as String? ?? 'Team A';
    final teamBName = match['team_b_name'] as String? ?? 'Team B';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (venue != null && venue.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 14),
              const SizedBox(width: 4),
              Expanded(child: Text(venue, style: const TextStyle(fontSize: 13))),
            ],
          ),
          const SizedBox(height: 8),
        ],
        
        Text('Team $teamAName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        ...teamAPlayers.map((p) => _buildPlayerRow(p)),
        
        const SizedBox(height: 12),
        
        Text('Team $teamBName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        ...teamBPlayers.map((p) => _buildPlayerRow(p)),
      ],
    );
  }
  
  /// Build a privacy-aware team roster display
  /// If showRoster is false, shows only counts instead of player names
  Widget _buildTeamRosterDisplay({
    required List<Map<String, dynamic>> players,
    required String teamName,
    required bool showRoster,
    required Map<String, int> counts,
  }) {
    if (showRoster) {
      // Show full roster with player names
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...players.map((p) => _buildPlayerRow(p)),
        ],
      );
    } else {
      // Show only counts for privacy
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPrivacyCountsDisplay(counts: counts),
        ],
      );
    }
  }

  /// Build privacy counts display (available, not available, pending)
  Widget _buildPrivacyCountsDisplay({required Map<String, int> counts}) {
    final available = counts['accepted'] ?? 0;
    final notAvailable = counts['declined'] ?? 0;
    final pending = counts['pending'] ?? 0;
    final total = available + notAvailable + pending;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'Roster hidden for privacy',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (available > 0)
            _buildCountRow(
              icon: Icons.check_circle,
              color: Colors.green,
              label: 'Available',
              count: available,
              total: total,
            ),
          if (notAvailable > 0)
            _buildCountRow(
              icon: Icons.cancel,
              color: Colors.red,
              label: 'Not Available',
              count: notAvailable,
              total: total,
            ),
          if (pending > 0)
            _buildCountRow(
              icon: Icons.help_outline,
              color: Colors.orange,
              label: 'Yet to Respond',
              count: pending,
              total: total,
            ),
        ],
      ),
    );
  }

  Widget _buildCountRow({
    required IconData icon,
    required Color color,
    required String label,
    required int count,
    required int total,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (total > 0) ...[
            Text(
              ' / $total',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerRow(Map<String, dynamic> player) {
    final name = player['name'] as String? ?? 'Unknown';
    final status = (player['status'] as String?)?.toLowerCase() ?? 'pending';
    final isAdmin = player['is_admin'] as bool? ?? false;
    
    IconData icon;
    Color color;
    switch (status) {
      case 'accepted':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'declined':
        icon = Icons.cancel;
        color = Colors.red;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.orange;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(name, style: const TextStyle(fontSize: 13)),
          if (isAdmin) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.shade300, width: 1),
              ),
              child: Text(
                'Admin',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
    
    // Check if user is admin of either team
    final isAdminA = teamAPlayers.any((p) => 
      p['user_id'] == uid && (p['is_admin'] as bool? ?? false));
    final isAdminB = teamBPlayers.any((p) => 
      p['user_id'] == uid && (p['is_admin'] as bool? ?? false));
    final isAdmin = isAdminA || isAdminB;

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
                    // Also allow admins (non-organizers) to edit expected players for confirmed team games
                    if (!isOrganizer && isAdmin) ...[
                      const PopupMenuItem(
                        value: 'edit_players',
                        child: Text('Edit expected players'),
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
        return _buildMyGamesTab(); // Discover tab removed, My Games is now index 1
      case 2:
        return ChatScreen(controller: _controller); // Chat is now index 2
      case 3:
        return const UserProfileScreen(); // Profile is now index 3
      default:
        return _buildHomeTab();
    }
  }

  void _onItemTapped(int index) {
    setState(() => _controller.selectedIndex = index);
    
    // Reload discovery matches when needed (now embedded in Home tab)
    // Removed Discover tab-specific reload since it's now in Home tab
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Scaffold(
          body: _buildCurrentTabBody(),
          bottomNavigationBar: _buildModernBottomNav(),
        );
      },
    );
  }
  
  // Modern Bottom Navigation Bar - Floating pill, fixed height, active tab orange, others white
  Widget _buildModernBottomNav() {
    const orange = Color(0xFFFF8A30); // Orange for active tab
    const white = Color(0xFFFFFFFF); // White for inactive tabs
    const teal = Color(0xFF0E8E8E); // Teal pill background (matches Profile bg)
    
    return Container(
      height: 72, // Fixed height
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Floating pill with margin
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: teal, // Teal background for floating pill
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24), // Rounded top corners matching white card
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24), // Rounded bottom corners
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            icon: Icons.home_filled,
            label: 'Home',
            index: 0,
            isSelected: _controller.selectedIndex == 0,
            activeColor: orange,
            inactiveColor: white, // others = white
          ),
          _buildNavItem(
            icon: Icons.sports_esports,
            label: 'My Games',
            index: 1,
            isSelected: _controller.selectedIndex == 1,
            activeColor: orange,
            inactiveColor: white, // others = white
          ),
          _buildNavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            index: 2,
            isSelected: _controller.selectedIndex == 2,
            activeColor: orange,
            inactiveColor: white, // others = white
          ),
          _buildNavItem(
            icon: Icons.person,
            label: 'Profile',
            index: 3,
            isSelected: _controller.selectedIndex == 3,
            activeColor: orange,
            inactiveColor: white, // others = white
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isSelected,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent, // Orange = active, transparent = inactive
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : inactiveColor, // White icon on orange, grey on white
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.white, // White text on orange background
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

