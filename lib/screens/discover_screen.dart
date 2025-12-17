import 'package:flutter/material.dart';

import 'home_tabs/home_tabs_controller.dart';

class DiscoverScreen extends StatefulWidget {
  final HomeTabsController controller;
  final VoidCallback? onCreateGame;
  
  const DiscoverScreen({super.key, required this.controller, this.onCreateGame});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();
  String _selectedSport = '';
  String _selectedFilter = '5v5'; // Default selected filter
  bool _showNearby = true;
  bool _showToday = false;
  bool _showIndoor = false;

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

  // Calculate distance (mock for now - would need location services)
  String _calculateDistance(String? zip) {
    // TODO: Implement actual distance calculation
    return '2 miles';
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
              
              // Filter Chips
              _buildFilterChips(),
              
              // Content
              Expanded(
                child: widget.controller.loadingDiscoveryMatches
                    ? const Center(child: CircularProgressIndicator())
                    : widget.controller.discoveryPickupMatches.isEmpty
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

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('📍 Nearby', _showNearby, () {
              setState(() => _showNearby = !_showNearby);
            }),
            const SizedBox(width: 8),
            _buildFilterChip('⚽ Soccer', _selectedSport == 'soccer', () {
              setState(() => _selectedSport = _selectedSport == 'soccer' ? '' : 'soccer');
            }),
            const SizedBox(width: 8),
            _buildFilterChip('Today', _showToday, () {
              setState(() => _showToday = !_showToday);
            }),
            const SizedBox(width: 8),
            _buildFilterChip('Indoor', _showIndoor, () {
              setState(() => _showIndoor = !_showIndoor);
            }),
            const SizedBox(width: 8),
            _buildFilterChip('5v5', _selectedFilter == '5v5', () {
              setState(() => _selectedFilter = '5v5');
            }, highlightSelected: true),
          ],
        ),
      ),
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

  Widget _buildResultsFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Results Feed',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ...widget.controller.discoveryPickupMatches.map((match) => _buildResultCard(match)),
      ],
    );
  }

  Widget _buildResultCard(Map<String, dynamic> match) {
    final sport = match['sport'] as String? ?? '';
    final numPlayers = match['num_players'] as int?;
    final startDt = match['start_time'] as DateTime?;
    final zip = match['zip_code'] as String?;
    final sportEmoji = _getSportEmoji(sport);
    final distance = _calculateDistance(zip);
    final format = numPlayers != null ? '$numPlayers v$numPlayers' : 'Pickup';
    final timeStr = _formatTime(startDt);
    // TODO: Calculate popularity based on match data
    
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
              Row(
                children: [
                  Text('$sportEmoji ${_displaySport(sport)}', 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Text(' • '),
                  Text(format),
                  const Text(' • '),
                  Text(distance),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    timeStr,
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                  ),
                  const Text(' | '),
                  const Icon(Icons.attach_money, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  const Text(
                    '\$10',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              // Popular badge can be added here when popularity is calculated
              // if (isPopular) ...[
              //   const SizedBox(height: 8),
              //   Row(
              //     children: [
              //       const Icon(Icons.local_fire_department, size: 16, color: Colors.orange),
              //       const SizedBox(width: 4),
              //       const Text('Popular', style: TextStyle(color: Colors.orange)),
              //     ],
              //   ),
              // ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: Show join dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Join ${_displaySport(sport)} match')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Join'),
                ),
              ),
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

