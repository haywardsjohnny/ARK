import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'home_tabs/home_tabs_controller.dart';
import '../../utils/sport_defaults.dart';
import '../../services/location_service.dart';
import 'user_profile_screen.dart';

class CreateGameScreen extends StatefulWidget {
  final HomeTabsController controller;
  
  const CreateGameScreen({super.key, required this.controller});

  @override
  State<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends State<CreateGameScreen> {
  int _currentStep = 0; // 0 = Game Type Selector, 1 = Form
  String? _selectedGameType; // 'team' or 'individual'
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _isAdmin = widget.controller.adminTeams.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep == 0) {
      return _buildGameTypeSelector();
    } else {
      if (_selectedGameType == 'team') {
        return _isAdmin 
            ? _buildTeamVsTeamAdminForm()
            : _buildTeamVsTeamRequestForm();
      } else {
        return _buildIndividualsForm();
      }
    }
  }

  // STEP 1: Game Type Selector
  Widget _buildGameTypeSelector() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Game'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What are you creating?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            
            // Team vs Team Card
            _buildGameTypeCard(
              icon: '🏆',
              title: 'Team vs Team',
              subtitle: 'Organized match between teams',
              note: 'Admin required',
              onTap: () {
                if (!_isAdmin) {
                  _showNonAdminDialog();
                } else {
                  setState(() {
                    _selectedGameType = 'team';
                    _currentStep = 1;
                  });
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Individuals Card
            _buildGameTypeCard(
              icon: '👤',
              title: 'Individuals',
              subtitle: 'Open match for players',
              onTap: () {
                setState(() {
                  _selectedGameType = 'individual';
                  _currentStep = 1;
                });
              },
            ),
            
            const Spacer(),
            
            // Cancel Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameTypeCard({
    required String icon,
    required String title,
    required String subtitle,
    String? note,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Future<void> _showNonAdminDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin Required'),
        content: const Text(
          'You are not an admin of this team.\nYou can submit a request for approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Request Game'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        _selectedGameType = 'team';
        _currentStep = 1;
      });
    }
  }

  // STEP 2A: Team vs Team (Admin View)
  Widget _buildTeamVsTeamAdminForm() {
    return _TeamVsTeamForm(
      controller: widget.controller,
      isAdmin: true,
      onBack: () => setState(() => _currentStep = 0),
    );
  }

  // STEP 2B: Team vs Team (Non-Admin Request)
  Widget _buildTeamVsTeamRequestForm() {
    return _TeamVsTeamForm(
      controller: widget.controller,
      isAdmin: false,
      onBack: () => setState(() => _currentStep = 0),
    );
  }

  // STEP 2C: Individuals Match
  Widget _buildIndividualsForm() {
    return _IndividualsForm(
      controller: widget.controller,
      onBack: () => setState(() => _currentStep = 0),
    );
  }
}

// Team vs Team Form (used for both admin and non-admin)
class _TeamVsTeamForm extends StatefulWidget {
  final HomeTabsController controller;
  final bool isAdmin;
  final VoidCallback onBack;

  const _TeamVsTeamForm({
    required this.controller,
    required this.isAdmin,
    required this.onBack,
  });

  @override
  State<_TeamVsTeamForm> createState() => _TeamVsTeamFormState();
}

class _TeamVsTeamFormState extends State<_TeamVsTeamForm> {
  /// Get ZIP code from current device location
  Future<String?> _getDeviceLocationZip() async {
    // Use LocationService.getCurrentZipCode() which handles:
    // 1. Current device location
    // 2. Manual location setting
    // 3. Cached ZIP code
    // 4. Last known ZIP code from database (fallback)
    final zip = await LocationService.getCurrentZipCode();
    if (kDebugMode) {
      if (zip != null) {
        print('[DEBUG] Using ZIP code for game creation: $zip');
      } else {
        print('[DEBUG] ⚠️  No ZIP code available for game creation');
      }
    }
    return zip;
  }

  final _allSportsOptions = const [
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

  String? _selectedSport;
  String? _selectedTeamId;
  String _opponentType = 'specific'; // 'specific' or 'open'
  // Allow selecting multiple specific opponent teams
  final Set<String> _selectedOpponentTeamIds = {};
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _venueText;
  String? _gameDetails;
  String _visibility = 'invited'; // 'invited', 'nearby', 'public'
  bool _notifyAdmins = true;
  String? _errorText;
  bool _saving = false;
  int? _expectedPlayersPerTeam;

  String _displaySport(String key) {
    final withSpaces = key.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _submit() async {
    if (_selectedSport == null) {
      setState(() => _errorText = 'Please select a sport.');
      return;
    }
    if (_selectedTeamId == null) {
      setState(() => _errorText = 'Please select your team.');
      return;
    }
    if (_selectedDate == null) {
      setState(() => _errorText = 'Please select match date.');
      return;
    }
    if (_startTime == null || _endTime == null) {
      setState(() => _errorText = 'Please select start and end time.');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final supa = Supabase.instance.client;
    final userId = widget.controller.currentUserId;
    if (userId == null) {
      setState(() {
        _saving = false;
        _errorText = 'User not logged in.';
      });
      return;
    }

    try {
      final d = _selectedDate!;
      final startLocal = DateTime(
        d.year,
        d.month,
        d.day,
        _startTime!.hour,
        _startTime!.minute,
      );
      final endLocal = DateTime(
        d.year,
        d.month,
        d.day,
        _endTime!.hour,
        _endTime!.minute,
      );

      final startUtc = startLocal.toUtc().toIso8601String();
      final endUtc = endLocal.toUtc().toIso8601String();

      // Get device location ZIP code
      String? gameZipCode;
      // Use LocationService.getCurrentZipCode() which handles fallback to last known ZIP
      gameZipCode = await LocationService.getCurrentZipCode();
      if (kDebugMode) {
        if (gameZipCode != null) {
          print('[DEBUG] Using ZIP code for team game creation: $gameZipCode');
        } else {
          print('[DEBUG] ⚠️  No ZIP code available for team game creation');
        }
      }

      final insertMap = <String, dynamic>{
        'creator_id': userId,
        'created_by': userId,
        'mode': 'team_vs_team',
        'match_type': 'team_vs_team',
        'sport': _selectedSport,
        'zip_code': gameZipCode, // Use device location ZIP
        // Default radius for all match types
        'radius_miles': 75, // Required field
        'status': widget.isAdmin ? 'open' : 'pending', // Non-admin creates as pending
        'visibility': _visibility,
        'is_public': _visibility == 'public',
        'start_time_1': startUtc,
        'start_time_2': endUtc,
        'last_updated_at': DateTime.now().toUtc().toIso8601String(),
        'team_id': _selectedTeamId,
        // Note: expected_players_per_team is now stored in sport_expected_players table
        // We don't store it per-match anymore
      };

      if (_venueText != null && _venueText!.trim().isNotEmpty) {
        insertMap['venue'] = _venueText!.trim();
      }
      
      if (_gameDetails != null && _gameDetails!.trim().isNotEmpty) {
        insertMap['details'] = _gameDetails!.trim();
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

      // If admin and specific team(s) selected, create invite(s)
      if (widget.isAdmin &&
          _opponentType == 'specific' &&
          _selectedOpponentTeamIds.isNotEmpty) {
        final inviteRows = _selectedOpponentTeamIds.map((teamId) {
          return {
            'request_id': requestId,
            'target_team_id': teamId,
            'status': 'pending',
            'target_type': 'team',
          };
        }).toList();

        await supa.from('instant_request_invites').insert(inviteRows);
        
        // Create attendance records for all members of the creating team
        try {
          final creatingTeamMembers = await supa
              .from('team_members')
              .select('user_id')
              .eq('team_id', _selectedTeamId!);
          
          if (kDebugMode) {
            print('[DEBUG] Creating attendance for creating team $_selectedTeamId: ${creatingTeamMembers is List ? creatingTeamMembers.length : 0} members');
          }
          
          if (creatingTeamMembers is List && creatingTeamMembers.isNotEmpty) {
            final creatingTeamAttendanceRows = creatingTeamMembers.map((member) {
              return {
                'request_id': requestId,
                'user_id': member['user_id'] as String,
                'team_id': _selectedTeamId,
                'status': 'pending', // All members start as pending
              };
            }).toList();
            
            // Use upsert to handle potential duplicates gracefully
            await supa.from('team_match_attendance').upsert(
              creatingTeamAttendanceRows,
              onConflict: 'request_id,user_id',
            );
            
            if (kDebugMode) {
              print('[DEBUG] ✅ Created ${creatingTeamAttendanceRows.length} attendance records for creating team');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('[ERROR] Failed to create attendance for creating team: $e');
          }
          // Continue even if this fails - game is already created
        }
        
        // Create attendance records for all members of the invited teams
        for (final invitedTeamId in _selectedOpponentTeamIds) {
          try {
            final invitedTeamMembers = await supa
                .from('team_members')
                .select('user_id')
                .eq('team_id', invitedTeamId);
            
            if (kDebugMode) {
              print('[DEBUG] Creating attendance for invited team $invitedTeamId: ${invitedTeamMembers is List ? invitedTeamMembers.length : 0} members');
            }
            
            if (invitedTeamMembers is List && invitedTeamMembers.isNotEmpty) {
              final invitedTeamAttendanceRows = invitedTeamMembers.map((member) {
                return {
                  'request_id': requestId,
                  'user_id': member['user_id'] as String,
                  'team_id': invitedTeamId,
                  'status': 'pending', // All members start as pending
                };
              }).toList();
              
              // Use upsert to handle potential duplicates gracefully
              await supa.from('team_match_attendance').upsert(
                invitedTeamAttendanceRows,
                onConflict: 'request_id,user_id',
              );
              
              if (kDebugMode) {
                print('[DEBUG] ✅ Created ${invitedTeamAttendanceRows.length} attendance records for invited team $invitedTeamId');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('[ERROR] Failed to create attendance for invited team $invitedTeamId: $e');
            }
            // Continue for other teams even if one fails
          }
        }
      } else if (widget.isAdmin && _opponentType == 'open') {
        // Open challenge: no per-team invites created.
        // Other teams discover this match via visibility + radius filters.
        // Still create attendance records for all members of the creating team
        try {
          final creatingTeamMembers = await supa
              .from('team_members')
              .select('user_id')
              .eq('team_id', _selectedTeamId!);
          
          if (creatingTeamMembers is List && creatingTeamMembers.isNotEmpty) {
            final creatingTeamAttendanceRows = creatingTeamMembers.map((member) {
              return {
                'request_id': requestId,
                'user_id': member['user_id'] as String,
                'team_id': _selectedTeamId,
                'status': 'pending', // All members start as pending
              };
            }).toList();
            
            // Use upsert to handle potential duplicates gracefully
            await supa.from('team_match_attendance').upsert(
              creatingTeamAttendanceRows,
              onConflict: 'request_id,user_id',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('[ERROR] Failed to create attendance for creating team (open challenge): $e');
          }
          // Continue even if this fails - game is already created
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAdmin
                ? 'Team match created successfully!'
                : 'Match request submitted for admin approval.',
          ),
        ),
      );

      await widget.controller.loadAdminTeamsAndInvites();
      await widget.controller.loadAwaitingOpponentConfirmationGames();
      await widget.controller.loadAllMyMatches(); // Refresh My Games
      await widget.controller.loadDiscoveryPickupMatches(); // Refresh Discover
    } catch (e) {
      setState(() {
        _saving = false;
        _errorText = 'Failed to create match: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredTeams = _selectedSport == null
        ? widget.controller.adminTeams
        : widget.controller.adminTeams
            .where((t) =>
                (t['sport'] as String? ?? '').toLowerCase() ==
                _selectedSport!.toLowerCase())
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Create Team Match' : 'Request Team Match'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sport
            const Row(
              children: [
                Text('🏏', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Sport *', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedSport,
              decoration: const InputDecoration(
                hintText: 'Select sport',
                border: OutlineInputBorder(),
              ),
              items: _allSportsOptions
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(_displaySport(s)),
                      ))
                  .toList(),
              onChanged: (v) async {
                setState(() {
                  _selectedSport = v;
                  _selectedTeamId = null;
                });
                // Set default expected players based on sport
                if (v != null) {
                  final expected = await SportDefaults.getExpectedPlayersPerTeam(v);
                  setState(() {
                    _expectedPlayersPerTeam = expected;
                  });
                }
              },
            ),
            const SizedBox(height: 24),

            // Your Team
            const Row(
              children: [
                Text('👥', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Your Team *', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedTeamId,
              decoration: const InputDecoration(
                hintText: 'Select your team',
                border: OutlineInputBorder(),
              ),
              items: filteredTeams
                  .map((t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['name'] as String? ?? ''),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedTeamId = v),
            ),
            const SizedBox(height: 24),

            // Opponent
            const Row(
              children: [
                Text('🆚', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Opponent', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.isAdmin) ...[
              RadioListTile<String>(
                title: const Text('Invite specific team'),
                value: 'specific',
                groupValue: _opponentType,
                onChanged: (v) => setState(() {
                  _opponentType = v ?? 'specific';
                  // Default visibility when inviting specific teams
                  _visibility = 'invited';
                  _selectedOpponentTeamIds.clear();
                }),
              ),
              RadioListTile<String>(
                title: const Text('Open challenge'),
                value: 'open',
                groupValue: _opponentType,
                onChanged: (v) => setState(() {
                  _opponentType = v ?? 'open';
                  // Default visibility when open challenge
                  _visibility = 'public';
                  _selectedOpponentTeamIds.clear();
                }),
              ),
              if (_opponentType == 'specific' && _selectedSport != null) ...[
                const SizedBox(height: 8),
                FutureBuilder(
                  future: _loadOpponentTeams(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }
                    final teams = snapshot.data as List<Map<String, dynamic>>;
                    if (teams.isEmpty) {
                      return const Text(
                        'No opponent teams available for this sport yet.',
                        style: TextStyle(color: Colors.grey),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select opponent team(s)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...teams.map((t) {
                          final id = t['id'] as String;
                          final name = t['name'] as String? ?? '';
                          final selected = _selectedOpponentTeamIds.contains(id);
                          return CheckboxListTile(
                            value: selected,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(name),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedOpponentTeamIds.add(id);
                                } else {
                                  _selectedOpponentTeamIds.remove(id);
                                }
                              });
                            },
                          );
                        }),
                      ],
                    );
                  },
                ),
              ],
            ] else
              const Text(
                'Opponent will be selected after admin approval',
                style: TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 24),

            // Match Date
            const Row(
              children: [
                Text('📅', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Match Date *', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate ?? now,
                  firstDate: now.subtract(const Duration(days: 1)),
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                }
              },
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _selectedDate == null
                    ? 'Select date'
                    : '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(height: 24),

            // Time
            const Row(
              children: [
                Text('⏱', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Time *', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _startTime ?? TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() => _startTime = picked);
                      }
                    },
                    icon: const Icon(Icons.access_time),
                    label: Text(_startTime == null
                        ? 'Start'
                        : _startTime!.format(context)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _endTime ?? TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() => _endTime = picked);
                      }
                    },
                    icon: const Icon(Icons.access_time),
                    label: Text(
                        _endTime == null ? 'End' : _endTime!.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Venue
            const Row(
              children: [
                Text('📍', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Venue (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter or suggest venue',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _venueText = v),
            ),
            const SizedBox(height: 24),

            // Game Details
            const Row(
              children: [
                Text('📝', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Game Details (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Add any additional details about the game',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (v) => setState(() => _gameDetails = v),
            ),
            const SizedBox(height: 24),

            // Expected Players Per Team (Admin only, shown after sport is selected)
            // Note: This is now managed globally in the sport_expected_players table
            // Display info only, editing is done in a separate admin screen
            if (widget.isAdmin && _selectedSport != null) ...[
              FutureBuilder<int>(
                future: SportDefaults.getExpectedPlayersPerTeam(_selectedSport!),
                builder: (context, snapshot) {
                  final expected = snapshot.data ?? 11;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('👥', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          const Text('Expected players per team', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '$expected players',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(Default for ${_displaySport(_selectedSport!)})',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Note: Expected players are managed globally per sport. Contact admin to update.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ],

            const Divider(),
            const SizedBox(height: 16),

            // Visibility (Admin only) - Auto-set based on opponent type, non-editable
            if (widget.isAdmin) ...[
              const Text('Visibility', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      _opponentType == 'specific' ? Icons.lock : Icons.public,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _opponentType == 'specific' 
                            ? 'Only invited teams (auto-set)'
                            : 'Public (auto-set)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _opponentType == 'specific'
                    ? 'Visibility is automatically set to "Only invited teams" when inviting specific teams.'
                    : 'Visibility is automatically set to "Public" for open challenges.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Notify team admins'),
                value: _notifyAdmins,
                onChanged: (v) => setState(() => _notifyAdmins = v ?? true),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Requires admin approval',
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],

            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : widget.onBack,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(widget.isAdmin ? Icons.check : Icons.send),
                    label: Text(_saving
                        ? 'Creating...'
                        : widget.isAdmin
                            ? 'Create Game ✓'
                            : 'Submit Request 📨'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadOpponentTeams() async {
    if (_selectedSport == null || _selectedTeamId == null) return [];
    final supa = Supabase.instance.client;
    final teams = await supa
        .from('teams')
        .select('id, name')
        .eq('sport', _selectedSport!)
        .neq('id', _selectedTeamId!);
    if (teams is List) {
      return teams.map((t) => Map<String, dynamic>.from(t)).toList();
    }
    return [];
  }
}

// Individuals Match Form
class _IndividualsForm extends StatefulWidget {
  final HomeTabsController controller;
  final VoidCallback onBack;

  const _IndividualsForm({
    required this.controller,
    required this.onBack,
  });

  @override
  State<_IndividualsForm> createState() => _IndividualsFormState();
}

class _IndividualsFormState extends State<_IndividualsForm> {
  /// Get ZIP code from current device location
  Future<String?> _getDeviceLocationZip() async {
    // Use LocationService.getCurrentZipCode() which handles:
    // 1. Current device location
    // 2. Manual location setting
    // 3. Cached ZIP code
    // 4. Last known ZIP code from database (fallback)
    final zip = await LocationService.getCurrentZipCode();
    if (kDebugMode) {
      if (zip != null) {
        print('[DEBUG] Using ZIP code for game creation: $zip');
      } else {
        print('[DEBUG] ⚠️  No ZIP code available for game creation');
      }
    }
    return zip;
  }
  final _allSportsOptions = const [
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

  String? _selectedSport;
  int _numPlayers = 4;
  String _skillLevel = 'Intermediate'; // 'Beginner', 'Intermediate', 'Advanced'
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _venueText;
  String? _gameDetails;
  String _visibility = 'public'; // 'friends_group', 'public'
  String? _selectedFriendsGroupId;
  List<Map<String, dynamic>> _friendsGroups = [];
  bool _loadingGroups = false;
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFriendsGroups();
  }

  String _displaySport(String key) {
    final withSpaces = key.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _loadFriendsGroups() async {
    final supa = Supabase.instance.client;
    final userId = widget.controller.currentUserId;
    if (userId == null) return;

    setState(() => _loadingGroups = true);

    try {
      // First, get groups created by user or groups user is member of
      final createdGroupsRows = await supa
          .from('friends_groups')
          .select('id, name, created_by, sport')
          .eq('created_by', userId)
          .order('sport, name');
      
      // Then, get group IDs where user is a member
      final memberGroupsRows = await supa
          .from('friends_group_members')
          .select('group_id')
          .eq('user_id', userId);
      
      // Collect all group IDs (created + member)
      Set<String> allGroupIds = {};
      if (createdGroupsRows is List) {
        for (final g in createdGroupsRows) {
          final groupId = g['id'] as String?;
          if (groupId != null) allGroupIds.add(groupId);
        }
      }
      if (memberGroupsRows is List) {
        for (final m in memberGroupsRows) {
          final groupId = m['group_id'] as String?;
          if (groupId != null) allGroupIds.add(groupId);
        }
      }
      
      // Fetch all groups
      List<Map<String, dynamic>> allGroups = [];
      if (allGroupIds.isNotEmpty) {
        final allGroupsRows = await supa
            .from('friends_groups')
            .select('id, name, created_by, sport')
            .inFilter('id', allGroupIds.toList())
            .order('sport, name');
        
        if (allGroupsRows is List) {
          allGroups = allGroupsRows.map((g) => Map<String, dynamic>.from(g)).toList();
        }
      }

      // Filter by selected sport if available
      // If sport is selected, only show groups for that sport
      // If no sport selected, show all groups
      List<Map<String, dynamic>> filteredGroups = allGroups;
      if (_selectedSport != null && _selectedSport!.isNotEmpty) {
        filteredGroups = allGroups.where((g) {
          final groupSport = g['sport'] as String?;
          return groupSport == _selectedSport;
        }).toList();
      }

      if (mounted) {
        setState(() {
          _friendsGroups = filteredGroups;
          if (_selectedFriendsGroupId != null) {
            // Clear selected group if it's no longer in the filtered list
            final stillExists = filteredGroups.any((g) => g['id'] == _selectedFriendsGroupId);
            if (!stillExists) {
              _selectedFriendsGroupId = null;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load friends groups: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingGroups = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedSport == null) {
      setState(() => _errorText = 'Please select a sport.');
      return;
    }
    if (_selectedDate == null) {
      setState(() => _errorText = 'Please select date.');
      return;
    }
    if (_selectedTime == null) {
      setState(() => _errorText = 'Please select time.');
      return;
    }
    
    // Validate friends group selection
    if (_visibility == 'friends_group' && _selectedFriendsGroupId == null) {
      setState(() => _errorText = 'Please select a friends group.');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final supa = Supabase.instance.client;
    final userId = widget.controller.currentUserId;
    if (userId == null) {
      setState(() {
        _saving = false;
        _errorText = 'User not logged in.';
      });
      return;
    }

    try {
      final d = _selectedDate!;
      final startLocal = DateTime(
        d.year,
        d.month,
        d.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      final endLocal = startLocal.add(const Duration(hours: 2)); // Default 2 hour match

      final startUtc = startLocal.toUtc().toIso8601String();
      final endUtc = endLocal.toUtc().toIso8601String();

      // Set radius: 100 miles for public, 75 for others
      final radiusMiles = _visibility == 'public' ? 100 : 75;

      final insertMap = <String, dynamic>{
        'creator_id': userId,
        'created_by': userId,
        'mode': 'pickup',
        'match_type': 'pickup',
        'sport': _selectedSport,
        'zip_code': await _getDeviceLocationZip(), // Use device location ZIP
        'radius_miles': radiusMiles,
        'num_players': _numPlayers,
        'proficiency_level': _skillLevel,
        'status': 'open',
        'visibility': _visibility,
        'is_public': _visibility == 'public',
        'start_time_1': startUtc,
        'start_time_2': endUtc,
        'last_updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (_venueText != null && _venueText!.trim().isNotEmpty) {
        insertMap['venue'] = _venueText!.trim();
      }
      
      if (_gameDetails != null && _gameDetails!.trim().isNotEmpty) {
        insertMap['details'] = _gameDetails!.trim();
      }
      
      if (_visibility == 'friends_group' && _selectedFriendsGroupId != null) {
        insertMap['friends_group_id'] = _selectedFriendsGroupId;
      }

      final result = await supa.from('instant_match_requests').insert(insertMap).select('id').maybeSingle();
      final requestId = result?['id'] as String?;
      
      if (requestId == null) {
        throw Exception('Failed to create game');
      }

      // For public games, create an accepted attendance record for the creator
      // so the game appears in "My Games"
      if (_visibility == 'public') {
        try {
          if (kDebugMode) {
            print('[DEBUG] Creating attendance record for public game creator');
            print('[DEBUG] request_id: $requestId, user_id: $userId');
          }
          final insertResult = await supa.from('individual_game_attendance').insert({
            'request_id': requestId,
            'user_id': userId,
            'status': 'accepted', // Creator is automatically accepted
          }).select();
          if (kDebugMode) {
            print('[DEBUG] ✅ Successfully created attendance record: $insertResult');
          }
        } catch (e) {
          if (kDebugMode) {
            print('[DEBUG] ❌ Failed to create creator attendance record: $e');
            print('[DEBUG] Stack trace: ${StackTrace.current}');
          }
          // Don't fail game creation if attendance record fails
        }
      } else if (kDebugMode) {
        print('[DEBUG] Not creating attendance record (visibility: $_visibility)');
      }

      // If friends_group visibility, create pending attendance for all group members (including organizer)
      if (_visibility == 'friends_group' && _selectedFriendsGroupId != null) {
        final groupId = _selectedFriendsGroupId!;
        try {
          if (kDebugMode) {
            print('[DEBUG] ========== CREATING ATTENDANCE RECORDS ==========');
            print('[DEBUG] Game ID: $requestId');
            print('[DEBUG] Group ID: $groupId');
            print('[DEBUG] Organizer ID: $userId');
          }
          
          // First, verify we can see the group
          final groupCheck = await supa
              .from('friends_groups')
              .select('id, name, created_by')
              .eq('id', groupId)
              .maybeSingle();
          
          if (kDebugMode) {
            print('[DEBUG] Group check result: $groupCheck');
          }
          
          final groupMembers = await supa
              .from('friends_group_members')
              .select('user_id')
              .eq('group_id', groupId);
          
          if (kDebugMode) {
            print('[DEBUG] Found ${groupMembers is List ? groupMembers.length : 0} group members');
            if (groupMembers is List) {
              print('[DEBUG] Group member IDs: ${groupMembers.map((m) => m['user_id']).toList()}');
            }
          }
          
          if (groupMembers is List && groupMembers.isNotEmpty) {
            final List<Map<String, dynamic>> attendanceRecords = [];
            for (final member in groupMembers as List) {
              final memberId = member['user_id'] as String?;
              if (kDebugMode) {
                print('[DEBUG] Processing member: $memberId (organizer: $userId)');
              }
              if (memberId != null) { // Include organizer too (they'll have pending status)
                attendanceRecords.add({
                  'request_id': requestId,
                  'user_id': memberId,
                  'status': 'pending',
                  'invited_by': userId,
                });
                if (kDebugMode) {
                  print('[DEBUG] Added attendance record for member: $memberId');
                }
              } else if (kDebugMode) {
                print('[DEBUG] Skipping null member: $memberId');
              }
            }
            
            if (kDebugMode) {
              print('[DEBUG] Total attendance records to create: ${attendanceRecords.length}');
              print('[DEBUG] Records: $attendanceRecords');
            }
            
            if (attendanceRecords.isNotEmpty) {
              try {
                final insertResult = await supa.from('individual_game_attendance').insert(attendanceRecords);
                if (kDebugMode) {
                  print('[DEBUG] ✅ Successfully created ${attendanceRecords.length} pending attendance records');
                  print('[DEBUG] Insert result: $insertResult');
                  
                  // Verify the records were created
                  final verifyRecords = await supa
                      .from('individual_game_attendance')
                      .select('id, user_id, status')
                      .eq('request_id', requestId)
                      .eq('status', 'pending');
                  
                  if (kDebugMode) {
                    print('[DEBUG] Verification: Found ${verifyRecords is List ? verifyRecords.length : 0} pending records');
                    if (verifyRecords is List) {
                      for (final record in verifyRecords) {
                        print('[DEBUG] Verified record: user=${record['user_id']}, status=${record['status']}');
                      }
                    }
                  }
                }
              } catch (insertError) {
                if (kDebugMode) {
                  print('[DEBUG] ❌ Failed to insert attendance records: $insertError');
                  print('[DEBUG] Attempted to insert: $attendanceRecords');
                }
                rethrow; // Re-throw to be caught by outer catch
              }
            } else if (kDebugMode) {
              print('[DEBUG] No attendance records to create (only organizer in group)');
            }
          } else if (kDebugMode) {
            print('[DEBUG] ❌ No group members found for group $groupId');
          }
          
          if (kDebugMode) {
            print('[DEBUG] ========== END ATTENDANCE RECORDS CREATION ==========');
          }
        } catch (e) {
          if (kDebugMode) {
            print('[DEBUG] ❌ Error creating attendance records for friends group: $e');
            print('[DEBUG] Stack trace: ${StackTrace.current}');
          }
          // Don't fail the entire game creation if attendance record creation fails
          // The game is already created, attendance can be added later
        }
      }

      // Refresh discovery and my games after creating
      await widget.controller.loadDiscoveryPickupMatches();
      await widget.controller.loadAllMyIndividualMatches();
      await widget.controller.loadAllMyMatches();

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open match created successfully!')),
      );

      await widget.controller.loadDiscoveryPickupMatches();
    } catch (e) {
      setState(() {
        _saving = false;
        _errorText = 'Failed to create match: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Open Match'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sport
            const Row(
              children: [
                Text('🏸', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Sport *', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedSport,
              decoration: const InputDecoration(
                hintText: 'Select sport',
                border: OutlineInputBorder(),
              ),
              items: _allSportsOptions
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(_displaySport(s)),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedSport = v;
                  _selectedFriendsGroupId = null; // Reset selected group when sport changes
                });
                _loadFriendsGroups(); // Reload groups filtered by new sport
              },
            ),
            const SizedBox(height: 24),

            // Players Needed
            const Row(
              children: [
                Text('👤', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Players Needed', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (_numPlayers > 1) {
                      setState(() => _numPlayers--);
                    }
                  },
                  icon: const Icon(Icons.remove),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '$_numPlayers',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() => _numPlayers++);
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Skill Level
            const Row(
              children: [
                Text('🎯', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Skill Level', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _skillLevel,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Beginner', child: Text('Beginner')),
                DropdownMenuItem(value: 'Intermediate', child: Text('Intermediate')),
                DropdownMenuItem(value: 'Advanced', child: Text('Advanced')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _skillLevel = v);
                }
              },
            ),
            const SizedBox(height: 24),

            // Date & Time
            const Row(
              children: [
                Text('📅', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate ?? now,
                        firstDate: now.subtract(const Duration(days: 1)),
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _selectedDate == null
                          ? 'Date'
                          : '${_selectedDate!.month}/${_selectedDate!.day}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime ?? TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedTime = picked);
                      }
                    },
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      _selectedTime == null
                          ? 'Time'
                          : _selectedTime!.format(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Visibility
            const Row(
              children: [
                Text('👀', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Visibility', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              title: const Text('Friends Group'),
              subtitle: const Text('Send to a specific friends group'),
              value: 'friends_group',
              groupValue: _visibility,
              onChanged: (v) {
                setState(() {
                  _visibility = v ?? 'friends_group';
                  _selectedFriendsGroupId = null; // Reset selection
                });
                _loadFriendsGroups(); // Reload groups when selecting this option
              },
            ),
            // Friends Group Dropdown
            if (_visibility == 'friends_group') ...[
              const SizedBox(height: 8),
              if (_loadingGroups)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_friendsGroups.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedSport != null
                            ? 'You currently do not have friends group for ${_displaySport(_selectedSport!)}.'
                            : 'You currently do not have friends group.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const UserProfileScreen(),
                            ),
                          ).then((_) {
                            _loadFriendsGroups(); // Reload groups when returning
                          });
                        },
                        child: Text(
                          'Create Friends Group',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedFriendsGroupId,
                  decoration: const InputDecoration(
                    labelText: 'Select Friends Group',
                    border: OutlineInputBorder(),
                  ),
                  items: _friendsGroups.map((group) {
                    final groupName = group['name'] as String? ?? 'Unnamed Group';
                    final groupSport = group['sport'] as String?;
                    return DropdownMenuItem<String>(
                      value: group['id'] as String,
                      child: Text(
                        groupSport != null
                            ? '$groupName (${_displaySport(groupSport)})'
                            : groupName,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedFriendsGroupId = value);
                  },
                ),
            ],
            RadioListTile<String>(
              title: const Text('Public'),
              subtitle: const Text('Visible to all players within 100 miles'),
              value: 'public',
              groupValue: _visibility,
              onChanged: (v) {
                setState(() {
                  _visibility = v ?? 'public';
                  _selectedFriendsGroupId = null;
                });
              },
            ),
            const SizedBox(height: 24),

            // Venue
            const Row(
              children: [
                Text('📍', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Venue (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Enter venue',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _venueText = v),
            ),
            const SizedBox(height: 24),

            // Game Details
            const Row(
              children: [
                Text('📝', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('Game Details (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Add any additional details about the game',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (v) => setState(() => _gameDetails = v),
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : widget.onBack,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? 'Creating...' : 'Create Game ✓'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

