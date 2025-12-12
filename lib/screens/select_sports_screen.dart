import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectSportsScreen extends StatefulWidget {
  const SelectSportsScreen({super.key});

  @override
  State<SelectSportsScreen> createState() => _SelectSportsScreenState();
}

class _SelectSportsScreenState extends State<SelectSportsScreen> {
  // You can expand this list later
  final List<String> _allSports = const [
    'Badminton',
    'Cricket',
    'Tennis',
    'Table Tennis',
    'Pickleball',
    'Football',
    'Basketball',
    'Volleyball',
  ];

  final Set<String> _selectedSports = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingSelections();
  }

  Future<void> _loadExistingSelections() async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) return;

    final rows = await supa
        .from('user_sports')
        .select('sport')
        .eq('user_id', user.id);

    setState(() {
      for (final row in rows as List) {
        final sport = (row['sport'] as String?) ?? '';
        if (sport.isNotEmpty) {
          // Stored as lowercase, display as capitalized
          _selectedSports.add(_toDisplaySport(sport));
        }
      }
    });
  }

  String _toStorageSport(String displaySport) =>
      displaySport.toLowerCase().replaceAll(' ', '_');

  String _toDisplaySport(String storageSport) {
    final withSpaces = storageSport.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }

  Future<void> _saveSports() async {
    setState(() => _loading = true);

    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) return;

    // 1) Clear old selections
    await supa.from('user_sports').delete().eq('user_id', user.id);

    // 2) Insert new selections
    if (_selectedSports.isNotEmpty) {
      final rows = _selectedSports
          .map((sport) => {
                'user_id': user.id,
                'sport': _toStorageSport(sport),
                'skill_level': 'intermediate', // later: let user choose
              })
          .toList();

      await supa.from('user_sports').insert(rows);
    }

    setState(() => _loading = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sports interests saved')),
    );
    Navigator.of(context).pop(); // go back to previous screen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Sports')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select the sports you are interested in.',
              style: TextStyle(fontSize: 16),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _allSports.length,
              itemBuilder: (context, index) {
                final sport = _allSports[index];
                final selected = _selectedSports.contains(sport);
                return CheckboxListTile(
                  title: Text(sport),
                  value: selected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedSports.add(sport);
                      } else {
                        _selectedSports.remove(sport);
                      }
                    });
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _loading ? null : _saveSports,
              child: Text(_loading ? 'Saving...' : 'Save Sports'),
            ),
          ),
        ],
      ),
    );
  }
}
