import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

void main() async {
  final zip1 = '08823';
  final zip2 = '08902';
  
  print('🔍 Verifying distance between ZIP codes:');
  print('   User ZIP: $zip1');
  print('   Game ZIP: $zip2');
  print('');
  
  final distance = await calculateDistance(zip1, zip2);
  if (distance != null) {
    print('✅ Calculated distance: ${distance.toStringAsFixed(2)} miles');
    print('');
    if ((distance - 37).abs() < 2.0) {
      print('✅ Distance is approximately 37 miles (within 2 miles tolerance)');
    } else {
      print('⚠️  Distance differs from expected 37 miles');
      print('   Difference: ${(distance - 37).abs().toStringAsFixed(2)} miles');
    }
  } else {
    print('❌ Failed to calculate distance');
  }
}

Future<double?> calculateDistance(String zip1, String zip2) async {
  try {
    // Get coordinates for both ZIPs
    final coords1 = await getCoordinates(zip1);
    final coords2 = await getCoordinates(zip2);
    
    if (coords1 == null || coords2 == null) {
      print('❌ Could not get coordinates');
      return null;
    }
    
    print('📍 Coordinates:');
    print('   ZIP $zip1: (${coords1['lat']}, ${coords1['lng']})');
    print('   ZIP $zip2: (${coords2['lat']}, ${coords2['lng']})');
    print('');
    
    // Calculate distance
    final distanceMeters = Geolocator.distanceBetween(
      coords1['lat']!,
      coords1['lng']!,
      coords2['lat']!,
      coords2['lng']!,
    );
    
    final distanceMiles = distanceMeters * 0.000621371;
    return distanceMiles;
  } catch (e) {
    print('❌ Error: $e');
    return null;
  }
}

Future<Map<String, double>?> getCoordinates(String zip) async {
  try {
    // Get city/state from ZIP
    final zipUrl = Uri.parse('https://api.zippopotam.us/us/$zip');
    final zipResponse = await http.get(zipUrl).timeout(const Duration(seconds: 5));
    
    String? city, state;
    if (zipResponse.statusCode == 200) {
      final zipData = json.decode(zipResponse.body);
      final places = zipData['places'] as List?;
      if (places != null && places.isNotEmpty) {
        final place = places[0] as Map<String, dynamic>;
        city = place['place name'] as String?;
        state = place['state abbreviation'] as String?;
      }
    }
    
    // Geocode using Nominatim
    final query = city != null && state != null 
        ? '$city, $state, USA'
        : '$zip, USA';
    
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
