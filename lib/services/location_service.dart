import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const String _keyLocationMode = 'location_mode'; // 'auto' or 'manual'
  static const String _keyManualLocation = 'manual_location';
  static const String _keyManualCity = 'manual_city';
  static const String _keyManualZip = 'manual_zip';

  /// Get current location display string
  /// Returns manual location if set, otherwise device location
  static Future<String> getCurrentLocationDisplay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(_keyLocationMode) ?? 'auto';

      if (mode == 'manual') {
        // Use manually set location
        final manualLocation = prefs.getString(_keyManualLocation);
        if (manualLocation != null && manualLocation.isNotEmpty) {
          return manualLocation;
        }
      }

      // Use device location - no artificial timeout, let it try naturally
      final position = await _getCurrentPosition();
      
      if (position != null) {
        final cityName = await _getCityFromPosition(position);
        if (cityName != null) {
          // Cache the location for future use
          await prefs.setString('cached_location', cityName);
          await prefs.setDouble('cached_lat', position.latitude);
          await prefs.setDouble('cached_lng', position.longitude);
          return cityName;
        }
      }

      // Try to use cached location
      final cached = prefs.getString('cached_location');
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }

      return 'Location';
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting location: $e');
      }
      // Try cached location on error
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('cached_location') ?? 'Location';
      } catch (_) {
        return 'Location';
      }
    }
  }

  /// Get current coordinates (latitude, longitude)
  /// Returns Map with 'lat' and 'lng' keys
  static Future<Map<String, double>?> getCurrentCoordinates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(_keyLocationMode) ?? 'auto';

      if (mode == 'manual') {
        // Use manually set coordinates
        final lat = prefs.getDouble('manual_lat');
        final lng = prefs.getDouble('manual_lng');
        if (lat != null && lng != null) {
          return {'lat': lat, 'lng': lng};
        }
      }

      // Use device location
      final position = await _getCurrentPosition();
      
      if (position != null) {
        // Cache coordinates
        await prefs.setDouble('cached_lat', position.latitude);
        await prefs.setDouble('cached_lng', position.longitude);
        return {
          'lat': position.latitude,
          'lng': position.longitude,
        };
      }

      // Try cached coordinates
      final cachedLat = prefs.getDouble('cached_lat');
      final cachedLng = prefs.getDouble('cached_lng');
      if (cachedLat != null && cachedLng != null) {
        return {'lat': cachedLat, 'lng': cachedLng};
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting coordinates: $e');
      }
      // Try cached coordinates on error
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedLat = prefs.getDouble('cached_lat');
        final cachedLng = prefs.getDouble('cached_lng');
        if (cachedLat != null && cachedLng != null) {
          return {'lat': cachedLat, 'lng': cachedLng};
        }
      } catch (_) {}
      return null;
    }
  }

  /// Calculate distance between two coordinates in miles
  static double calculateDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    // Use Geolocator's distance calculation (returns meters)
    final distanceInMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    // Convert to miles
    return distanceInMeters * 0.000621371;
  }

  /// Set manual location override
  static Future<void> setManualLocation({
    required String displayName,
    String? zipCode,
    double? latitude,
    double? longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocationMode, 'manual');
    await prefs.setString(_keyManualLocation, displayName);
    
    if (zipCode != null) {
      await prefs.setString(_keyManualZip, zipCode);
    }
    
    // If coordinates provided, store them
    if (latitude != null && longitude != null) {
      await prefs.setDouble('manual_lat', latitude);
      await prefs.setDouble('manual_lng', longitude);
      await prefs.setDouble('cached_lat', latitude);
      await prefs.setDouble('cached_lng', longitude);
    } else if (zipCode != null) {
      // Try to get coordinates from ZIP code
      try {
        final zipResult = await _searchByZip(zipCode);
        if (zipResult != null) {
          // Use geocoding to get coordinates
          final locations = await locationFromAddress('$displayName, USA');
          if (locations.isNotEmpty) {
            await prefs.setDouble('manual_lat', locations.first.latitude);
            await prefs.setDouble('manual_lng', locations.first.longitude);
            await prefs.setDouble('cached_lat', locations.first.latitude);
            await prefs.setDouble('cached_lng', locations.first.longitude);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[LocationService] Could not get coordinates for manual location: $e');
        }
      }
    }
    
    await prefs.setString(_keyManualCity, displayName);
  }

  /// Switch back to auto (device) location
  static Future<void> useAutoLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocationMode, 'auto');
  }

  /// Check if using manual location
  static Future<bool> isUsingManualLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyLocationMode) ?? 'auto';
    return mode == 'manual';
  }

  /// Get current device position
  static Future<Position?> _getCurrentPosition() async {
    try {
      if (kDebugMode) {
        print('[LocationService] Starting position request...');
      }
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (kDebugMode) {
        print('[LocationService] Location service enabled: $serviceEnabled');
      }
      if (!serviceEnabled) {
        if (kDebugMode) {
          print('[LocationService] Location services are disabled');
        }
        return null;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (kDebugMode) {
        print('[LocationService] Current permission: $permission');
      }
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (kDebugMode) {
          print('[LocationService] Permission after request: $permission');
        }
        if (permission == LocationPermission.denied) {
          if (kDebugMode) {
            print('[LocationService] Location permission denied');
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          print('[LocationService] Location permission permanently denied');
        }
        return null;
      }

      if (kDebugMode) {
        print('[LocationService] Getting position...');
      }
      
      // Get current position - remove timeLimit for web compatibility
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(
        const Duration(seconds: 15), // Longer timeout for web
        onTimeout: () {
          if (kDebugMode) {
            print('[LocationService] Position request timed out after 15s');
          }
          throw TimeoutException('Location request timed out');
        },
      );
      
      if (kDebugMode) {
        print('[LocationService] Got position: ${position.latitude}, ${position.longitude}');
      }
      
      return position;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting position: $e');
      }
      return null;
    }
  }

  /// Convert position to city name
  static Future<String?> _getCityFromPosition(Position position) async {
    try {
      // Use geocoding package for reverse geocoding
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality ?? place.subAdministrativeArea;
        final state = place.administrativeArea;

        if (city != null && state != null) {
          // Return abbreviated state (e.g., "Edison, NJ")
          final stateAbbr = _getStateAbbreviation(state);
          return '$city, $stateAbbr';
        } else if (city != null) {
          return city;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting city from position: $e');
      }
      return null;
    }
  }

  /// Convert position to ZIP code
  static Future<String?> _getZipFromPosition(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        return placemarks.first.postalCode;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error getting ZIP from position: $e');
      }
      return null;
    }
  }

  /// Search for locations by name or ZIP code
  static Future<List<Map<String, String>>> searchLocations(String query) async {
    final results = <Map<String, String>>[];

    // If query looks like a ZIP code, search by ZIP
    if (RegExp(r'^\d{5}$').hasMatch(query)) {
      final zipResult = await _searchByZip(query);
      if (zipResult != null) {
        results.add(zipResult);
      }
    } else {
      // Search by city name
      final cityResults = await _searchByCity(query);
      results.addAll(cityResults);
    }

    return results;
  }

  /// Search location by ZIP code
  static Future<Map<String, String>?> _searchByZip(String zipCode) async {
    try {
      final url = Uri.parse('https://api.zippopotam.us/us/$zipCode');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final place = places[0] as Map<String, dynamic>;
          final city = place['place name'] as String?;
          final state = place['state abbreviation'] as String?;
          if (city != null && state != null) {
            return {
              'display': '$city, $state',
              'zip': zipCode,
              'city': city,
              'state': state,
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error searching by ZIP: $e');
      }
    }
    return null;
  }

  /// Search locations by city name
  static Future<List<Map<String, String>>> _searchByCity(String query) async {
    try {
      // Use geocoding to search for locations
      final locations = await locationFromAddress('$query, USA');

      if (locations.isNotEmpty) {
        final results = <Map<String, String>>[];

        for (final location in locations.take(5)) {
          try {
            final placemarks = await placemarkFromCoordinates(
              location.latitude,
              location.longitude,
            );

            if (placemarks.isNotEmpty) {
              final place = placemarks.first;
              final city = place.locality ?? place.subAdministrativeArea;
              final state = place.administrativeArea;
              final zip = place.postalCode;

              if (city != null && state != null && zip != null) {
                final stateAbbr = _getStateAbbreviation(state);
                results.add({
                  'display': '$city, $stateAbbr',
                  'zip': zip,
                  'city': city,
                  'state': stateAbbr,
                });
              }
            }
          } catch (e) {
            // Skip this location if there's an error
            continue;
          }
        }

        return results;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[LocationService] Error searching by city: $e');
      }
    }
    return [];
  }

  /// Get state abbreviation from full name
  static String _getStateAbbreviation(String stateName) {
    final stateMap = {
      'Alabama': 'AL', 'Alaska': 'AK', 'Arizona': 'AZ', 'Arkansas': 'AR',
      'California': 'CA', 'Colorado': 'CO', 'Connecticut': 'CT', 'Delaware': 'DE',
      'Florida': 'FL', 'Georgia': 'GA', 'Hawaii': 'HI', 'Idaho': 'ID',
      'Illinois': 'IL', 'Indiana': 'IN', 'Iowa': 'IA', 'Kansas': 'KS',
      'Kentucky': 'KY', 'Louisiana': 'LA', 'Maine': 'ME', 'Maryland': 'MD',
      'Massachusetts': 'MA', 'Michigan': 'MI', 'Minnesota': 'MN', 'Mississippi': 'MS',
      'Missouri': 'MO', 'Montana': 'MT', 'Nebraska': 'NE', 'Nevada': 'NV',
      'New Hampshire': 'NH', 'New Jersey': 'NJ', 'New Mexico': 'NM', 'New York': 'NY',
      'North Carolina': 'NC', 'North Dakota': 'ND', 'Ohio': 'OH', 'Oklahoma': 'OK',
      'Oregon': 'OR', 'Pennsylvania': 'PA', 'Rhode Island': 'RI', 'South Carolina': 'SC',
      'South Dakota': 'SD', 'Tennessee': 'TN', 'Texas': 'TX', 'Utah': 'UT',
      'Vermont': 'VT', 'Virginia': 'VA', 'Washington': 'WA', 'West Virginia': 'WV',
      'Wisconsin': 'WI', 'Wyoming': 'WY',
    };

    return stateMap[stateName] ?? stateName;
  }
}

