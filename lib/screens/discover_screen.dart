import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_tabs/home_tabs_controller.dart';
import '../../services/location_service.dart';

class DiscoverScreen extends StatefulWidget {
  final HomeTabsController controller;
  final VoidCallback? onCreateGame;
  
  const DiscoverScreen({super.key, required this.controller, this.onCreateGame});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();
  
  // Filter state
  String? _selectedSport; // null = all sports
  String? _selectedGameType; // 'team', 'individual', null = all
  DateTime? _selectedDate; // null = any date
  int _maxDistance = 100; // miles, default 100
  String? _selectedReadiness; // proficiency level, null = all
  int? _minSpotsLeft; // null = any
  int? _maxSpotsLeft; // null = any
  
  bool _showFilterPanel = false;
  String? _userLocationDisplay; // "City, State" format

  String _displaySport(String key) {
    final withSpaces = key.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
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

  String _formatTime(DateTime? start) {
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

  // Calculate distance from match data
  String _calculateDistance(Map<String, dynamic> match) {
    final distance = match['distance_miles'] as double?;
    if (distance == null) {
      return 'Distance unknown';
    }
    if (distance < 1) {
      return '${(distance * 5280).round()} ft'; // Show in feet if less than 1 mile
    } else if (distance < 10) {
      return '${distance.toStringAsFixed(1)} mi'; // Show 1 decimal for < 10 miles
    } else {
      return '${distance.round()} mi'; // Round to nearest mile for >= 10 miles
    }
  }
  
  Future<void> _showInviteFriendsDialog(String requestId, String sport) async {
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    if (userId == null) return;

    final selectedFriendIds = <String>{};

    // Load user's friends
    final friendRows = await supa
        .from('friends')
        .select('friend_id')
        .eq('user_id', userId)
        .eq('status', 'accepted');

    final friendIds = <String>[];
    if (friendRows is List) {
      for (final r in friendRows) {
        final fid = r['friend_id'] as String?;
        if (fid != null) friendIds.add(fid);
      }
    }

    if (friendIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You don\'t have any friends to invite')),
      );
      return;
    }

    // Get friend details
    final friends = await supa
        .from('users')
        .select('id, full_name, photo_url')
        .inFilter('id', friendIds);

    // Get already invited users
    final existingAttendance = await supa
        .from('individual_game_attendance')
        .select('user_id')
        .eq('request_id', requestId);

    final alreadyInvitedIds = <String>{};
    if (existingAttendance is List) {
      for (final row in existingAttendance) {
        final uid = row['user_id'] as String?;
        if (uid != null) alreadyInvitedIds.add(uid);
      }
    }

    // Filter out already invited friends
    final availableFriends = (friends is List ? friends : []).where((f) {
      final fid = f['id'] as String?;
      return fid != null && !alreadyInvitedIds.contains(fid) && fid != userId;
    }).toList();

    if (availableFriends.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All your friends are already invited or part of this game')),
      );
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Invite Friends to ${_displaySport(sport)} Game'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select friends to invite:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: availableFriends.length,
                        itemBuilder: (context, index) {
                          final friend = availableFriends[index];
                          final friendId = friend['id'] as String;
                          final friendName = friend['full_name'] as String? ?? 'Unknown';
                          final photoUrl = friend['photo_url'] as String?;
                          final isSelected = selectedFriendIds.contains(friendId);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? Text(friendName.isNotEmpty ? friendName[0].toUpperCase() : '?')
                                  : null,
                            ),
                            title: Text(friendName),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedFriendIds.add(friendId);
                                  } else {
                                    selectedFriendIds.remove(friendId);
                                  }
                                });
                              },
                            ),
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  selectedFriendIds.remove(friendId);
                                } else {
                                  selectedFriendIds.add(friendId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedFriendIds.isEmpty
                      ? null
                      : () async {
                          await _inviteFriendsToGame(requestId, selectedFriendIds.toList());
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: Text('Invite (${selectedFriendIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  Future<void> _inviteFriendsToGame(String requestId, List<String> friendIds) async {
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Create pending attendance records for invited friends
      final inviteRecords = friendIds.map((friendId) => {
        'request_id': requestId,
        'user_id': friendId,
        'status': 'pending',
        'invited_by': userId,
      }).toList();

      await supa.from('individual_game_attendance').insert(inviteRecords);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invited ${friendIds.length} friend(s)! They will see this in their pending games.'),
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Refresh discovery matches to update spots left
      widget.controller.loadDiscoveryPickupMatches();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to invite friends: $e')),
      );
    }
  }
  
  Future<void> _requestToJoinIndividualGame(String requestId) async {
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to join games')),
      );
      return;
    }

    try {
      // Check if already requested
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

      // Create pending attendance record
      await supa.from('individual_game_attendance').insert({
        'request_id': requestId,
        'user_id': userId,
        'status': 'pending',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Join request sent! Organizer will review your request.'),
          duration: Duration(seconds: 3),
        ),
      );
      
      // Refresh discovery matches
      widget.controller.loadDiscoveryPickupMatches();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join game: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUserLocation();
  }


  Future<void> _loadUserLocation() async {
    // Get user's ZIP code and convert to city, state
    try {
      final zipCode = await LocationService.getCurrentZipCode();
      if (zipCode != null) {
        final cityState = await LocationService.getCityStateFromZip(zipCode);
        if (mounted) {
          setState(() {
            _userLocationDisplay = cityState;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DiscoverScreen] Error loading user location: $e');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return Column(
            children: [
              // Search Bar
              _buildSearchBar(),
              
              // Location Header
              _buildLocationHeader(),
              
              // Filter Header
              _buildFilterHeader(),
              
              // Filter Panel (expandable)
              if (_showFilterPanel) _buildFilterPanel(),
              
              // Content
              Expanded(
                child: widget.controller.loadingDiscoveryMatches
                    ? const Center(child: CircularProgressIndicator())
                    : _getFilteredMatches().isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: () => widget.controller.loadDiscoveryPickupMatches(),
                            child: ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: [
                                const SizedBox(height: 8),
                                
                                // Featured (Paid) Section
                                _buildFeaturedSection(),
                                const SizedBox(height: 16),
                                
                                // Results Feed
                                _buildResultsFeed(),
                                const SizedBox(height: 80), // Space for sticky CTA
                              ],
                            ),
                          ),
              ),
            ],
          );
        },
      ),
      // Sticky CTA
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onCreateGame,
        icon: const Icon(Icons.add),
        label: const Text('Create Game'),
        backgroundColor: Colors.purple,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search games, teams, venues',
          prefixIcon: const Icon(Icons.search, color: Colors.purple),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.purple, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
    );
  }

  Widget _buildLocationHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            _userLocationDisplay != null
                ? 'Games near $_userLocationDisplay'
                : 'Games near you',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey.shade100,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterPillButton(
              icon: Icons.tune,
              label: 'Filter & Sort By',
              onTap: () {
                setState(() => _showFilterPanel = !_showFilterPanel);
              },
              showChevron: true,
            ),
            const SizedBox(width: 8),
            _buildFilterPillButton(
              icon: Icons.sports_soccer,
              label: _selectedSport != null ? _displaySport(_selectedSport!) : 'Sports',
              onTap: () => _showSportPicker(),
              showChevron: true,
              isActive: _selectedSport != null,
            ),
            const SizedBox(width: 8),
            _buildFilterPillButton(
              icon: Icons.calendar_today,
              label: _selectedDate != null ? _formatDate(_selectedDate!) : 'Date',
              onTap: () => _showDatePicker(),
              showChevron: true,
              isActive: _selectedDate != null,
            ),
            const SizedBox(width: 8),
            _buildFilterPillButton(
              icon: Icons.location_on,
              label: _maxDistance < 100 ? '$_maxDistance mi' : 'Nearby',
              onTap: () => _showDistancePicker(),
              showChevron: true,
              isActive: _maxDistance < 100,
            ),
            const SizedBox(width: 8),
            _buildFilterPillButton(
              icon: Icons.emoji_events,
              label: _selectedReadiness != null 
                  ? _selectedReadiness!.substring(0, 1).toUpperCase() + _selectedReadiness!.substring(1)
                  : 'Readiness',
              onTap: () => _showReadinessPicker(),
              showChevron: true,
              isActive: _selectedReadiness != null,
            ),
            const SizedBox(width: 8),
            _buildFilterPillButton(
              icon: Icons.people,
              label: _minSpotsLeft != null || _maxSpotsLeft != null
                  ? 'Spots ${_minSpotsLeft ?? 0}-${_maxSpotsLeft ?? '∞'}'
                  : 'Spots Left',
              onTap: () => _showSpotsLeftPicker(),
              showChevron: true,
              isActive: _minSpotsLeft != null || _maxSpotsLeft != null,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFilterPillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool showChevron = false,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.orange : Colors.grey.shade300,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.orange : Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? Colors.orange : Colors.grey.shade700,
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: isActive ? Colors.orange : Colors.grey.shade600,
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  void _showSportPicker() {
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
    
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Sport',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('All Sports'),
                leading: Radio<String?>(
                  value: null,
                  groupValue: _selectedSport,
                  onChanged: (value) {
                    setState(() => _selectedSport = value);
                    Navigator.pop(context);
                  },
                ),
                onTap: () {
                  setState(() => _selectedSport = null);
                  Navigator.pop(context);
                },
              ),
              ...allSports.map((sport) => ListTile(
                title: Text(_displaySport(sport)),
                leading: Radio<String?>(
                  value: sport,
                  groupValue: _selectedSport,
                  onChanged: (value) {
                    setState(() => _selectedSport = value);
                    Navigator.pop(context);
                  },
                ),
                onTap: () {
                  setState(() => _selectedSport = sport);
                  Navigator.pop(context);
                },
              )),
            ],
          ),
        );
      },
    );
  }
  
  void _showDatePicker() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }
  
  void _showDistancePicker() {
    int tempDistance = _maxDistance; // Store current value
    
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
                            _maxDistance = tempDistance; // Update main widget state
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
  
  void _showReadinessPicker() {
    final levels = ['Beginner', 'Intermediate', 'Advanced', 'Professional'];
    
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Skill Level',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Any Level'),
                leading: Radio<String?>(
                  value: null,
                  groupValue: _selectedReadiness,
                  onChanged: (value) {
                    setState(() => _selectedReadiness = value);
                    Navigator.pop(context);
                  },
                ),
                onTap: () {
                  setState(() => _selectedReadiness = null);
                  Navigator.pop(context);
                },
              ),
              ...levels.map((level) => ListTile(
                title: Text(level),
                leading: Radio<String?>(
                  value: level.toLowerCase(),
                  groupValue: _selectedReadiness,
                  onChanged: (value) {
                    setState(() => _selectedReadiness = value);
                    Navigator.pop(context);
                  },
                ),
                onTap: () {
                  setState(() => _selectedReadiness = level.toLowerCase());
                  Navigator.pop(context);
                },
              )),
            ],
          ),
        );
      },
    );
  }
  
  void _showSpotsLeftPicker() {
    final minController = TextEditingController(text: _minSpotsLeft?.toString() ?? '');
    final maxController = TextEditingController(text: _maxSpotsLeft?.toString() ?? '');
    
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Spots Left',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minController,
                      decoration: const InputDecoration(
                        labelText: 'Min',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('to'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: maxController,
                      decoration: const InputDecoration(
                        labelText: 'Max',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _minSpotsLeft = null;
                        _maxSpotsLeft = null;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Clear'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _minSpotsLeft = minController.text.isEmpty 
                            ? null 
                            : int.tryParse(minController.text);
                        _maxSpotsLeft = maxController.text.isEmpty 
                            ? null 
                            : int.tryParse(maxController.text);
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildActiveFilterChip(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onDeleted: onRemove,
        deleteIcon: const Icon(Icons.close, size: 16),
        backgroundColor: Colors.orange.shade100,
        labelStyle: const TextStyle(color: Colors.orange),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    return '${date.month}/${date.day}/${date.year}';
  }
  
  Widget _buildFilterPanel() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filters',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // Sport Filter
          _buildSportFilter(),
          const SizedBox(height: 16),
          
          // Game Type Filter
          _buildGameTypeFilter(),
          const SizedBox(height: 16),
          
          // Date Filter
          _buildDateFilter(),
          const SizedBox(height: 16),
          
          // Distance Filter
          _buildDistanceFilter(),
          const SizedBox(height: 16),
          
          // Readiness Filter
          _buildReadinessFilter(),
          const SizedBox(height: 16),
          
          // Spots Left Filter
          _buildSpotsLeftFilter(),
          const SizedBox(height: 16),
          
          // Apply/Clear Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _selectedSport = null;
                      _selectedGameType = null;
                      _selectedDate = null;
                      _maxDistance = 100;
                      _selectedReadiness = null;
                      _minSpotsLeft = null;
                      _maxSpotsLeft = null;
                    });
                  },
                  child: const Text('Clear All'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _showFilterPanel = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSportFilter() {
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sport', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedSport,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          hint: const Text('All Sports'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All Sports')),
            ...allSports.map((sport) => DropdownMenuItem<String>(
              value: sport,
              child: Text(_displaySport(sport)),
            )),
          ],
          onChanged: (value) {
            setState(() => _selectedSport = value);
          },
        ),
      ],
    );
  }
  
  Widget _buildGameTypeFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Game Type', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String?>(
                title: const Text('All'),
                value: null,
                groupValue: _selectedGameType,
                onChanged: (value) => setState(() => _selectedGameType = value),
              ),
            ),
            Expanded(
              child: RadioListTile<String?>(
                title: const Text('Team'),
                value: 'team',
                groupValue: _selectedGameType,
                onChanged: (value) => setState(() => _selectedGameType = value),
              ),
            ),
            Expanded(
              child: RadioListTile<String?>(
                title: const Text('Individual'),
                value: 'individual',
                groupValue: _selectedGameType,
                onChanged: (value) => setState(() => _selectedGameType = value),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildDateFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Date', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(_selectedDate == null ? 'Any Date' : _formatDate(_selectedDate!)),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                  }
                },
              ),
            ),
            if (_selectedDate != null)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => _selectedDate = null),
              ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildDistanceFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Distance (miles)', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(
              _maxDistance == 100 ? 'Any' : 'Within $_maxDistance mi',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: _maxDistance.toDouble(),
          min: 5,
          max: 100,
          divisions: 19,
          label: _maxDistance == 100 ? 'Any' : '$_maxDistance miles',
          onChanged: (value) {
            setState(() => _maxDistance = value.round());
          },
        ),
      ],
    );
  }
  
  Widget _buildReadinessFilter() {
    final levels = ['Beginner', 'Intermediate', 'Advanced', 'Professional'];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Skill Level', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedReadiness,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          hint: const Text('Any Level'),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Any Level')),
            ...levels.map((level) => DropdownMenuItem<String>(
              value: level.toLowerCase(),
              child: Text(level),
            )),
          ],
          onChanged: (value) {
            setState(() => _selectedReadiness = value);
          },
        ),
      ],
    );
  }
  
  Widget _buildSpotsLeftFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Spots Left', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Min',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() => _minSpotsLeft = value.isEmpty ? null : int.tryParse(value));
                },
              ),
            ),
            const SizedBox(width: 16),
            const Text('to', style: TextStyle(color: Colors.grey)),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Max',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() => _maxSpotsLeft = value.isEmpty ? null : int.tryParse(value));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap, {bool highlightSelected = false}) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: highlightSelected ? Colors.orange.shade100 : Colors.grey.shade200,
      checkmarkColor: highlightSelected ? Colors.orange : Colors.grey,
      labelStyle: TextStyle(
        color: isSelected && highlightSelected ? Colors.orange.shade900 : Colors.black87,
        fontWeight: isSelected && highlightSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildFeaturedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Featured (Paid)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.amber.shade50,
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: const Text('Featured Game', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Show featured games
            },
          ),
        ),
        const SizedBox(height: 4),
        Card(
          color: Colors.amber.shade50,
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: const Text('Featured Venue', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Show featured venues
            },
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getFilteredMatches() {
    var matches = widget.controller.discoveryPickupMatches;
    
    // Apply filters
    if (_selectedSport != null) {
      matches = matches.where((m) => 
        (m['sport'] as String?)?.toLowerCase() == _selectedSport?.toLowerCase()
      ).toList();
    }
    
    if (_selectedGameType != null) {
      matches = matches.where((m) {
        final mode = m['mode'] as String?;
        if (_selectedGameType == 'team') {
          return mode == 'team_vs_team';
        } else if (_selectedGameType == 'individual') {
          return mode != 'team_vs_team';
        }
        return true;
      }).toList();
    }
    
    if (_selectedDate != null) {
      matches = matches.where((m) {
        final startTime = m['start_time'] as DateTime?;
        if (startTime == null) return false;
        return startTime.year == _selectedDate!.year &&
               startTime.month == _selectedDate!.month &&
               startTime.day == _selectedDate!.day;
      }).toList();
    }
    
    if (_selectedReadiness != null) {
      matches = matches.where((m) {
        final proficiency = (m['proficiency_level'] as String?)?.toLowerCase();
        if (proficiency == null) return false;
        return proficiency == _selectedReadiness?.toLowerCase();
      }).toList();
    }
    
    if (_minSpotsLeft != null || _maxSpotsLeft != null) {
      matches = matches.where((m) {
        final spotsLeft = m['spots_left'] as int?;
        if (spotsLeft == null) return false;
        if (_minSpotsLeft != null && spotsLeft < _minSpotsLeft!) return false;
        if (_maxSpotsLeft != null && spotsLeft > _maxSpotsLeft!) return false;
        return true;
      }).toList();
    }
    
    // Filter by distance within the 100-mile range already loaded
    // Initial load limits to 100 miles, user can filter further (e.g., 25, 50 miles)
    if (_maxDistance < 100) {
      matches = matches.where((m) {
        final distance = m['distance_miles'] as double?;
        if (distance == null) {
          // If distance couldn't be calculated, exclude it when filtering by distance
          // This ensures consistent filtering behavior
          return false;
        }
        return distance <= _maxDistance;
      }).toList();
    }
    // When "Any Distance" (100 miles) is selected, show all games within the 100-mile range
    
    return matches;
  }
  
  Widget _buildResultsFeed() {
    final filteredMatches = _getFilteredMatches();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Results Feed',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            Text(
              '${filteredMatches.length} ${filteredMatches.length == 1 ? 'game' : 'games'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...filteredMatches.map((match) => _buildResultCard(match)),
      ],
    );
  }

  Widget _buildResultCard(Map<String, dynamic> match) {
    final sport = match['sport'] as String? ?? '';
    final mode = match['mode'] as String? ?? '';
    final numPlayers = match['num_players'] as int?;
    final startDt = match['start_time'] as DateTime?;
    final zip = match['zip_code'] as String?;
    final canAccept = match['can_accept'] as bool? ?? true;
    final spotsLeft = match['spots_left'] as int?;
    final acceptedCount = match['accepted_count'] as int? ?? 0;
    final requestId = match['request_id'] as String?;
    final sportEmoji = _getSportEmoji(sport);
    final distance = _calculateDistance(match);
    
    // Determine match type display
    String matchType;
    if (mode == 'team_vs_team') {
      matchType = 'Team Match';
    } else if (numPlayers != null) {
      matchType = 'Individual ($numPlayers players)';
    } else {
      matchType = 'Pickup';
    }
    
    final timeStr = _formatTime(startDt);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // TODO: Show match details
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sport, Type, Distance row
              Row(
                children: [
                  Text('$sportEmoji ${_displaySport(sport)}', 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Text(' • '),
                  Text(matchType),
                  const Text(' • '),
                  Text(distance),
                ],
              ),
              
              // Team match indicator
              if (mode == 'team_vs_team') ...[
                const SizedBox(height: 8),
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
              
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    timeStr,
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                  ),
                  if (mode != 'team_vs_team' && spotsLeft != null) ...[
                    const Text(' | '),
                    Icon(Icons.people, size: 16, color: spotsLeft! > 0 ? Colors.green : Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      '$spotsLeft spots left',
                      style: TextStyle(
                        color: spotsLeft! > 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else ...[
                    const Text(' | '),
                    const Icon(Icons.attach_money, size: 16, color: Colors.blue),
                    const SizedBox(width: 4),
                    const Text(
                      '\$10',
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Join/Request button (conditional for team games)
              if (mode == 'team_vs_team' && !canAccept) ...[
                // User is not an admin of a team in this sport
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
              ] else ...[
                // Can join/accept
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (mode == 'team_vs_team') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Request to join ${_displaySport(sport)} team match')),
                        );
                      } else {
                        // Individual game - request to join
                        await _requestToJoinIndividualGame(requestId!);
                      }
                    },
                    child: Text(mode == 'team_vs_team' ? 'Request to Join' : 'Request to Join'),
                  ),
                ),
                // Show organizer approval message for individual games
                if (mode != 'team_vs_team') ...[
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No games available',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Check back later for new matches',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

}

