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

  @override
  void initState() {
    super.initState();
    _controller = HomeTabsController(Supabase.instance.client);
    _controller.addListener(_onControllerChanged);

    _controller.init().then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_initialPopupShown) return;
        _initialPopupShown = true;
        await _controller.showCreateInstantMatchSheet(context);
      });
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.disposeRealtime();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
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
        return 'Accepted';
      case 'declined':
        return 'Declined';
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

  Widget _buildLikelihoodBar({
    required String teamLabel,
    required int acceptedCount,
  }) {
    // Cricket default
    const int maxPlayers = 11;
    final clamped = acceptedCount.clamp(0, maxPlayers);
    final pct = clamped / maxPlayers;
    final pctText = (pct * 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$teamLabel likelihood: $clamped/$maxPlayers players ($pctText%)',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: pct, minHeight: 6),
        ),
      ],
    );
  }

  // ---------- SECTIONS ----------

  Widget _buildTeamVsTeamInvitesSection() {
    if (_controller.teamVsTeamInvites.isEmpty) return const SizedBox.shrink();

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
            final st1 = req['start_time_1'] ?? req['time_slot_1'];
            if (st1 is String) startDt = DateTime.tryParse(st1);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text('Team match request (${_controller.displaySport(sport)})'),
                subtitle: Text(
                  [
                    'ZIP: $zip',
                    if (startDt != null) _formatTimeRange(startDt, null),
                  ].join(' • '),
                ),
                trailing: ElevatedButton(
                  onPressed: () => _controller.approveInvite(
                    context: context,
                    invite: inv,
                  ),
                  child: const Text('Approve'),
                ),
              ),
            );
          }),
        ],
      ),
    );
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
          'You don\'t have any confirmed games yet.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your confirmed team matches',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._controller.confirmedTeamMatches.map((m) {
            final reqId = m['request_id'] as String;
            final teamAId = m['team_a_id'] as String;
            final teamBId = m['team_b_id'] as String;
            final sport = m['sport'] as String? ?? '';
            final teamAName = m['team_a_name'] as String? ?? 'Team A';
            final teamBName = m['team_b_name'] as String? ?? 'Team B';

            final List<Map<String, dynamic>> teamAPlayers =
                (m['team_a_players'] as List).cast<Map<String, dynamic>>();
            final List<Map<String, dynamic>> teamBPlayers =
                (m['team_b_players'] as List).cast<Map<String, dynamic>>();

            final DateTime? startDt = m['start_time'] as DateTime?;
            final DateTime? endDt = m['end_time'] as DateTime?;
            final String? venue = m['venue'] as String?;
            final bool canSwitchSide = (m['can_switch_side'] as bool?) ?? false;

            // which team am I currently on?
            String? myTeamId;
            if (teamAPlayers.any((p) => p['user_id'] == _controller.currentUserId)) {
              myTeamId = teamAId;
            } else if (teamBPlayers.any((p) => p['user_id'] == _controller.currentUserId)) {
              myTeamId = teamBId;
            }

            final mySidePlayers = myTeamId == teamAId ? teamAPlayers : teamBPlayers;
            final theirSidePlayers = myTeamId == teamAId ? teamBPlayers : teamAPlayers;

            final myStatus = mySidePlayers
                .firstWhere(
                  (p) => p['user_id'] == _controller.currentUserId,
                  orElse: () => {'status': 'pending'},
                )['status'] as String;

            final teamAAccepted = teamAPlayers
                .where((p) => (p['status'] as String).toLowerCase() == 'accepted')
                .length;
            final teamBAccepted = teamBPlayers
                .where((p) => (p['status'] as String).toLowerCase() == 'accepted')
                .length;

            final otherTeamId = myTeamId == teamAId ? teamBId : teamAId;
            final otherTeamName = myTeamId == teamAId ? teamBName : teamAName;

            final showReminder =
                myTeamId != null && _controller.isAdminOfTeam(myTeamId);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$teamAName vs $teamBName',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text('Sport: ${_controller.displaySport(sport)}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(_formatTimeRange(startDt, endDt),
                        style: const TextStyle(fontSize: 13, color: Colors.black87)),

                    if (venue != null && venue.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              venue,
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Chip(
                          label: Text('You: ${_statusLabel(myStatus).toUpperCase()}'),
                          backgroundColor: _statusChipColor(myStatus),
                          labelStyle: TextStyle(
                            color: _statusTextColor(myStatus),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (showReminder)
                          OutlinedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reminder placeholder (wire later).')),
                              );
                            },
                            child: const Text('Send reminder to my team'),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    if (myTeamId != null) ...[
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () => _controller.setMyAttendance(
                              context: context,
                              requestId: reqId,
                              teamId: myTeamId!,
                              status: 'accepted',
                            ),
                            child: const Text('Accept'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _controller.setMyAttendance(
                              context: context,
                              requestId: reqId,
                              teamId: myTeamId!,
                              status: 'declined',
                            ),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                      if (canSwitchSide)
                        TextButton.icon(
                          onPressed: () => _controller.switchMyTeamForMatch(
                            context: context,
                            requestId: reqId,
                            newTeamId: otherTeamId,
                          ),
                          icon: const Icon(Icons.swap_horiz),
                          label: Text('Switch to play for $otherTeamName'),
                        ),
                    ],

                    const SizedBox(height: 8),

                    _buildLikelihoodBar(teamLabel: teamAName, acceptedCount: teamAAccepted),
                    const SizedBox(height: 4),
                    _buildLikelihoodBar(teamLabel: teamBName, acceptedCount: teamBAccepted),

                    const Divider(height: 16),

                    Text('$teamAName players', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: teamAPlayers.map((p) {
                        final status = p['status'] as String;
                        return Chip(
                          label: Text(
                            '${p['name']} (${_statusLabel(status)})',
                            style: TextStyle(
                              color: _statusTextColor(status),
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: _statusChipColor(status),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 8),

                    Text('$teamBName players', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: theirSidePlayers.map((p) {
                        final status = p['status'] as String;
                        return Chip(
                          label: Text(
                            '${p['name']} (${_statusLabel(status)})',
                            style: TextStyle(
                              color: _statusTextColor(status),
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: _statusChipColor(status),
                        );
                      }).toList(),
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

  // ---------- TABS ----------

  Widget _buildHomeTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _controller.loadAdminTeamsAndInvites();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.green.shade50,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.flash_on, color: Colors.white),
                  ),
                  title: const Text('Create instant match',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Set up a quick match now and find teams or players nearby.'),
                  onTap: () => _controller.showCreateInstantMatchSheet(context),
                ),
              ),
            ),
            _buildTeamVsTeamInvitesSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMyGamesTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('My Games')),
      body: RefreshIndicator(
        onRefresh: _controller.loadConfirmedTeamMatches,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildConfirmedMatchesSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildWhatsNewTab() {
    return Scaffold(
      appBar: AppBar(title: const Text("What's New")),
      body: const Center(
        child: Text("What’s New coming soon."),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentTabBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _controller.selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: 'My Games'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'My Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.new_releases_outlined), label: "What's New"),
        ],
      ),
    );
  }
}
