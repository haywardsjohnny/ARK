import 'package:supabase_flutter/supabase_flutter.dart';

/// Sport-specific default values
class SportDefaults {
  static final SupabaseClient _supa = Supabase.instance.client;
  static Map<String, int>? _cache;

  /// Get the default number of players per team for a given sport
  /// First tries to fetch from database, falls back to hardcoded defaults
  static Future<int> getExpectedPlayersPerTeam(String sport) async {
    final normalized = sport.toLowerCase().trim();
    
    // Try to fetch from database first
    try {
      if (_cache == null) {
        await _loadCache();
      }
      
      if (_cache != null && _cache!.containsKey(normalized)) {
        return _cache![normalized]!;
      }
    } catch (e) {
      // If database fetch fails, fall back to hardcoded defaults
    }
    
    // Fallback to hardcoded defaults
    return _getHardcodedDefault(normalized);
  }

  /// Load cache from database
  static Future<void> _loadCache() async {
    try {
      final result = await _supa
          .from('sport_expected_players')
          .select('sport, expected_players_per_team');
      
      if (result is List) {
        _cache = {};
        for (final row in result) {
          final sportName = (row['sport'] as String?)?.toLowerCase().trim();
          final count = row['expected_players_per_team'] as int?;
          if (sportName != null && count != null) {
            _cache![sportName] = count;
          }
        }
      }
    } catch (e) {
      // If fetch fails, cache will remain null and we'll use hardcoded defaults
      _cache = null;
    }
  }

  /// Clear cache (call this after updating expected players)
  static void clearCache() {
    _cache = null;
  }

  /// Hardcoded fallback defaults
  static int _getHardcodedDefault(String normalized) {
    switch (normalized) {
      case 'cricket':
      case 'soccer':
      case 'football':
        return 11;
      case 'basketball':
        return 5;
      case 'volleyball':
        return 6;
      case 'pickleball':
      case 'tennis':
      case 'badminton':
        return 4;
      case 'table_tennis':
        return 2;
      default:
        return 11; // Default fallback
    }
  }

  /// Get display name for sport
  static String getDisplayName(String sport) {
    final withSpaces = sport.replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Update expected players for a sport in the database
  static Future<void> updateExpectedPlayers(String sport, int count) async {
    final normalized = sport.toLowerCase().trim();
    try {
      // First, check if the record exists
      final existing = await _supa
          .from('sport_expected_players')
          .select('sport')
          .eq('sport', normalized)
          .maybeSingle();
      
      if (existing != null) {
        // Update existing record
        await _supa
            .from('sport_expected_players')
            .update({
              'expected_players_per_team': count,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('sport', normalized);
      } else {
        // Insert new record
        await _supa
            .from('sport_expected_players')
            .insert({
              'sport': normalized,
              'expected_players_per_team': count,
            });
      }
      
      // Clear cache to force reload
      clearCache();
    } catch (e) {
      rethrow;
    }
  }
}

