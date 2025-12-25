import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

/// Verify distance calculation for a specific game
/// Usage: dart verify_distance.dart <game_id> <user_zip>
void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart verify_distance.dart <game_id> <user_zip>');
    print('Example: dart verify_distance.dart 81994b3a-9453-4317-ac85-6b1da4d9a439 08902');
    exit(1);
  }

  final gameId = args[0];
  final userZip = args[1];

  print('🔍 Verifying distance calculation...');
  print('Game ID: $gameId');
  print('User ZIP: $userZip');
  print('');

  // Note: This script requires direct database access or Supabase client
  // For now, we'll calculate distance between two ZIP codes
  // You'll need to manually provide the game's ZIP code
  
  if (args.length >= 3) {
    final gameZip = args[2];
    print('Game ZIP: $gameZip');
    print('');
    
    final distance = await calculateDistanceBetweenZipCodes(userZip, gameZip);
    if (distance != null) {
      print('✅ Calculated distance: ${distance.toStringAsFixed(2)} miles');
      print('');
      if ((distance - 37).abs() < 1.0) {
        print('✅ Distance matches expected value (37 miles)');
      } else {
        print('⚠️  Distance does NOT match expected value (37 miles)');
        print('   Difference: ${(distance - 37).abs().toStringAsFixed(2)} miles');
      }
    } else {
      print('❌ Failed to calculate distance');
    }
  } else {
    print('⚠️  Game ZIP code not provided.');
    print('To verify, run:');
    print('  dart verify_distance.dart $gameId $userZip <game_zip_code>');
    print('');
    print('To get the game ZIP code, query the database:');
    print('  SELECT zip_code FROM instant_match_requests WHERE id = \'$gameId\';');
  }
}

/// Calculate distance between two ZIP codes
Future<double?> calculateDistanceBetweenZipCodes(String zip1, String zip2) async {
  try {
    print('📍 Getting coordinates for ZIP codes...');
    
    // Get coordinates for ZIP1
    final coords1 = await getCoordinatesFromZip(zip1);
    if (coords1 == null) {
      print('❌ Could not get coordinates for ZIP1: $zip1');
      return null;
    }
    print('   ZIP1 ($zip1): (${coords1['lat']}, ${coords1['lng']})');
    
    // Get coordinates for ZIP2
    final coords2 = await getCoordinatesFromZip(zip2);
    if (coords2 == null) {
      print('❌ Could not get coordinates for ZIP2: $zip2');
      return null;
    }
    print('   ZIP2 ($zip2): (${coords2['lat']}, ${coords2['lng']})');
    print('');
    
    // Calculate distance
    final distanceInMeters = Geolocator.distanceBetween(
      coords1['lat']!,
      coords1['lng']!,
      coords2['lat']!,
      coords2['lng']!,
    );
    
    // Convert to miles
    final distanceInMiles = distanceInMeters * 0.000621371;
    
    return distanceInMiles;
  } catch (e) {
    print('❌ Error calculating distance: $e');
    return null;
  }
}

/// Get coordinates from ZIP code using zippopotam.us and Nominatim
Future<Map<String, double>?> getCoordinatesFromZip(String zipCode) async {
  try {
    // First, get city/state from ZIP
    final zipUrl = Uri.parse('https://api.zippopotam.us/us/$zipCode');
    final zipResponse = await http.get(zipUrl).timeout(const Duration(seconds: 5));
    
    if (zipResponse.statusCode == 200) {
      final zipData = json.decode(zipResponse.body);
      final places = zipData['places'] as List?;
      if (places != null && places.isNotEmpty) {
        final place = places[0] as Map<String, dynamic>;
        final city = place['place name'] as String?;
        final state = place['state abbreviation'] as String?;
        
        if (city != null && state != null) {
          // Geocode city, state
          final cityState = '$city, $state, USA';
          return await geocodeWithNominatim(cityState);
        }
      }
    }
    
    // Fallback: geocode ZIP directly
    return await geocodeWithNominatim('$zipCode, USA');
  } catch (e) {
    print('   ⚠️  Error getting ZIP data: $e');
    // Fallback: geocode ZIP directly
    return await geocodeWithNominatim('$zipCode, USA');
  }
}

/// Geocode using OpenStreetMap Nominatim
Future<Map<String, double>?> geocodeWithNominatim(String query) async {
  try {
    final encodedQuery = Uri.encodeComponent(query);
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=1');
    
    final response = await http.get(
      url,
      headers: {'User-Agent': 'SportsdugApp/1.0'},
    ).timeout(const Duration(seconds: 5));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      if (data.isNotEmpty) {
        final result = data[0] as Map<String, dynamic>;
        final lat = double.tryParse(result['lat']?.toString() ?? '');
        final lng = double.tryParse(result['lon']?.toString() ?? '');
        
        if (lat != null && lng != null) {
          return {'lat': lat, 'lng': lng};
        }
      }
    }
    return null;
  } catch (e) {
    return null;
  }
}

